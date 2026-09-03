#!/usr/bin/env python3
"""
Classify every migration file against a live database.

Used by scripts/reconcile-local-snapshot.sh. Writes one TSV row per migration
that the ledger does not record:

    <version>\t<verdict>\t<detail>

    BASELINE  every object the file is responsible for is present and current;
              re-running it would gain nothing and might destroy data, so it
              should be recorded in the ledger, not executed.
    APPLY     objects are missing. The file has to run.
    REVIEW    objects are missing AND the file carries a destructive statement
              (DROP TABLE / DELETE / TRUNCATE). Never executed automatically.

WHY NOT JUST REPLAY EVERY UNRECORDED FILE
    A restored production snapshot is not a contiguous prefix of the migration
    list, so "unrecorded" does not mean "not applied". Replaying a file the
    snapshot already contains is not free: 20260206000000 opens with
    DROP TABLE public.records_messages CASCADE.

WHY NOT JUST ASK WHETHER THE FILE APPLIES CLEANLY
    Most of these files are idempotent (CREATE OR REPLACE, IF NOT EXISTS), so a
    clean replay says nothing about whether they ever ran. Presence of the
    objects is the only signal that distinguishes the two, which is what this
    does.

THE THREE THINGS THAT MAKE THAT HARDER THAN IT SOUNDS
    Supersession  Several files define the same function. Only the last one
                  describes what the body should look like today; for the
                  earlier ones, existence is all that can be asked.
    Renames       20260714000000 renames responsible_control_troop and its
                  indexes. Probing 20260605150000 for the old index names finds
                  nothing and would wrongly conclude it never ran — re-running
                  it then re-adds a column a later migration removed.
    Deletions     20260713000000 drops objects an earlier file created. Their
                  absence is correct, not a hole.

    All three are resolved by reading the whole migration list first and asking
    what each object's *final* state should be.
"""

import argparse
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path

# ── SQL text handling ────────────────────────────────────────────────────────

DOLLAR_TAG = re.compile(r"\$[A-Za-z_][A-Za-z_0-9]*\$|\$\$")


def strip_comments(sql: str) -> str:
    """Remove comments that sit *outside* strings and function bodies.

    Two reasons this cannot be a regex. The migrations are commented in German,
    and 'Der View darf ...' matches a naive `create view (\\w+)` well enough to
    invent an object named 'darf' — so the comments have to go. But pg_proc
    stores a function body verbatim, comments included, so stripping them inside
    a dollar-quoted body makes every body comparison fail against a database
    that is perfectly up to date.
    """
    out, i, n = [], 0, len(sql)
    while i < n:
        ch = sql[i]
        if ch == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'":
                    if j + 1 < n and sql[j + 1] == "'":
                        j += 2
                        continue
                    break
                j += 1
            out.append(sql[i : j + 1])
            i = j + 1
            continue
        m = DOLLAR_TAG.match(sql, i)
        if m:
            tag = m.group(0)
            end = sql.find(tag, i + len(tag))
            end = n if end == -1 else end + len(tag)
            out.append(sql[i:end])
            i = end
            continue
        if sql.startswith("--", i):
            j = sql.find("\n", i)
            i = n if j == -1 else j
            out.append(" ")
            continue
        if sql.startswith("/*", i):
            j = sql.find("*/", i + 2)
            i = n if j == -1 else j + 2
            out.append(" ")
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def split_statements(sql: str):
    """Split on semicolons that are not inside a string or a dollar-quoted body."""
    out, buf, i, n = [], [], 0, len(sql)
    while i < n:
        ch = sql[i]
        if ch == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'":
                    if j + 1 < n and sql[j + 1] == "'":
                        j += 2
                        continue
                    break
                j += 1
            buf.append(sql[i : j + 1])
            i = j + 1
            continue
        m = DOLLAR_TAG.match(sql, i)
        if m:
            tag = m.group(0)
            end = sql.find(tag, i + len(tag))
            end = n if end == -1 else end + len(tag)
            buf.append(sql[i:end])
            i = end
            continue
        if ch == ";":
            out.append("".join(buf))
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    if "".join(buf).strip():
        out.append("".join(buf))
    return [s.strip() for s in out if s.strip()]


def norm(s: str) -> str:
    """Normalise SQL text for comparison.

    Whitespace around punctuation is collapsed as well, so that a body which
    was merely reformatted on its way into production — `format( 'x' )` against
    `format('x')` — does not read as drift. The comparison is deliberately
    lenient: the question it answers is whether re-running an idempotent
    CREATE OR REPLACE would change anything that matters.
    """
    s = re.sub(r"\s+", " ", s).strip().lower()
    return re.sub(r"\s*([(),;])\s*", r"\1", s)


