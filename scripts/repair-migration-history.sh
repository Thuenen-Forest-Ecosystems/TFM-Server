#!/usr/bin/env bash
# =============================================================================
# TFM-Server — repair the migration history (baselining)
#
#   ./scripts/repair-migration-history.sh                  # report only, local
#   ./scripts/repair-migration-history.sh --apply          # write the ledger
#   ./scripts/repair-migration-history.sh --db-url "..."   # another target
#
# WHY THIS EXISTS
#   supabase_migrations.schema_migrations no longer matches supabase/migrations/.
#   Files were deleted (commit 5eafd03 "clean migrations") and schema changes
#   were made by hand in the Studio SQL console. `supabase db push` therefore
#   refuses to run: it finds local files with versions older than the last
#   recorded version.
#
# WHAT IS AND IS NOT RISKY
#   The ledger is bookkeeping. Repairing it touches no schema and no data.
#   The judgement that matters is WHICH files are already in the database:
#     marked applied but never applied -> its content never lands (silent drift)
#     left open but already applied    -> the file runs again on the next push,
#                                         and 13 of them carry INSERT/UPDATE/
#                                         DELETE, one a DROP TABLE ... CASCADE.
#                                         That is where data actually dies.
#
#   So this script does not guess. It asks the CLI to build a shadow database
#   from the migration files and diff it against the target:
#
#     no structural difference -> the target really is at the state the files
#                                 describe, marking them all applied is correct,
#                                 and --apply does exactly that
#     structural difference    -> saved for review, ledger untouched, exit 1
#
#   It never applies SQL to the target. Running migrations stays a separate,
#   explicit step (scripts/deploy.sh, or supabase db push).
#
# GRANT/REVOKE noise is reported but does not block. Privileges drift on every
# database that was ever restored from a dump, and they cannot cause a
# migration to be re-run against live data — which is the only failure mode
# here that destroys anything.
#
# See TFM-Documentation -> Server -> Deploy on Linux, "Repairing the migration
# history".
# =============================================================================
set -uo pipefail

cd "$(dirname "$0")/.."

MIGRATION_DIR="supabase/migrations"
OUT_DIR="tmp/migration-repair"

# The CLI stack started by `supabase start`. The password is the CLI default,
# not a secret — the port is bound to loopback only.
DEFAULT_URL="postgres://postgres:postgres@127.0.0.1:54322/postgres?sslmode=disable"

# auth is deliberately absent: GoTrue owns it and migrates it itself, so it
# would show up as drift on every run.
SCHEMAS="public,lookup,inventory_archive,derived"

DB_URL="$DEFAULT_URL"
APPLY=0
ASSUME_YES=0
ALLOW_REMOTE=0
STRICT=0

while [ $# -gt 0 ]; do
    case "$1" in
        --apply)         APPLY=1 ;;
        --db-url)        DB_URL="${2:-}"; shift ;;
        --schema)        SCHEMAS="${2:-}"; shift ;;
        --strict)        STRICT=1 ;;
        --allow-remote)  ALLOW_REMOTE=1 ;;
        --yes|-y)        ASSUME_YES=1 ;;
        --help|-h)       sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
stage() { printf '\n%s── %s %s\n' "$BOLD" "$1" "$OFF"; }
ok()    { printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$1"; }
warn()  { printf '  %s!%s %s\n' "$YELLOW" "$OFF" "$1"; }
info()  { printf '    %s\n' "$1"; }
die()   { printf '  %s✗%s %s\n' "$RED" "$OFF" "$1"; exit 1; }

RUN_TMP="$(mktemp -d)"
trap 'rm -rf "$RUN_TMP"' EXIT

psql_q() { psql "$DB_URL" --no-psqlrc -t -A -v ON_ERROR_STOP=1 -c "$1"; }

# The CLI wraps its output in JSON when stdout is not a terminal. Unwrap it, but
# stay correct if a future version prints plain SQL again.
unwrap_diff() {
    local raw="$1" out="$2"
    if [ "$(head -c 1 "$raw")" = "{" ]; then
        if command -v jq >/dev/null 2>&1; then
            jq -r '.diff // ""' < "$raw" > "$out"
        else
            python3 -c 'import json,sys;sys.stdout.write(json.load(sys.stdin).get("diff",""))' < "$raw" > "$out"
        fi
    else
        cp "$raw" "$out"
    fi
}

# ── Preflight ────────────────────────────────────────────────────────────────
stage "Preflight"

command -v supabase >/dev/null 2>&1 || die "supabase CLI not installed"
command -v psql     >/dev/null 2>&1 || die "psql not installed"
command -v pg_dump  >/dev/null 2>&1 || die "pg_dump not installed"
command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 \
    || die "neither jq nor python3 available — cannot unwrap the CLI's JSON output"
ok "supabase CLI $(supabase --version 2>/dev/null | head -1), $(psql --version)"

# The shadow database runs in a throwaway container.
docker info >/dev/null 2>&1 || die "Docker is not running — the shadow database needs it"
ok "Docker available"

# Guard against pointing a ledger rewrite at production by accident.
DB_HOST="$(printf '%s' "$DB_URL" | sed -E 's#^[^@]*@##; s#[:/?].*$##')"
case "$DB_HOST" in
    127.0.0.1|localhost|::1|"") ok "target is local ($DB_HOST)" ;;
    *)
        [ "$ALLOW_REMOTE" -eq 1 ] \
            || die "target host is '$DB_HOST', not loopback. Pass --allow-remote if you mean it, and take a pg_dump first."
        warn "target host is '$DB_HOST' — NOT local. Backup taken? Ctrl-C now if not."
        ;;
