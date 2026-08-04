#!/usr/bin/env bash
# =============================================================================
# TFM-Server — production deploy: structure, data, services
#
#   ./scripts/deploy.sh                      # migrations + start stack
#   ./scripts/deploy.sh --seed               # + public seeds (fresh install)
#   ./scripts/deploy.sh --seed --seed-intern # + internal seeds (DMZ access)
#   ./scripts/deploy.sh --migrate-only       # structure only, start nothing else
#
# Order is not arbitrary:
#   db -> auth (GoTrue migrates the auth schema; application migrations depend
#   on auth.users columns) -> migrations -> seeds -> remaining services.
#
# Seeds are loaded with PowerSync stopped: every lookup and inventory_archive
# table is in the "powersync" publication, so seeding while it replicates pushes
# millions of rows through logical decoding instead of one initial snapshot.
#
# See TFM-Documentation -> Server -> Deploy on Linux.
# =============================================================================
set -uo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

RUN_TMP="$(mktemp -d)"
trap 'rm -rf "$RUN_TMP"' EXIT

DO_MIGRATE=1
DO_SEED=0
DO_SEED_INTERN=0
DO_START=1
MIGRATE_ONLY=0
FORCE_SEED=0
ASSUME_YES=0

for arg in "$@"; do
    case "$arg" in
        --seed)         DO_SEED=1 ;;
        --seed-intern)  DO_SEED=1; DO_SEED_INTERN=1 ;;
        --migrate-only) MIGRATE_ONLY=1; DO_START=0 ;;
        --no-migrate)   DO_MIGRATE=0 ;;
        --force-seed)   FORCE_SEED=1 ;;
        --yes|-y)       ASSUME_YES=1 ;;
        --help|-h)      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