def pg_ident(name: str) -> str:
    """Truncate to what PostgreSQL will actually store.

    Identifiers are cut to 63 bytes (NAMEDATALEN - 1). Several policies here are
    named in full sentences — one in 20260605150000 is 134 characters in the
    file and 63 in pg_policies — so comparing the file's spelling against the
    catalogue reports every one of them as missing.
    """
    return name.encode("utf-8")[:63].decode("utf-8", "ignore")


def unquote(ident: str) -> str:
    return ident.replace('"', "").strip().lower()


def qualify(ident: str, default_schema: str = "public") -> str:
    ident = unquote(ident)
    parts = ident.split(".") if "." in ident else [default_schema, ident]
    return ".".join(pg_ident(x) for x in parts)


# ── What a statement declares ────────────────────────────────────────────────

RE_TABLE = re.compile(r"^create\s+table\s+(?:if\s+not\s+exists\s+)?([\w.\"]+)", re.I)
RE_VIEW = re.compile(
    r"^create\s+(?:or\s+replace\s+)?(?:materialized\s+)?view\s+([\w.\"]+)", re.I
)
RE_FUNC = re.compile(
    r"^create\s+(?:or\s+replace\s+)?function\s+([\w.\"]+)\s*\(", re.I
)
RE_TRIGGER = re.compile(
    r"^create\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+([\w\"]+)"
    r"[\s\S]*?\bon\s+([\w.\"]+)",
    re.I,
)
RE_INDEX = re.compile(
    r"^create\s+(?:unique\s+)?index\s+(?:concurrently\s+)?"
    r"(?:if\s+not\s+exists\s+)?([\w\"]+)\s+on\s+([\w.\"]+)",
    re.I,
)
RE_CONSTRAINT = re.compile(
    r"^alter\s+table\s+(?:only\s+)?([\w.\"]+)[\s\S]*?\badd\s+constraint\s+([\w\"]+)", re.I
)
RE_ADD_COLUMN = re.compile(
    r"^alter\s+table\s+(?:only\s+)?([\w.\"]+)[\s\S]*?"
    r"\badd\s+column\s+(?:if\s+not\s+exists\s+)?([\w\"]+)",
    re.I,
)
RE_POLICY = re.compile(
    r"^create\s+policy\s+(?:\"([^\"]+)\"|([\w]+))\s+on\s+([\w.\"]+)", re.I
)
RE_DROP_POLICY = re.compile(
    r"^drop\s+policy\s+(?:if\s+exists\s+)?(?:\"([^\"]+)\"|([\w]+))\s+on\s+([\w.\"]+)", re.I
)
RE_SEC_INVOKER = re.compile(
    r"^alter\s+view\s+([\w.\"]+)\s+set\s*\([^)]*security_invoker\s*=\s*(true|on)", re.I
)
RE_BODY = re.compile(r"(\$[A-Za-z_][A-Za-z_0-9]*\$|\$\$)([\s\S]*?)\1")
RE_SEARCH_PATH = re.compile(r"^set\s+(?:local\s+)?search_path\s*(?:to|=)\s*(.+)$", re.I)

# Statements whose replay can destroy collected data.
RE_DESTRUCTIVE = re.compile(
    r"^\s*(drop\s+table|truncate|delete\s+from)\b", re.I
)

# Later files can retire an earlier file's objects. Both spellings appear.
RE_DROP = re.compile(
    r"^drop\s+(table|view|function|trigger|index|policy)\s+(?:if\s+exists\s+)?([\w.\"]+)"
    r"(?:\s*\([^)]*\))?(?:\s+on\s+([\w.\"]+))?",
    re.I,
)
RE_RENAME_IDX = re.compile(
    r"alter\s+index\s+(?:if\s+exists\s+)?([\w.\"]+)\s+rename\s+to\s+([\w\"]+)", re.I
)
RE_RENAME_COL = re.compile(
    r"alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?([\w.\"]+)[\s\S]{0,200}?"
    r"\brename\s+column\s+([\w\"]+)\s+to\s+([\w\"]+)",
    re.I,
)


