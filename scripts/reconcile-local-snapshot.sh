#!/usr/bin/env bash
# =============================================================================
# TFM-Server — reconcile a database whose migration ledger drifted from the files
#
#   ./scripts/reconcile-local-snapshot.sh                  # report only
#   ./scripts/reconcile-local-snapshot.sh --apply          # local: fix and record
#   ./scripts/reconcile-local-snapshot.sh --baseline-only  # production: record only
#
# WHY THIS EXISTS
#   Production ships no migration history, so a restored snapshot arrives with a
#   ledger that stops years before its schema does. `supabase migration up` then
#   replays everything unrecorded — against a database that already contains
#   most of it — and dies on the first file that is not idempotent.
#
#   The snapshot is also not a contiguous prefix of the migration list. Parts of
#   the newest migrations can be present while a band in the middle never ran,
#   so there is no cut-off to baseline at. Every file has to be asked
#   individually, which is what scripts/classify-migrations.py does.
#
# THE TWO MODES, AND WHY PRODUCTION GETS ITS OWN
#   --apply          classify, run the files that never ran, then record all of
#                    them. For a local database restored from a dump. Refused on
#                    a target that is not loopback.
#   --baseline-only  classify and record, changing no schema at all. Refuses to
#                    record anything while a file is still missing objects.
#
#   Production is not a database to auto-remediate. Its schema is the source of
#   truth the snapshots come from, so what it needs is a ledger that admits what
#   is already deployed — that is --baseline-only. If the report shows files that
#   genuinely never ran there, deploying them is a release, and it belongs in
#   scripts/deploy.sh with the review that implies. Not here.
#
# WHAT IT WILL NOT DO
#   Apply a file that is missing objects AND carries DROP TABLE / TRUNCATE /
#   DELETE. Those are reported as REVIEW and left alone: 20260206000000 opens
#   with DROP TABLE public.records_messages CASCADE, and replaying it on a
#   database that already has the table destroys the messages in it.
#
# See README.md -> "When the local database came from a production backup".
# =============================================================================
set -uo pipefail

cd "$(dirname "$0")/.."

# psql/pg_dump come from the keg-only libpq formula; supabase is not on a
# non-interactive PATH on macOS.
PATH="/opt/homebrew/bin:/opt/homebrew/opt/libpq/bin:/usr/local/opt/libpq/bin:$PATH"
export PATH

MIGRATION_DIR="supabase/migrations"
CLASSIFY="scripts/classify-migrations.py"

# The CLI stack started by `supabase start`. The password is the CLI default,
# not a secret — the port is bound to loopback only.
DEFAULT_URL="postgres://postgres:postgres@127.0.0.1:54322/postgres?sslmode=disable"

DB_URL="$DEFAULT_URL"
CONTAINER=""
APPLY=0
BASELINE_ONLY=0
ASSUME_YES=0
ALLOW_REMOTE=0
MAX_PASSES=5

while [ $# -gt 0 ]; do
    case "$1" in
        --apply)         APPLY=1 ;;
        --baseline-only) BASELINE_ONLY=1 ;;
        --db-url)
            DB_URL="${2:-}"
            # An unset shell variable would arrive here as "", and an empty URL
            # makes psql fall back to the LOCAL default — i.e. --db-url "$DB_URL"
            # with DB_URL unset silently retargets this at the local database.
            [ -n "$DB_URL" ] || { echo "--db-url was given but is empty (is \$DB_URL set?)" >&2; exit 2; }
            shift ;;
        --container)     CONTAINER="${2:-}"; shift ;;
        --allow-remote)  ALLOW_REMOTE=1 ;;
        --yes|-y)        ASSUME_YES=1 ;;
        --help|-h)
            sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//'
            printf '  --apply          run missing migrations, then record all of them\n'
            printf '  --baseline-only  record only; never changes the schema\n'
            printf '  --db-url URL     target (default: the local CLI stack)\n'
            printf '  --container NAME reach psql through this container instead\n'
            printf '  --allow-remote   permit a target that is not loopback\n'
            printf '  --yes, -y        skip the confirmation prompt\n'
            exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

