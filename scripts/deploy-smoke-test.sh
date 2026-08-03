#!/usr/bin/env bash
# =============================================================================
# TFM-Server — deployment smoke test
#
# Runs the production deployment procedure end to end against a FRESH database
# and asserts every stage. Intended for a disposable VM.
#
#   ./scripts/deploy-smoke-test.sh --reset --seed-lookup
#   ./scripts/deploy-smoke-test.sh --reset --no-powersync
#   ./scripts/deploy-smoke-test.sh --reset --seed-lookup --teardown
#
# See TFM-Documentation → Server → Deploy on Linux, appendix "Testing the
# deployment".
#
# ⚠  DESTRUCTIVE with --reset: removes containers, named volumes and
#    ./volumes/db/data of THIS checkout. Never run it on the production host.
#    docker-compose.yaml uses fixed container_names and a bind-mounted data
#    directory, so a test stack cannot be isolated from a production stack on
#    the same machine.
# =============================================================================
set -uo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

# Private scratch dir. Fixed names under /tmp break when the script is run first as a
# user and then as root: fs.protected_regular blocks even root from O_CREAT-opening
# another user's file in a world-writable sticky directory.
RUN_TMP="$(mktemp -d)"
trap 'rm -rf "$RUN_TMP"' EXIT

RESET=0
SEED_LOOKUP=0
WITH_POWERSYNC=1
TEARDOWN=0
ASSUME_YES=0

for arg in "$@"; do
    case "$arg" in
        --reset)         RESET=1 ;;
        --seed-lookup)   SEED_LOOKUP=1 ;;
        --no-powersync)  WITH_POWERSYNC=0 ;;
        --teardown)      TEARDOWN=1 ;;
        --yes|-y)        ASSUME_YES=1 ;;
        --help|-h)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "Unknown option: $arg (try --help)" >&2
            exit 2 ;;
    esac
done

# ── Output helpers ───────────────────────────────────────────────────────────
PASSED=0
FAILED=0
RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; OFF=$'\033[0m'

stage() { printf '\n%s── %s %s\n' "$BOLD" "$1" "$OFF"; }
ok()    { PASSED=$((PASSED+1)); printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$1"; }
warn()  { printf '  %s!%s %s\n' "$YELLOW" "$OFF" "$1"; }
fail()  { FAILED=$((FAILED+1)); printf '  %s✗%s %s\n' "$RED" "$OFF" "$1"; }
die()   { fail "$1"; summary; exit 1; }

summary() {
    printf '\n%s────────────────────────────%s\n' "$BOLD" "$OFF"
    printf '  passed: %s%d%s   failed: %s%d%s\n' \
        "$GREEN" "$PASSED" "$OFF" "$([ "$FAILED" -gt 0 ] && echo "$RED" || echo "$GREEN")" "$FAILED" "$OFF"
}

# Retry a command until it succeeds. retry <seconds> <description> <cmd...>
retry() {
    local timeout=$1 desc=$2; shift 2
    local waited=0
    until "$@" >/dev/null 2>&1; do
        if [ "$waited" -ge "$timeout" ]; then
            return 1
        fi
        sleep 3
        waited=$((waited+3))
    done
    return 0
}

# psql inside the db container — no host client and no port guessing needed.
psql_q() {
    docker compose exec -T db psql -U postgres -d "${POSTGRES_DB}" \
        --no-psqlrc -t -A --set ON_ERROR_STOP=on -c "$1" 2>/dev/null
}

http_code() {
    curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@" 2>/dev/null
}

# ── Stage 1: preflight ───────────────────────────────────────────────────────
stage "1. Preflight"

command -v docker >/dev/null 2>&1 || die "docker not found"

COMPOSE_VERSION="$(docker compose version --short 2>/dev/null | tr -d 'v')"
if [ -z "$COMPOSE_VERSION" ]; then
    die "docker compose plugin not found"
fi
# include: requires >= 2.20.3
if [ "$(printf '%s\n2.20.3\n' "$COMPOSE_VERSION" | sort -V | head -1)" != "2.20.3" ]; then
    die "compose $COMPOSE_VERSION is too old, need >= 2.20.3 for 'include:'"
fi
ok "docker compose $COMPOSE_VERSION"

[ -f .env ] || die ".env missing — copy .env.example and fill it in"
set -a; . ./.env; set +a
ok ".env loaded"

for var in POSTGRES_PASSWORD POSTGRES_DB POSTGRES_PORT JWT_SECRET ANON_KEY \
           SERVICE_ROLE_KEY KONG_HTTP_PORT; do
    [ -n "${!var:-}" ] || die "$var is empty in .env"
done
ok "required variables set"

case "$JWT_SECRET" in
    your-super-secret*) warn "JWT_SECRET is still the .env.example demo value" ;;