class Migration:
    def __init__(self, path: Path):
        self.path = path
        self.version = path.name.split("_")[0]
        raw = path.read_text(encoding="utf-8", errors="replace")
        self.sql = strip_comments(raw)
        self.statements = split_statements(self.sql)
        self.destructive = [s for s in self.statements if RE_DESTRUCTIVE.match(s)]

        # objects this file declares: (kind, key) -> extra
        self.declares = {}
        self.func_bodies = {}
        self.view_stmts = {}

        # Several files do `SET search_path TO lookup;` and then create
        # unqualified objects. Resolving those against `public` invents holes
        # that are not there.
        schema = "public"
        for st in self.statements:
            sp = RE_SEARCH_PATH.match(st)
            if sp:
                first = sp.group(1).split(",")[0]
                if unquote(first) not in ("", "$user"):
                    schema = unquote(first)
                continue
            m = RE_TABLE.match(st)
            if m:
                self.declares[("table", qualify(m.group(1), schema))] = None
            m = RE_VIEW.match(st)
            if m:
                vname = qualify(m.group(1), schema)
                self.declares[("view", vname)] = None
                self.view_stmts[vname] = st
            m = RE_FUNC.match(st)
            if m:
                name = qualify(m.group(1), schema)
                self.declares[("function", name)] = None
                b = RE_BODY.search(st)
                if b:
                    self.func_bodies[name] = norm(b.group(2))
            m = RE_TRIGGER.match(st)
            if m:
                self.declares[
                    ("trigger", f"{pg_ident(unquote(m.group(1)))}@{qualify(m.group(2), schema).split('.')[-1]}")
                ] = None
            m = RE_INDEX.match(st)
            if m:
                self.declares[("index", pg_ident(unquote(m.group(1))))] = None
            m = RE_CONSTRAINT.match(st)
            if m:
                self.declares[("constraint", pg_ident(unquote(m.group(2))))] = None
            m = RE_ADD_COLUMN.match(st)
            if m:
                self.declares[
                    ("column", f"{qualify(m.group(1), schema)}.{pg_ident(unquote(m.group(2)))}")
                ] = None
            m = RE_POLICY.match(st)
            if m:
                pol = pg_ident((m.group(1) or m.group(2) or "").strip().lower())
                tbl = qualify(m.group(3), schema).split(".")[-1]
                self.declares[("policy", f"{pol}@{tbl}")] = None
            m = RE_SEC_INVOKER.match(st)
            if m:
                self.declares[("security_invoker", qualify(m.group(1), schema))] = None

        # objects this file retires or renames
        self.drops, self.renames = set(), {}
        schema = "public"
        for st in self.statements:
            sp = RE_SEARCH_PATH.match(st)
            if sp:
                first = sp.group(1).split(",")[0]
                if unquote(first) not in ("", "$user"):
                    schema = unquote(first)
                continue
            m = RE_DROP_POLICY.match(st)
            if m:
                pol = pg_ident((m.group(1) or m.group(2) or "").strip().lower())
                self.drops.add(("policy", f"{pol}@{qualify(m.group(3), schema).split('.')[-1]}"))
            m = RE_DROP.match(st)
            if m:
                kind, name = m.group(1).lower(), unquote(m.group(2))
                if kind == "trigger" and m.group(3):
                    self.drops.add(
                        ("trigger", f"{name}@{qualify(m.group(3), schema).split('.')[-1]}")
                    )
                elif kind in ("index", "policy"):
                    self.drops.add((kind, name.split(".")[-1]))
                else:
                    self.drops.add((kind, qualify(name, schema)))
        for m in RE_RENAME_IDX.finditer(self.sql):
            self.renames[("index", unquote(m.group(1)).split(".")[-1])] = unquote(m.group(2))
        for m in RE_RENAME_COL.finditer(self.sql):
            tbl = qualify(m.group(1), schema)
            self.renames[("column", f"{tbl}.{unquote(m.group(2))}")] = (
                f"{tbl}.{unquote(m.group(3))}"
            )


# ── Live database state ──────────────────────────────────────────────────────

QUERIES = {
    "table": "select schemaname||'.'||tablename from pg_tables",
    "view": ("select schemaname||'.'||viewname from pg_views "
             "union all select schemaname||'.'||matviewname from pg_matviews"),
    "trigger": ("select t.tgname||'@'||c.relname from pg_trigger t "
                "join pg_class c on c.oid=t.tgrelid where not t.tgisinternal"),
    "index": "select indexname from pg_indexes",
    "constraint": "select conname from pg_constraint",
    "column": ("select table_schema||'.'||table_name||'.'||column_name "
               "from information_schema.columns"),
    "policy": "select policyname||'@'||tablename from pg_policies",
    # 20260820000000 only flips security_invoker on a view; that is checkable.
    "security_invoker": ("select n.nspname||'.'||c.relname from pg_class c "
                         "join pg_namespace n on n.oid = c.relnamespace "
                         "where c.relkind = 'v' "
                         "and 'security_invoker=true' = any(c.reloptions)"),
}