[ "$APPLY" -eq 1 ] && [ "$BASELINE_ONLY" -eq 1 ] \
    && { echo "--apply and --baseline-only are mutually exclusive" >&2; exit 2; }

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
stage() { printf '\n%s── %s %s\n' "$BOLD" "$1" "$OFF"; }
ok()    { printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$1"; }
warn()  { printf '  %s!%s %s\n' "$YELLOW" "$OFF" "$1"; }
info()  { printf '    %s\n' "$1"; }
die()   { printf '  %s✗%s %s\n' "$RED" "$OFF" "$1"; exit 1; }

RUN_TMP="$(mktemp -d)"
trap 'rm -rf "$RUN_TMP"' EXIT

# ── Preflight ────────────────────────────────────────────────────────────────
stage "Preflight"

command -v supabase >/dev/null 2>&1 || die "supabase CLI not installed"
command -v python3  >/dev/null 2>&1 || die "python3 not installed"
[ -f "$CLASSIFY" ] || die "missing $CLASSIFY"
ls "$MIGRATION_DIR"/*.sql >/dev/null 2>&1 || die "no migration files in $MIGRATION_DIR"

DB_HOST="$(printf '%s' "$DB_URL" | sed -E 's#^[^@]*@##; s#[:/?].*$##')"
DB_NAME="$(printf '%s' "$DB_URL" | sed -E 's#\?.*$##; s#^.*/##')"
[ -z "$DB_NAME" ] && DB_NAME="postgres"

case "$DB_HOST" in
    127.0.0.1|localhost|::1|"") IS_LOCAL=1 ;;
    *)                          IS_LOCAL=0 ;;
esac

# How to reach psql. The production server has no host psql client — the same
# reason scripts/repair-migration-history.sh cannot run there — so fall back to
# the database container, which is how scripts/deploy.sh has always done it.
# The CLI names that container supabase_db_<project>; docker-compose.yaml names
# it supabase-db.
FORCE_CONTAINER=0
if [ -n "$CONTAINER" ]; then
    FORCE_CONTAINER=1          # an explicit --container wins over a host client
else
    CONTAINER="$(docker ps --format '{{.Names}}' 2>/dev/null \
        | grep -E '^supabase[-_]db' | head -1)"
fi

if [ "$FORCE_CONTAINER" -eq 0 ] && command -v psql >/dev/null 2>&1; then
    PSQL=(psql "$DB_URL")
    CLASSIFY_CONN=(--db-url "$DB_URL")
    ok "psql $(psql --version | awk '{print $3}') on the host → $DB_HOST/$DB_NAME"
elif [ -n "$CONTAINER" ]; then
    [ "$IS_LOCAL" -eq 1 ] \
        || die "no host psql, and a local container cannot reach '$DB_HOST'"
    PSQL=(docker exec -i "$CONTAINER" psql -U postgres -d "$DB_NAME")
    CLASSIFY_CONN=(--psql "docker exec -i $CONTAINER psql -U postgres -d $DB_NAME")
    ok "no host psql — going through container '$CONTAINER' (db $DB_NAME)"
else
    die "no psql on PATH and no supabase db container found (try --container NAME)"
fi

psql_q() { "${PSQL[@]}" --no-psqlrc -t -A -v ON_ERROR_STOP=1 -c "$1"; }

if [ "$IS_LOCAL" -eq 1 ]; then
    ok "target is local ($DB_HOST)"
else
    [ "$ALLOW_REMOTE" -eq 1 ] \
        || die "target host is '$DB_HOST', not loopback. Pass --allow-remote if you mean it."
    warn "target host is '$DB_HOST' — NOT local"
    # Running migrations against a database that is not this developer's own
    # copy is a release, not a repair. Reading it and fixing its ledger is fine.
    [ "$APPLY" -eq 1 ] && die "--apply is refused on a remote target. Use --baseline-only for its ledger, and scripts/deploy.sh to deploy migrations."
    info "back up supabase_migrations.schema_migrations before continuing"
fi

psql_q 'select 1' >/dev/null 2>"$RUN_TMP/conn.err" \
    || { sed 's/^/      /' "$RUN_TMP/conn.err"; die "cannot connect to the target database"; }
ok "database reachable ($(psql_q 'select current_database()'))"

# ── Ownership ────────────────────────────────────────────────────────────────
# In a production dump most of `public` is owned by supabase_admin while the CLI
# connects as postgres, so every CREATE OR REPLACE fails with 42501. The grant
# lives in the cluster-wide pg_auth_members, so it survives restarts and even
# dropping the database — only a wiped Postgres volume loses it.
stage "Ownership"

if [ "$(psql_q "select pg_has_role('postgres','supabase_admin','member');")" = "t" ]; then
    ok "postgres is a member of supabase_admin"