esac

# Compose interpolates and validates the whole file before selecting services, so a
# variable missing from .env is fatal even for services this run never starts (an empty
# PS_PORT collapses "${PS_PORT}:${PS_PORT}" to ":" -> "no port specified: :<empty>").
if docker compose config -q 2>"$RUN_TMP/config.err"; then
    ok "compose file resolves with this .env"
else
    fail "docker compose config failed:"
    sed 's/^/      /' "$RUN_TMP/config.err"
    warn "a variable used by docker-compose.yaml is missing from .env"
    summary
    exit 1
fi

[ -f volumes/functions/main/index.ts ] || warn "volumes/functions submodule looks empty (git submodule update --init)"

if [ "$SEED_LOOKUP" -eq 1 ]; then
    [ -f supabase/seeds/public/lookup.sql ] \
        || die "supabase/seeds/public/lookup.sql missing (git submodule update --init)"
    ok "public seeds present"
fi

MIGRATION_COUNT="$(find supabase/migrations -maxdepth 1 -name '*.sql' | wc -l | tr -d ' ')"
[ "$MIGRATION_COUNT" -gt 0 ] || die "no migrations found in supabase/migrations"
ok "$MIGRATION_COUNT migrations found"

# ── Stage 2: reset to zero ───────────────────────────────────────────────────
if [ "$RESET" -eq 1 ]; then
    stage "2. Reset"
    printf '  This removes all containers, named volumes and:\n    %s/volumes/db/data\n' "$REPO_ROOT"
    if [ "$ASSUME_YES" -ne 1 ]; then
        printf '  Type "reset" to continue: '
        read -r answer
        [ "$answer" = "reset" ] || die "aborted"
    fi
    docker compose down -v --remove-orphans >/dev/null 2>&1
    rm -rf volumes/db/data
    ok "stack down, data directory removed"
else
    stage "2. Reset (skipped)"
    if [ -d volumes/db/data ] && [ -n "$(ls -A volumes/db/data 2>/dev/null)" ]; then
        warn "volumes/db/data is not empty — the init scripts in volumes/db/ will NOT run"
        warn "and the migrations will fail on an already-migrated database. Use --reset."
    fi
fi

# ── Stage 3: database first start ────────────────────────────────────────────
stage "3. Start database and auth"

if ! docker compose up -d db >/dev/null 2>"$RUN_TMP/up-db.err"; then
    fail "docker compose up -d db failed:"
    sed 's/^/      /' "$RUN_TMP/up-db.err"
    summary
    exit 1
fi

if retry 180 "db healthy" docker compose exec -T db pg_isready -U postgres -q; then
    ok "postgres accepting connections"
else
    docker compose logs --tail=40 db
    die "database did not become ready within 180s"
fi

# The init scripts only run on an empty PGDATA; verify they did.
if [ "$(psql_q "select count(*) from pg_roles where rolname = 'authenticator';")" = "1" ]; then
    ok "volumes/db init scripts ran (supabase roles exist)"
else
    die "supabase roles missing — PGDATA was not empty, rerun with --reset"
fi

# GoTrue owns the auth schema and adds columns such as auth.users.email_confirmed_at
# through its own migrations at startup. Application migrations reference those columns
# (e.g. the on_auth_user_created trigger in 20250115140818_public.sql), so auth must have
# migrated before any of them can be applied.
if ! docker compose up -d auth >/dev/null 2>"$RUN_TMP/up-auth.err"; then
    fail "docker compose up -d auth failed:"
    sed 's/^/      /' "$RUN_TMP/up-auth.err"
    summary
    exit 1
fi

