#!/bin/bash

set -a && source ../.env && set +a

echo "=== Starting DATA-ONLY sync FROM remote TO local ==="
echo "⚠️  This will TRUNCATE and reload data in public schema tables"
echo "Assumes: local schema structure already matches remote"
echo ""

REMOTE_DB="postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB"
LOCAL_DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"

# Tables to exclude (add large tables you don't need)
EXCLUDE_TABLES=(
    "--exclude-table-data=public.record_changes"  # Huge table, usually not needed locally
)

# Add any additional excludes from command line
ADDITIONAL_EXCLUDES=("$@")

echo "Step 1: Truncating tables (with triggers disabled)..."
psql "$LOCAL_DB" -q -v ON_ERROR_STOP=0 <<-EOSQL
    SET session_replication_role = replica;
    
    -- Truncate all public tables (except excluded ones and Supabase internal)
    TRUNCATE TABLE public.organizations CASCADE;
    TRUNCATE TABLE public.organizations_lose CASCADE;
    TRUNCATE TABLE public.r_monitor CASCADE;
    TRUNCATE TABLE public.records CASCADE;
    TRUNCATE TABLE public.records_messages CASCADE;
    TRUNCATE TABLE public.schemas CASCADE;
    TRUNCATE TABLE public.troop CASCADE;
    TRUNCATE TABLE public.troop_members CASCADE;
    TRUNCATE TABLE public.users_permissions CASCADE;
    TRUNCATE TABLE public.users_profile CASCADE;
    
    SET session_replication_role = default;
EOSQL

echo ""
echo "Step 2: Streaming data from remote to local (compressed)..."
echo "This may take 5-15 minutes for large databases..."
if [ ${#EXCLUDE_TABLES[@]} -gt 0 ] || [ ${#ADDITIONAL_EXCLUDES[@]} -gt 0 ]; then
    echo "Excluding large tables:"
    printf '%s\n' "${EXCLUDE_TABLES[@]}" "${ADDITIONAL_EXCLUDES[@]}" | grep -v "^$"
fi

# Stream data directly with compression
pg_dump "$REMOTE_DB" \
    -n public \
    --exclude-table='public._*' \
    --exclude-table='public.storage_*' \
    "${EXCLUDE_TABLES[@]}" \
    "${ADDITIONAL_EXCLUDES[@]}" \
    --data-only \
    --no-owner \
    --no-acl \
    -Fc -Z6 | \
pg_restore -d "$LOCAL_DB" \
    --data-only \
    --disable-triggers \
    --no-owner \
    --no-acl \
    --exit-on-error 2>&1

echo "✓ Data synced!"

echo ""
echo "=== Sync completed! ==="
echo "To exclude additional tables, run:"
echo "./remote-to-local-data-only.sh --exclude-table-data='public.table_name'"