class Database:
    def __init__(self, psql_argv):
        # How to reach psql, not where the database is: the production server
        # has no host psql client, so there the invocation is
        # `docker exec -i supabase-db psql -U postgres -d postgres`.
        self.psql_argv = psql_argv
        self.sets = {k: self._rows(q) for k, q in QUERIES.items()}
        # JSON, not a delimiter: function bodies contain newlines, tabs and
        # every quoting style there is, and any separator chosen here would
        # eventually appear inside one and silently corrupt the comparison.
        self.functions = {}
        payload = self._scalar(
            "select coalesce(json_agg(json_build_array("
            "n.nspname||'.'||p.proname, p.prosrc))::text, '[]') "
            "from pg_proc p join pg_namespace n on n.oid=p.pronamespace "
            "where n.nspname not in ('pg_catalog','information_schema','pg_toast')"
        )
        for name, src in json.loads(payload):
            self.functions.setdefault(name.lower(), []).append(norm(src or ""))
        self.sets["function"] = set(self.functions)

    def _scalar(self, sql):
        out = subprocess.run(
            self.psql_argv + ["--no-psqlrc", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
            capture_output=True, text=True,
        )
        if out.returncode != 0:
            sys.exit(f"query failed: {out.stderr.strip()}")
        return out.stdout.strip()

    def _rows(self, sql):
        out = subprocess.run(
            self.psql_argv + ["--no-psqlrc", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
            capture_output=True, text=True,
        )
        if out.returncode != 0:
            sys.exit(f"query failed: {out.stderr.strip()}")
        return {r.strip().lower() for r in out.stdout.splitlines() if r.strip()}

    # CREATE OR REPLACE VIEW can neither rename nor drop a column, so replaying
    # one statement against the live view answers "is this view the shape this
    # migration expects?" without touching anything. Only the shape errors count
    # — any other failure means the statement depends on something else in its
    # own migration, which the object probe already reports.
    SHAPE_ERRORS = (
        "cannot change name of view column",
        "cannot drop columns from view",
        "cannot change data type of view column",
    )

    def view_shape_differs(self, statement: str) -> bool:
        out = subprocess.run(
            self.psql_argv + ["--no-psqlrc", "-q", "-v", "ON_ERROR_STOP=1"],
            input=f"BEGIN;\n{statement};\nROLLBACK;\n",
            capture_output=True, text=True,
        )
        err = out.stderr.lower()
        return any(e in err for e in self.SHAPE_ERRORS)

    def ledger(self):
        exists = self._rows(
            "select count(*) from information_schema.tables "
            "where table_schema='supabase_migrations' and table_name='schema_migrations'"
        )
        if "1" not in exists:
            return set()
        return self._rows("select version from supabase_migrations.schema_migrations")

    def has(self, kind, key):
        return key in self.sets.get(kind, set())


# ── Classification ───────────────────────────────────────────────────────────

def classify(migs, db, ignore_ledger=False):
    recorded = set() if ignore_ledger else db.ledger()

    # An object's fate is decided by the LAST file that touches it.
    last_definer, retired, renamed_to = {}, {}, {}
    for m in migs:
        for obj in m.declares:
            last_definer[obj] = m.version
            retired.pop(obj, None)
        for obj in m.drops:
            retired[obj] = m.version
        for obj, new in m.renames.items():
            renamed_to[obj] = new

    # DROP TABLE takes its policies, triggers and columns with it. The migration
    # that created those never mentions them again, so without this they look
    # like holes forever — 20260709120000 drops the table 20260605120000 makes,
    # along with its two policies.
    dropped_tables = {
        key.split(".")[-1]: ver
        for (kind, key), ver in retired.items() if kind == "table"
    }
    if dropped_tables:
        for kind, key in list(last_definer):
            if kind in ("policy", "trigger"):
                tbl = key.rsplit("@", 1)[-1]
            elif kind == "column" and key.count(".") >= 2:
                tbl = key.rsplit(".", 2)[-2]
            else:
                continue
            if tbl in dropped_tables:
                retired.setdefault((kind, key), dropped_tables[tbl])

    def resolve(kind, key):
        """Follow renames applied by later migrations."""
        seen = 0
        while (kind, key) in renamed_to and seen < 8:
            key = renamed_to[(kind, key)]
            seen += 1
        return key

    rows = []
    for m in migs:
        if m.version in recorded:
            continue

        missing, stale, probeable = [], [], 0
        for kind, key in m.declares:
            if retired.get((kind, key), "") > m.version:
                continue  # a later migration removes it on purpose
            probeable += 1
            probe = resolve(kind, key)
            if not db.has(kind, probe):
                missing.append(f"{kind} {probe}")
                continue
            # Present — but an object can exist and still be the wrong version
            # of itself, and only the file that defines it last can say so.
            if last_definer.get((kind, key)) != m.version:
                continue
            if kind == "function" and key in m.func_bodies:
                if m.func_bodies[key] not in db.functions.get(probe, []):
                    stale.append(f"function {probe} (body differs)")
            elif kind == "view" and key in m.view_stmts:
                if db.view_shape_differs(m.view_stmts[key]):
                    stale.append(f"view {probe} (different shape)")

        if m.declares and probeable == 0:
            # Everything this file creates, a later migration deliberately
            # removes — 20260709120000 drops the table 20260605120000 adds.
            # Re-running it would resurrect what the newer file deleted.
            rows.append((m.version, "BASELINE",
                         "every object it creates is removed by a later migration"))
            continue

        if not probeable:
            # Nothing to look for: GRANT-only or DML-only files. This is not
            # evidence that the migration is missing — it is the absence of
            # evidence either way, and reporting it as "never ran" would send
            # `db push` at a production database on a guess.
            verdict = "REVIEW" if m.destructive else "UNKNOWN"
            detail = "nothing to probe (grants/DML only) — decide by hand" \
                if not m.destructive \
                else "nothing to probe, and it carries a destructive statement"
        elif missing or stale:
            verdict = "REVIEW" if m.destructive else "APPLY"
            detail = "; ".join(missing + stale)
            if m.destructive:
                detail += " [destructive: " + norm(m.destructive[0])[:60] + "]"
        else:
            verdict = "BASELINE"
            detail = f"{probeable} object(s) present and current"

        rows.append((m.version, verdict, detail))
    return rows



# ── Remedies for the two blockers that recur on every restored snapshot ──────

RE_FK = re.compile(
    r"(add\s+constraint\s+[\w\"]+\s+foreign\s+key[\s\S]*?)(?=$)", re.I
)


def fk_not_valid(sql: str) -> str:
    """Append NOT VALID to every ADD CONSTRAINT ... FOREIGN KEY.

    A partial dump leaves rows pointing at parents it did not bring along, so
    ADD CONSTRAINT fails while validating the existing table. NOT VALID still
    enforces every INSERT and UPDATE from that point on; only the rows already
    in the table are exempt, and `VALIDATE CONSTRAINT` closes that later.
    """
    out = []
    for st in split_statements(strip_comments(sql)):
        low = norm(st)
        if (
            low.startswith("alter table")
            and "add constraint" in low
            and "foreign key" in low
            and "not valid" not in low
        ):
            st = st.rstrip() + " NOT VALID"
        out.append(st + ";")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db-url", help="connect with the host psql client")
    ap.add_argument("--psql", help="full psql invocation to use instead of --db-url, "
                                   "e.g. 'docker exec -i supabase-db psql -U postgres -d postgres'")
    ap.add_argument("--migrations-dir", default="supabase/migrations")
    ap.add_argument("--ignore-ledger", action="store_true",
                    help="classify every file, not just unrecorded ones (self-test)")
    ap.add_argument("--declares", metavar="FILE",
                    help="print the objects one migration declares, then exit")
    ap.add_argument("--fk-not-valid", metavar="FILE",
                    help="print the migration with NOT VALID on its foreign keys, then exit")
    args = ap.parse_args()

    if args.declares:
        for kind, key in Migration(Path(args.declares)).declares:
            print(f"{kind}\t{key}")
        return
    if args.fk_not_valid:
        sys.stdout.write(
            fk_not_valid(Path(args.fk_not_valid).read_text(encoding="utf-8"))
        )
        return

    paths = sorted(Path(args.migrations_dir).glob("*.sql"))
    if not paths:
        sys.exit(f"no migration files in {args.migrations_dir}")

    if args.psql:
        psql_argv = shlex.split(args.psql)
    elif args.db_url:
        psql_argv = ["psql", args.db_url]
    else:
        sys.exit("classification needs --db-url or --psql")
    migs = [Migration(p) for p in paths]
    db = Database(psql_argv)
    for version, verdict, detail in classify(migs, db, args.ignore_ledger):
        print(f"{version}\t{verdict}\t{detail}")


if __name__ == "__main__":
    main()