stage() { printf '\n%s── %s %s\n' "$BOLD" "$1" "$OFF"; }
ok()    { printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$1"; }
warn()  { printf '  %s!%s %s\n' "$YELLOW" "$OFF" "$1"; }
die()   { printf '  %s✗%s %s\n' "$RED" "$OFF" "$1"; exit 1; }

retry() {
    local timeout=$1; shift
    local waited=0
    until "$@" >/dev/null 2>&1; do
        [ "$waited" -ge "$timeout" ] && return 1
        sleep 3; waited=$((waited+3))
    done
}

# psql through the db container: no host client required, no port/password juggling.
psql_q()  { docker compose exec -T db psql -U postgres -d "$POSTGRES_DB" --no-psqlrc -t -A --set ON_ERROR_STOP=on -c "$1" 2>/dev/null; }
psql_f()  { docker compose exec -T db psql -U postgres -d "$POSTGRES_DB" --no-psqlrc -q --set ON_ERROR_STOP=on -f - < "$1"; }

# ── Preflight ────────────────────────────────────────────────────────────────
stage "Preflight"

[ -f .env ] || die ".env missing"
set -a; . ./.env; set +a
ok ".env loaded"

if ! docker compose config -q 2>"$RUN_TMP/config.err"; then
    sed 's/^/      /' "$RUN_TMP/config.err"
    die "docker-compose.yaml does not resolve — a variable is missing from .env"
fi
ok "compose file resolves"

if [ "$DO_SEED" -eq 1 ]; then
    ls supabase/seeds/public/*.sql >/dev/null 2>&1 \
        || die "no public seeds found (git submodule update --init supabase/seeds/public)"
    if [ "$DO_SEED_INTERN" -eq 1 ]; then
        ls supabase/seeds/intern/*.sql >/dev/null 2>&1 \
            || die "no internal seeds found (clone tfm-seeds/intern into supabase/seeds/intern)"
    fi
    ok "seed files present"
fi

# ── Database and auth ────────────────────────────────────────────────────────
stage "Database and auth"

docker compose up -d db >/dev/null 2>"$RUN_TMP/up.err" \
    || { sed 's/^/      /' "$RUN_TMP/up.err"; die "could not start db"; }
retry 180 docker compose exec -T db pg_isready -U postgres -q \
    || die "postgres not ready within 180s"
ok "postgres ready"

# GoTrue owns the auth schema. Application migrations reference auth.users columns
# (e.g. the on_auth_user_created trigger), so auth must migrate first.
docker compose up -d auth >/dev/null 2>&1 || die "could not start auth"
if retry 180 bash -c "[ \"\$(docker compose exec -T db psql -U postgres -d $POSTGRES_DB --no-psqlrc -t -A -c \"select count(*) from information_schema.columns where table_schema='auth' and table_name='users' and column_name='email_confirmed_at';\" 2>/dev/null)\" = '1' ]"; then
    ok "auth schema migrated"
else
    docker compose logs --tail=30 auth
    die "GoTrue did not migrate the auth schema — migrations would fail"
fi

# ── Structure ────────────────────────────────────────────────────────────────
if [ "$DO_MIGRATE" -eq 1 ]; then
    stage "Structure (migrations)"

    if command -v supabase >/dev/null 2>&1; then
        # sslmode=disable: nothing in this stack terminates TLS at Postgres. Safe
        # only because this runs on the server itself, over loopback.
        DB_URL="postgres://postgres:${POSTGRES_PASSWORD}@127.0.0.1:${POSTGRES_PORT}/${POSTGRES_DB}?sslmode=disable"
        if supabase db push --db-url "$DB_URL" --yes 2>&1 | sed 's/^/      /'; then
            ok "migrations applied via supabase CLI (history tracked)"
        else
            die "supabase db push failed — check 'supabase migration list --db-url ...'"
        fi
    else
        warn "supabase CLI not installed — falling back to psql (NO history tracking)"
        warn "the loop is not re-runnable: it will fail on an already-migrated database"
        count=0
        for f in supabase/migrations/*.sql; do
            if psql_f "$f" >/dev/null 2>"$RUN_TMP/migrate.err"; then
                count=$((count+1))
            else
                sed 's/^/      /' "$RUN_TMP/migrate.err"
                die "migration failed: $f"
            fi
        done
        ok "$count migrations applied"
    fi
fi

[ "$MIGRATE_ONLY" -eq 1 ] && { stage "Done (--migrate-only)"; exit 0; }

# ── Data ─────────────────────────────────────────────────────────────────────
if [ "$DO_SEED" -eq 1 ]; then
    stage "Data (seeds)"

    # Only lookup.sql carries ON CONFLICT DO NOTHING. The inventory_archive files
    # are plain INSERTs, so loading them twice duplicates rows or violates PKs.
    existing="$(psql_q "select count(*) from inventory_archive.plot;")"
    if [ "${existing:-0}" -gt 0 ] && [ "$FORCE_SEED" -eq 0 ]; then
        warn "inventory_archive.plot already holds $existing rows"
        warn "skipping every seed except lookup.sql (idempotent); use --force-seed to override"
        SKIP_BULK=1
    else
        SKIP_BULK=0
    fi

    if [ "$SKIP_BULK" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
        printf '  About to load bulk seed data into %s. Type "seed" to continue: ' "$POSTGRES_DB"
        read -r answer
        [ "$answer" = "seed" ] || die "aborted"
    fi

    # PowerSync must not replicate during the load — see header.
    PS_WAS_RUNNING=0
    if [ -n "$(docker compose ps -q powersync 2>/dev/null)" ]; then
        PS_WAS_RUNNING=1
        docker compose stop powersync >/dev/null 2>&1
        warn "powersync stopped for the duration of the load"
    fi

    load_seed_dir() {
        local dir=$1
        for f in "$dir"/*.sql; do
            [ -e "$f" ] || continue
            if [ "$SKIP_BULK" -eq 1 ] && [ "$(basename "$f")" != "lookup.sql" ]; then
                continue
            fi
            printf '    → %s\n' "$f"
            if ! psql_f "$f" >/dev/null 2>"$RUN_TMP/seed.err"; then
                sed 's/^/      /' "$RUN_TMP/seed.err"
                die "seed failed: $f"
            fi
        done
    }

    load_seed_dir supabase/seeds/public
    ok "public seeds loaded"

    if [ "$DO_SEED_INTERN" -eq 1 ]; then
        load_seed_dir supabase/seeds/intern
        ok "internal seeds loaded"
    fi

    if [ "$PS_WAS_RUNNING" -eq 1 ]; then
        docker compose start powersync >/dev/null 2>&1
        ok "powersync restarted"
    fi
fi

# ── Services ─────────────────────────────────────────────────────────────────
if [ "$DO_START" -eq 1 ]; then
    stage "Services"
    docker compose up -d >/dev/null 2>"$RUN_TMP/up-all.err" \
        || { sed 's/^/      /' "$RUN_TMP/up-all.err"; die "docker compose up -d failed"; }
    ok "stack started"
fi

# ── Verify ───────────────────────────────────────────────────────────────────
stage "Verify"

for q in \
    "select 'schemas: ' || string_agg(schema_name, ', ') from information_schema.schemata where schema_name in ('lookup','inventory_archive','derived','public')" \
    "select 'inventory_archive.plot: ' || count(*) from inventory_archive.plot" \
    "select 'public.records: ' || count(*) from public.records" \
    ; do
    result="$(psql_q "$q")"
    [ -n "$result" ] && ok "$result"
done

slot="$(psql_q "select slot_name || ' active=' || active || ' ' || wal_status from pg_replication_slots limit 1;")"
[ -n "$slot" ] && ok "replication slot: $slot" || warn "no replication slot (powersync has not connected yet)"

printf '\n%sDeployment finished.%s\n' "$BOLD" "$OFF"