if retry 180 "auth migrations" bash -c \
    "[ \"\$(docker compose exec -T db psql -U postgres -d ${POSTGRES_DB} --no-psqlrc -t -A -c \"select count(*) from information_schema.columns where table_schema='auth' and table_name='users' and column_name='email_confirmed_at';\" 2>/dev/null)\" = '1' ]"
then
    ok "auth schema migrated (auth.users.email_confirmed_at present)"
else
    docker compose logs --tail=40 auth
    die "GoTrue did not migrate the auth schema within 180s — migrations would fail"
fi

# ── Stage 4: migrations ──────────────────────────────────────────────────────
stage "4. Apply migrations"

applied=0
for f in supabase/migrations/*.sql; do
    if docker compose exec -T db psql -U postgres -d "${POSTGRES_DB}" \
        --no-psqlrc -q --set ON_ERROR_STOP=on -f - < "$f" >/dev/null 2>"$RUN_TMP/migrate.err"
    then
        applied=$((applied+1))
    else
        fail "migration failed: $f"
        sed 's/^/      /' "$RUN_TMP/migrate.err"
        summary
        exit 1
    fi
done
ok "$applied/$MIGRATION_COUNT migrations applied"

for schema in lookup inventory_archive derived public; do
    if [ "$(psql_q "select count(*) from information_schema.schemata where schema_name = '$schema';")" = "1" ]; then
        ok "schema $schema exists"
    else
        fail "schema $schema missing"
    fi
done

ia_tables="$(psql_q "select count(*) from information_schema.tables where table_schema = 'inventory_archive';")"
[ "${ia_tables:-0}" -gt 0 ] \
    && ok "inventory_archive has $ia_tables tables" \
    || fail "inventory_archive has no tables"

[ "$(psql_q "select count(*) from pg_publication where pubname = 'powersync';")" = "1" ] \
    && ok "publication powersync created" \
    || fail "publication powersync missing"

# ── Stage 5: seed mechanics (lookup only) ────────────────────────────────────
if [ "$SEED_LOOKUP" -eq 1 ]; then
    stage "5. Seed lookup schema"

    docker compose exec -T db psql -U postgres -d "${POSTGRES_DB}" \
        --no-psqlrc -q --set ON_ERROR_STOP=on -f - < supabase/seeds/public/lookup.sql \
        >/dev/null 2>&1 || die "lookup.sql failed to load"

    first="$(psql_q "select count(*) from lookup.lookup_cover_percentage;")"
    [ "${first:-0}" -gt 0 ] \
        && ok "lookup.lookup_cover_percentage has $first rows" \
        || fail "lookup seed loaded no rows"

    # lookup.sql carries ON CONFLICT (code) DO NOTHING — loading it twice must
    # not change anything. This validates the idempotency claim in the docs.
    docker compose exec -T db psql -U postgres -d "${POSTGRES_DB}" \
        --no-psqlrc -q --set ON_ERROR_STOP=on -f - < supabase/seeds/public/lookup.sql \
        >/dev/null 2>&1 || die "lookup.sql is not re-runnable"
    second="$(psql_q "select count(*) from lookup.lookup_cover_percentage;")"
    [ "$first" = "$second" ] \
        && ok "lookup seed is idempotent ($second rows after second load)" \
        || fail "row count changed on second load: $first -> $second"
else
    stage "5. Seed lookup schema (skipped)"
fi

# ── Stage 6: full stack ──────────────────────────────────────────────────────
stage "6. Start remaining services"

CORE_SERVICES="kong auth rest realtime storage imgproxy meta functions studio"

if [ "$WITH_POWERSYNC" -eq 1 ]; then
    up_ok=0
    docker compose up -d >/dev/null 2>"$RUN_TMP/up.err" && up_ok=1
    label="full stack started"
else
    # mongo/mongo-rs-init arrive through include:, so services must be named
    # explicitly to keep them down.
    up_ok=0
    # shellcheck disable=SC2086
    docker compose up -d db $CORE_SERVICES >/dev/null 2>"$RUN_TMP/up.err" && up_ok=1
    label="stack started without powersync/mongo"
fi

if [ "$up_ok" -eq 1 ]; then
    ok "$label"
else
    fail "docker compose up -d failed:"
    sed 's/^/      /' "$RUN_TMP/up.err"
    summary
    exit 1
fi

for svc in db kong auth rest functions; do
    state="$(docker compose ps --format '{{.State}}' "$svc" 2>/dev/null | head -1)"
    [ "$state" = "running" ] \
        && ok "$svc running" \
        || fail "$svc is '$state', expected running"
done

if [ "$WITH_POWERSYNC" -eq 1 ]; then
    rs_state="$(docker compose ps -a --format '{{.State}}' mongo-rs-init 2>/dev/null | head -1)"
    rs_code="$(docker inspect -f '{{.State.ExitCode}}' \
        "$(docker compose ps -aq mongo-rs-init 2>/dev/null | head -1)" 2>/dev/null)"
    if [ "${rs_code:-1}" = "0" ]; then
        ok "mongo-rs-init completed (replica set rs0 initialised)"
    else
        fail "mongo-rs-init state='$rs_state' exit=${rs_code:-?} — expected exit 0"
    fi
else
    mongo_running="$(docker compose ps --format '{{.Name}}' 2>/dev/null | grep -c mongo)"
    [ "$mongo_running" = "0" ] \
        && ok "no mongo containers running" \
        || fail "$mongo_running mongo container(s) running despite --no-powersync"
fi

# ── Stage 7: endpoints ───────────────────────────────────────────────────────
stage "7. Endpoints"

KONG="http://127.0.0.1:${KONG_HTTP_PORT}"

if retry 120 "kong" bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H 'apikey: ${ANON_KEY}' '${KONG}/rest/v1/')\" = '200' ]"; then
    ok "GET /rest/v1/ → 200 (PostgREST through Kong)"
else
    fail "GET /rest/v1/ → $(http_code -H "apikey: ${ANON_KEY}" "${KONG}/rest/v1/") (expected 200)"
fi

code="$(http_code -H "apikey: ${ANON_KEY}" "${KONG}/auth/v1/health")"
[ "$code" = "200" ] && ok "GET /auth/v1/health → 200" || fail "GET /auth/v1/health → $code"

# The functions-v1 route has no key-auth plugin in volumes/api/kong.yml.
if retry 120 "functions" bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 '${KONG}/functions/v1/health')\" = '200' ]"; then
    ok "GET /functions/v1/health → 200 (edge runtime)"
else
    fail "GET /functions/v1/health → $(http_code "${KONG}/functions/v1/health") (expected 200)"
fi

if [ "$WITH_POWERSYNC" -eq 1 ]; then
    PS="http://127.0.0.1:${PS_PORT:-8181}"
    if retry 180 "powersync" bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 '${PS}/probes/liveness')\" = '200' ]"; then
        ok "GET ${PS}/probes/liveness → 200"
    else
        docker compose logs --tail=30 powersync
        fail "powersync liveness probe failed"
    fi

    # PowerSync creates its replication slot on first connect.
    if retry 180 "slot" bash -c "[ \"\$(docker compose exec -T db psql -U postgres -d ${POSTGRES_DB} --no-psqlrc -t -A -c \"select count(*) from pg_replication_slots where active;\" 2>/dev/null)\" != '0' ]"; then
        slot="$(psql_q "select slot_name || ' (' || wal_status || ')' from pg_replication_slots where active limit 1;")"
        ok "active replication slot: $slot"
    else
        fail "no active replication slot — powersync is not replicating"
    fi
else
    slots="$(psql_q "select count(*) from pg_replication_slots;")"
    [ "${slots:-0}" = "0" ] \
        && ok "no replication slot exists (expected without powersync)" \
        || warn "$slots replication slot(s) present without powersync running"
fi

# ── Stage 8: teardown ────────────────────────────────────────────────────────
if [ "$TEARDOWN" -eq 1 ]; then
    stage "8. Teardown"
    docker compose down -v --remove-orphans >/dev/null 2>&1
    rm -rf volumes/db/data
    ok "stack removed, data directory cleaned"
else
    stage "8. Teardown (skipped)"
    printf '  Stack left running. Clean up with:\n'
    printf '    docker compose down -v --remove-orphans && rm -rf volumes/db/data\n'
fi

summary
[ "$FAILED" -eq 0 ] || exit 1