elif [ "$BASELINE_ONLY" -eq 1 ]; then
    ok "postgres is not a member of supabase_admin — irrelevant here, no schema is written"
else
    GRANT_SQL="GRANT supabase_admin TO postgres;"
    if [ "$APPLY" -eq 0 ]; then
        warn "postgres cannot write supabase_admin-owned objects — migrations would fail with 42501"
        info "--apply will run, as a superuser: $GRANT_SQL"
    elif [ -n "$CONTAINER" ] && docker exec "$CONTAINER" \
            psql "postgres://supabase_admin:postgres@127.0.0.1:5432/postgres" \
            -q -c "$GRANT_SQL" >"$RUN_TMP/grant.err" 2>&1; then
        ok "granted supabase_admin to postgres"
    else
        sed 's/^/      /' "$RUN_TMP/grant.err" 2>/dev/null
        die "could not grant it. Run this as a superuser, then re-run: $GRANT_SQL"
    fi
fi

# ── Classify ─────────────────────────────────────────────────────────────────
classify() {
    python3 "$CLASSIFY" "${CLASSIFY_CONN[@]}" --migrations-dir "$MIGRATION_DIR" \
        > "$RUN_TMP/plan.tsv" 2>"$RUN_TMP/plan.err" \
        || { sed 's/^/      /' "$RUN_TMP/plan.err"; die "classification failed"; }
}

stage "Classify"
classify

