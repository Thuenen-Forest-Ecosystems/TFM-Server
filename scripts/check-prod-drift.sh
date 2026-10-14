#!/usr/bin/env bash
# =============================================================================
# TFM-Server — find database objects that no migration file knows about
#
#   ./scripts/check-prod-drift.sh --db-url "postgresql://postgres:...@134.110.100.75:3389/postgres"
#   ./scripts/check-prod-drift.sh                      # local stack (127.0.0.1:54322)
#
# WHY THIS EXISTS
#   Objects created directly on production (Studio, ad-hoc psql) are invisible
#   to every local test: the restored snapshot may lack them, and no migration
#   adapts them. 20261014000000 failed its first push because two such views
#   (v_stats_workflow_plot_map / _map2) depended on a column it dropped.
#   Run this before `supabase db push`.
#
# WHAT IT CHECKS
#   Tables, views, materialized views, functions and triggers in the schemas
#   public, inventory_archive, lookup and derived (extension-owned objects
#   excluded). An object counts as known when its name appears in at least one
#   file under supabase/migrations/. Names only — a function whose body drifted
#   from its migration is NOT caught (see scripts/classify-migrations.py for that).
#
#   Read-only: one SELECT against the target.
#
# EXIT
#   0 = every object is mentioned in a migration, 1 = drift found, 2 = usage/connection error
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
while [ $# -gt 0 ]; do
    case "$1" in
        --db-url) DB_URL="${2:?--db-url needs a value}"; shift 2 ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
command -v psql >/dev/null || { echo "psql not found" >&2; exit 2; }

MIGRATIONS_DIR="supabase/migrations"

objects="$(psql "$DB_URL" --no-psqlrc -X -A -t -F $'\t' --set ON_ERROR_STOP=on -c "
    WITH ext AS (
        SELECT objid FROM pg_depend WHERE deptype = 'e'
    )
    SELECT n.nspname, CASE c.relkind WHEN 'r' THEN 'table' WHEN 'p' THEN 'table'
                                     WHEN 'v' THEN 'view' WHEN 'm' THEN 'matview' END, c.relname
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('public', 'inventory_archive', 'lookup', 'derived')
      AND c.relkind IN ('r', 'p', 'v', 'm')
      AND c.oid NOT IN (SELECT objid FROM ext)
    UNION
    SELECT n.nspname, 'function', p.proname
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname IN ('public', 'inventory_archive', 'lookup', 'derived')
      AND p.oid NOT IN (SELECT objid FROM ext)
    UNION
    SELECT n.nspname, 'trigger', t.tgname
    FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('public', 'inventory_archive', 'lookup', 'derived')
      AND NOT t.tgisinternal
    ORDER BY 1, 2, 3;")" || { echo "query failed against $DB_URL" >&2; exit 2; }

# One lowercase blob of all migrations; identifiers are matched as whole words
corpus="$(cat "$MIGRATIONS_DIR"/*.sql | tr '[:upper:]' '[:lower:]')"

unknown=0
total=0
while IFS=$'\t' read -r schema kind name; do
    [ -z "$name" ] && continue
    total=$((total + 1))
    lname="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
    if ! grep -qE "(^|[^a-z0-9_])${lname}([^a-z0-9_]|$)" <<<"$corpus"; then
        printf '  %-18s %-9s %s\n' "$schema" "$kind" "$name"
        unknown=$((unknown + 1))
    fi
done <<<"$objects"

echo
if [ "$unknown" -gt 0 ]; then
    echo "DRIFT: $unknown of $total objects are not mentioned in any migration (listed above)."
    echo "Version them in a migration (pg_get_viewdef / pg_get_functiondef) before pushing changes that touch their dependencies."
    exit 1
fi
echo "OK: all $total objects are mentioned in a migration."