esac

psql_q 'select 1' >/dev/null 2>"$RUN_TMP/conn.err" \
    || { sed 's/^/      /' "$RUN_TMP/conn.err"; die "cannot connect to the target database"; }
ok "database reachable ($(psql_q 'select current_database()'))"

ls "$MIGRATION_DIR"/*.sql >/dev/null 2>&1 || die "no migration files in $MIGRATION_DIR"

mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"

# ── Ledger inventory ─────────────────────────────────────────────────────────
stage "Ledger inventory"

LEDGER_EXISTS="$(psql_q "select count(*) from information_schema.tables
                         where table_schema='supabase_migrations'
                           and table_name='schema_migrations';")"

if [ "$LEDGER_EXISTS" = "0" ]; then
    warn "supabase_migrations.schema_migrations does not exist — the CLI has never touched this database"
    : > "$RUN_TMP/ledger.txt"
else
    psql_q "select version from supabase_migrations.schema_migrations order by 1;" > "$RUN_TMP/ledger.txt"
fi

for f in "$MIGRATION_DIR"/*.sql; do basename "$f" | cut -d_ -f1; done | sort > "$RUN_TMP/files.txt"

comm -23 "$RUN_TMP/ledger.txt" "$RUN_TMP/files.txt" > "$RUN_TMP/phantom.txt"   # in ledger, no file
comm -13 "$RUN_TMP/ledger.txt" "$RUN_TMP/files.txt" > "$RUN_TMP/missing.txt"   # file, not in ledger

N_FILES=$(grep -c . "$RUN_TMP/files.txt")
N_LEDGER=$(grep -c . "$RUN_TMP/ledger.txt")
N_PHANTOM=$(grep -c . "$RUN_TMP/phantom.txt")
N_MISSING=$(grep -c . "$RUN_TMP/missing.txt")

info "migration files      : $N_FILES"
info "ledger entries       : $N_LEDGER"
info "ledger without file  : $N_PHANTOM"
info "file without ledger  : $N_MISSING"

if [ "$N_PHANTOM" -gt 0 ]; then
    warn "$N_PHANTOM ledger entries point at files that no longer exist:"
    while read -r v; do [ -n "$v" ] && info "  $v"; done < "$RUN_TMP/phantom.txt"
    info "they are removed from the ledger (--status reverted); no schema object is dropped"
fi

if [ "$N_PHANTOM" -eq 0 ] && [ "$N_MISSING" -eq 0 ]; then
    ok "ledger already matches the migration files — nothing to repair"
    exit 0
fi

# ── Drift capture ────────────────────────────────────────────────────────────
stage "Drift capture"

DIFF_FILE="$OUT_DIR/drift-$STAMP.sql"
info "supabase db diff --from migrations --to <target> --schema $SCHEMAS"
info "applying $N_FILES files to a shadow database — this takes a while"

# --from/--to is deliberate. The bare --db-url form selects a different diff
# engine and a different pairing; it reported "drop schema lookup" against a
# database that demonstrably has 65 lookup tables. Do not "simplify" this back.
if ! supabase db diff --from migrations --to "$DB_URL" --schema "$SCHEMAS" \
        > "$RUN_TMP/diff.raw" 2>"$RUN_TMP/diff.err"; then
    sed 's/^/      /' "$RUN_TMP/diff.err"
    die "supabase db diff failed — the files do not apply to a fresh database, or shadow port 54320 is taken"
fi
unwrap_diff "$RUN_TMP/diff.raw" "$DIFF_FILE"

# Statements are classified by what they can break. GRANT/REVOKE/ALTER DEFAULT
# PRIVILEGES cannot cause a migration to re-run against live data; anything else
# means the target is not at the state the files describe.
grep -vE '^[[:space:]]*(--.*)?$' "$DIFF_FILE" > "$RUN_TMP/body.txt" || true
grep -iE '^[[:space:]]*(GRANT|REVOKE|ALTER DEFAULT PRIVILEGES)\b' "$RUN_TMP/body.txt" > "$RUN_TMP/priv.txt" || true
grep -ivE '^[[:space:]]*(GRANT|REVOKE|ALTER DEFAULT PRIVILEGES)\b' "$RUN_TMP/body.txt" > "$RUN_TMP/struct.txt" || true

N_PRIV=$(grep -c . "$RUN_TMP/priv.txt")
N_STRUCT=$(grep -c . "$RUN_TMP/struct.txt")

[ "$N_PRIV" -gt 0 ] && warn "$N_PRIV privilege statements differ (GRANT/REVOKE/DEFAULT PRIVILEGES) — not blocking"
[ "$STRICT" -eq 1 ] && [ "$N_PRIV" -gt 0 ] && N_STRUCT=$((N_STRUCT + N_PRIV))

if [ "$N_STRUCT" -gt 0 ]; then
    warn "$N_STRUCT structural statements differ between the files and the target"
    printf '\n'
    head -30 "$RUN_TMP/struct.txt" | sed 's/^/      /'
    [ "$N_STRUCT" -gt 30 ] && info "  … full diff: $DIFF_FILE"
    printf '\n'
    warn "ledger NOT touched. Resolve the drift first:"
    info "1. Read $DIFF_FILE. It is written as 'from the files, to the target',"
    info "   so it describes what the target has that the files do not."
    info "2. DROP x followed by CREATE x = same object, different definition."
    info "   Read both and decide which side is right."
    info "3. A lone CREATE = an object no file defines, i.e. a Studio SQL"
    info "   console change. Move it into a new migration file."
    info "4. A lone DROP = the files define it and the target lacks it, i.e."
    info "   that migration was never applied here. Apply it, do not baseline"
    info "   it away."
    info "5. Re-run until only privilege statements remain."
    exit 1
fi

ok "no structural drift — the target is at the state the migration files describe"
ok "marking every file applied is therefore correct"
rm -f "$DIFF_FILE"

# ── Repair plan ──────────────────────────────────────────────────────────────
stage "Repair plan"

REPAIR_CMDS="$RUN_TMP/cmds.sh"
: > "$REPAIR_CMDS"
if [ "$N_PHANTOM" -gt 0 ]; then
    printf 'supabase migration repair --db-url "$DB_URL" --status reverted %s\n' \
        "$(tr '\n' ' ' < "$RUN_TMP/phantom.txt" | sed 's/  *$//')" >> "$REPAIR_CMDS"
fi
printf 'supabase migration repair --db-url "$DB_URL" --status applied %s\n' \
    "$(tr '\n' ' ' < "$RUN_TMP/files.txt" | sed 's/  *$//')" >> "$REPAIR_CMDS"

fold -s -w 100 "$REPAIR_CMDS" | sed 's/^/      /'

if [ "$APPLY" -eq 0 ]; then
    printf '\n'
    ok "report only — nothing was written. Re-run with --apply to execute this plan."
    exit 0
fi

# ── Ledger backup ────────────────────────────────────────────────────────────
stage "Ledger backup"

BACKUP="$OUT_DIR/ledger-$STAMP.sql"
if [ "$LEDGER_EXISTS" = "0" ]; then
    warn "no ledger table yet — nothing to back up"
    BACKUP="(none)"
else
    pg_dump "$DB_URL" --data-only --inserts \
            --table=supabase_migrations.schema_migrations > "$BACKUP" 2>"$RUN_TMP/dump.err" \
        || { sed 's/^/      /' "$RUN_TMP/dump.err"; die "could not back up the ledger"; }
    ok "$BACKUP ($(wc -c < "$BACKUP" | tr -d ' ') bytes)"
    info "restore: psql \"\$DB_URL\" -c 'truncate supabase_migrations.schema_migrations' -f $BACKUP"
fi

# ── Apply ────────────────────────────────────────────────────────────────────
stage "Apply"

if [ "$ASSUME_YES" -eq 0 ]; then
    printf '  Rewrite the migration ledger of %s? [y/N] ' "$DB_HOST"
    read -r answer
    case "$answer" in [yY]*) ;; *) die "aborted" ;; esac
fi

export DB_URL
while read -r cmd; do
    [ -z "$cmd" ] && continue
    if ! eval "$cmd" >"$RUN_TMP/repair.out" 2>&1; then
        sed 's/^/      /' "$RUN_TMP/repair.out"
        die "migration repair failed — ledger backup at $BACKUP"
    fi
done < "$REPAIR_CMDS"
ok "ledger rewritten"

# ── Verify ───────────────────────────────────────────────────────────────────
stage "Verify"

psql_q "select version from supabase_migrations.schema_migrations order by 1;" > "$RUN_TMP/ledger2.txt"
if diff -q "$RUN_TMP/ledger2.txt" "$RUN_TMP/files.txt" >/dev/null; then
    ok "ledger now lists exactly the $N_FILES migration files"
else
    diff "$RUN_TMP/files.txt" "$RUN_TMP/ledger2.txt" | sed 's/^/      /'
    die "ledger still differs from the files — backup at $BACKUP"
fi

if supabase db push --db-url "$DB_URL" --dry-run >"$RUN_TMP/push.out" 2>&1; then
    sed 's/^/      /' "$RUN_TMP/push.out"
    ok "supabase db push --dry-run is clean — the standard workflow is back"
else
    sed 's/^/      /' "$RUN_TMP/push.out"
    warn "db push --dry-run still complains — read the output above"
fi