n_total=$(ls "$MIGRATION_DIR"/*.sql | wc -l | tr -d ' ')
n_unrec=$(grep -c . "$RUN_TMP/plan.tsv" || true)
n_base=$(awk -F'\t' '$2=="BASELINE"' "$RUN_TMP/plan.tsv" | grep -c . || true)
n_apply=$(awk -F'\t' '$2=="APPLY"'   "$RUN_TMP/plan.tsv" | grep -c . || true)
n_rev=$(awk -F'\t' '$2=="REVIEW"'    "$RUN_TMP/plan.tsv" | grep -c . || true)
n_unk=$(awk -F'\t' '$2=="UNKNOWN"'   "$RUN_TMP/plan.tsv" | grep -c . || true)

info "migration files   : $n_total"
info "unrecorded        : $n_unrec"
info "already in the db : $n_base   (baseline, do not run)"
info "missing           : $n_apply   (run)"
info "cannot tell       : $n_unk   (grants/DML only — decide by hand)"
info "needs a human     : $n_rev   (review)"

if [ "$n_apply" -gt 0 ]; then
    printf '\n'
    warn "these files never ran here:"
    awk -F'\t' '$2=="APPLY" {printf "      %s  %s\n", $1, $3}' "$RUN_TMP/plan.tsv"
fi
if [ "$n_unk" -gt 0 ]; then
    printf '\n'
    warn "these have nothing probeable — absence of evidence, not evidence of absence:"
    awk -F'\t' '$2=="UNKNOWN" {printf "      %s  %s\n", $1, $3}' "$RUN_TMP/plan.tsv"
fi
if [ "$n_rev" -gt 0 ]; then
    printf '\n'
    warn "these are missing objects AND can destroy data — never applied automatically:"
    awk -F'\t' '$2=="REVIEW" {printf "      %s  %s\n", $1, $3}' "$RUN_TMP/plan.tsv"
    info "read the file, decide what it should do here, apply the parts you want by"
    info "hand, then: supabase migration repair --db-url \"\$DB_URL\" --status applied <version>"
fi

if [ "$n_unrec" -eq 0 ]; then
    ok "ledger already records every migration file — nothing to do"
    exit 0
fi

if [ "$APPLY" -eq 0 ] && [ "$BASELINE_ONLY" -eq 0 ]; then
    printf '\n'
    ok "report only — nothing was written."
    info "local snapshot : re-run with --apply"
    info "production     : re-run with --baseline-only (records, never writes schema)"
    exit 0
fi

# Recording a file as applied when it never ran means its content never lands,
# and nothing will ever tell you. So those files are left OUT of the ledger
# instead — which is also what makes them the exact set `supabase db push`
# applies next.
if [ "$BASELINE_ONLY" -eq 1 ] && [ $((n_apply + n_rev + n_unk)) -gt 0 ]; then
    printf '\n'
    warn "$((n_apply + n_rev + n_unk)) file(s) will be left unrecorded on purpose:"
    info "$((n_apply + n_rev)) verifiably missing here, $n_unk unprovable either way."
    info "after this, those are exactly what 'supabase db push --include-all' applies."
    info "read them first — nothing else will."
fi
[ "$APPLY" -eq 1 ] && [ "$n_rev" -gt 0 ] \
    && die "refusing to continue while $n_rev file(s) need review"

if [ "$ASSUME_YES" -eq 0 ]; then
    if [ "$BASELINE_ONLY" -eq 1 ]; then
        printf '\n  Record %s migration(s) as applied on %s? No schema changes. [y/N] ' \
            "$((n_total - n_apply - n_rev - n_unk))" "$DB_HOST"
    else
        printf '\n  Apply %s migration(s) to %s and record all %s in the ledger? [y/N] ' \
            "$n_apply" "$DB_HOST" "$n_total"
    fi
    read -r answer
    case "$answer" in [yY]*) ;; *) die "aborted" ;; esac
fi

# ── Apply ────────────────────────────────────────────────────────────────────
run_sql_file() {
    "${PSQL[@]}" --no-psqlrc -q -v ON_ERROR_STOP=1 --single-transaction -f - \
        >/dev/null 2>"$1" < "$2"
}

# The views a migration rebuilds have to be dropped first, because CREATE OR
# REPLACE VIEW can neither rename nor drop a column. Only safe while every
# dependent view is rebuilt by the same migration, so that is checked.
blocking_views() {
    local file="$1" own v deps dep
    own="$(python3 "$CLASSIFY" --declares "$file" | awk -F'\t' '$1=="view"{print $2}')"
    for v in $own; do
        [ "$(psql_q "select count(*) from pg_views where schemaname||'.'||viewname = '$v';")" = "0" ] \
            && continue
        deps="$(psql_q "select string_agg(distinct d.relname, ' ') from pg_depend dep
                          join pg_rewrite r on r.oid = dep.objid
                          join pg_class d on d.oid = r.ev_class
                         where dep.refobjid = '$v'::regclass
                           and d.relname <> split_part('$v','.',2);")"
        for dep in $deps; do
            printf '%s\n' "$own" | sed 's/.*\.//' | grep -qx "$dep" \
                || { warn "$v is used by '$dep', which this migration does not rebuild"; return 1; }
        done
        printf '%s\n' "$v"
    done
}

apply_file() {
    local file="$1" err="$RUN_TMP/apply.err" views

    run_sql_file "$err" "$file" && return 0

    # A foreign key that cannot validate against the rows already in the table.
    if grep -qi 'violates foreign key constraint' "$err"; then
        python3 "$CLASSIFY" --fk-not-valid "$file" > "$RUN_TMP/patched.sql"
        if run_sql_file "$err" "$RUN_TMP/patched.sql"; then
            warn "foreign keys added NOT VALID — rows exist whose parents this database lacks"
            info "validate later: ALTER TABLE <t> VALIDATE CONSTRAINT <c>;"
            return 0
        fi
    fi

    # A view held in a shape CREATE OR REPLACE cannot reach. Drop and rebuild in
    # ONE transaction: if the migration then fails, the drops roll back with it
    # instead of leaving the views missing.
    if grep -qiE 'cannot change name of view column|cannot drop columns from view|cannot change data type of view column' "$err"; then
        views="$(blocking_views "$file" | paste -sd, -)"
        if [ -n "$views" ]; then
            info "dropping and rebuilding in one transaction: $views"
            { printf 'DROP VIEW %s;\n' "$views"; cat "$file"; } > "$RUN_TMP/withdrop.sql"
            run_sql_file "$err" "$RUN_TMP/withdrop.sql" && return 0
        fi
    fi

    sed 's/^/        /' "$err"
    return 1
}

: > "$RUN_TMP/done.txt"
if [ "$APPLY" -eq 1 ]; then
    stage "Apply"
    pass=0
    while [ "$pass" -lt "$MAX_PASSES" ]; do
        pass=$((pass + 1))
        [ "$pass" -gt 1 ] && classify

        # Only files not already applied in this run. Re-running one would undo
        # a later migration that supersedes it.
        awk -F'\t' '$2=="APPLY"{print $1}' "$RUN_TMP/plan.tsv" | sort > "$RUN_TMP/want.txt"
        comm -23 "$RUN_TMP/want.txt" <(sort "$RUN_TMP/done.txt") > "$RUN_TMP/todo.txt"

        n_todo=$(grep -c . "$RUN_TMP/todo.txt" || true)
        [ "$n_todo" -eq 0 ] && break

        # Pass 2+ finds files the ledger already recorded whose objects an older
        # migration has just overwritten: 20260610000000 redefines
        # add_plot_ids_to_records, which 20260618000000 had already fixed.
        [ "$pass" -gt 1 ] && info "pass $pass: $n_todo file(s) superseded by what pass $((pass-1)) applied"

        while read -r version; do
            [ -z "$version" ] && continue
            f="$(ls "$MIGRATION_DIR"/${version}_*.sql 2>/dev/null | head -1)"
            [ -z "$f" ] && die "no file for version $version"
            if apply_file "$f"; then
                ok "applied $(basename "$f")"
                echo "$version" >> "$RUN_TMP/done.txt"
            else
                die "failed: $(basename "$f") — nothing was recorded in the ledger"
            fi
        done < "$RUN_TMP/todo.txt"
    done
    [ "$pass" -ge "$MAX_PASSES" ] && warn "stopped after $MAX_PASSES passes — re-run to check it settled"
    ok "$(grep -c . "$RUN_TMP/done.txt" || true) migration(s) applied"
fi

# ── Ledger ───────────────────────────────────────────────────────────────────
# Everything the files describe is now in the database, so every file is
# correctly recorded as applied.
stage "Ledger"

for f in "$MIGRATION_DIR"/*.sql; do basename "$f" | cut -d_ -f1; done | sort > "$RUN_TMP/all.txt"

if [ "$BASELINE_ONLY" -eq 1 ]; then
    # Record only what is verifiably in the database. A file that never ran
    # stays unrecorded deliberately: that is what keeps it visible to
    # `supabase migration list` and applicable by `supabase db push`.
    awk -F'\t' '$2=="APPLY" || $2=="REVIEW" || $2=="UNKNOWN" {print $1}' "$RUN_TMP/plan.tsv" \
        | sort > "$RUN_TMP/skip.txt"
    comm -23 "$RUN_TMP/all.txt" "$RUN_TMP/skip.txt" > "$RUN_TMP/repair.txt"
else
    cp "$RUN_TMP/all.txt" "$RUN_TMP/repair.txt"
fi

n_repair=$(grep -c . "$RUN_TMP/repair.txt" || true)
# shellcheck disable=SC2046
if supabase migration repair --db-url "$DB_URL" --status applied \
       $(tr '\n' ' ' < "$RUN_TMP/repair.txt") >"$RUN_TMP/repair.out" 2>&1; then
    ok "ledger records $n_repair of $n_total migration files"
else
    sed 's/^/      /' "$RUN_TMP/repair.out"
    die "migration repair failed"
fi

# ── Verify ───────────────────────────────────────────────────────────────────
stage "Verify"

classify
left=$(awk -F'\t' '$2!="BASELINE"' "$RUN_TMP/plan.tsv" | grep -c . || true)
[ "$left" -gt 0 ] && warn "$left file(s) still classify as needing work — read the plan above"

# `migration up --dry-run` does not exist in every CLI version, so compare the
# ledger with the files directly.
psql_q "select version from supabase_migrations.schema_migrations order by 1;" \
    | sort > "$RUN_TMP/ledger.txt"
sort "$RUN_TMP/all.txt" > "$RUN_TMP/all.sorted"
pending=$(comm -13 "$RUN_TMP/ledger.txt" "$RUN_TMP/all.sorted" | grep -c . || true)
if [ "$pending" -eq 0 ]; then
    ok "every migration file is recorded — 'supabase migration up' is a no-op now"
elif [ "$BASELINE_ONLY" -eq 1 ]; then
    warn "$pending file(s) deliberately left unrecorded — missing, or unprovable:"
    comm -13 "$RUN_TMP/ledger.txt" "$RUN_TMP/all.sorted" | sed 's/^/      /'
    info "APPLY rows are missing here; UNKNOWN rows only mean nothing was probeable."
    info "Read each, then deploy: supabase db push --db-url \"\$DB_URL\" --include-all"
    [ "$n_rev" -gt 0 ] && warn "$n_rev of them carry DROP TABLE/TRUNCATE/DELETE — db push WILL run those"
else
    comm -13 "$RUN_TMP/ledger.txt" "$RUN_TMP/all.sorted" | sed 's/^/      /'
    warn "$pending file(s) still unrecorded"
fi
