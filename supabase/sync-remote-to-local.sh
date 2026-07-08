#!/bin/bash

set -a && source ../.env && set +a

echo "=== FAST CLEAN SYNC: Remote → Local ==="
echo "⚠️  This will completely DROP and RECREATE public schema tables!"
echo "Auth schema will NOT be touched (managed by Supabase)"
echo ""

REMOTE_DB="postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB"
LOCAL_DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"

# Tables to exclude by default (add large tables here)
EXCLUDE_TABLES=(
    # Uncomment to skip large tables:
    # "--exclude-table-data=public.record_changes"
)

# Add any additional excludes from command line
ADDITIONAL_EXCLUDES=("$@")

if [ ${#EXCLUDE_TABLES[@]} -gt 0 ] || [ ${#ADDITIONAL_EXCLUDES[@]} -gt 0 ]; then
    echo "Excluding tables:"
    printf '%s\n' "${EXCLUDE_TABLES[@]}" "${ADDITIONAL_EXCLUDES[@]}" | grep -v "^$" | sed 's/--exclude-table-data=/  - /'
    echo ""
fi

# Step 1: Drop and recreate public schema for CLEAN sync
echo "Step 1: Dropping and recreating public schema on LOCAL..."
psql "$LOCAL_DB" <<-EOSQL
    -- Drop the entire public schema (this removes EVERYTHING)
    DROP SCHEMA IF EXISTS public CASCADE;
    
    -- Recreate empty public schema
    CREATE SCHEMA public;
    GRANT ALL ON SCHEMA public TO postgres;
    GRANT ALL ON SCHEMA public TO public;
EOSQL

echo "✓ Public schema recreated (clean slate)"

# Step 2: Stream schema structure from remote to local
echo ""
echo "Step 2: Streaming public schema structure from remote..."
echo "(Deferring plot_nested_json views until after data import...)"
pg_dump "$REMOTE_DB" \
    -n public \
    --exclude-table='public._*' \
    --exclude-table='public.storage_*' \
    --schema-only \
    --no-owner \
    --no-acl | \
sed '/SET transaction_timeout/d' | \
grep -v 'plot_nested_json' | \
psql "$LOCAL_DB" -q -v ON_ERROR_STOP=0

echo "✓ Schema structure synced (views deferred)"

# Step 3: Stream data from remote to local (with trigger disabling)
echo ""
echo "Step 3: Streaming data from remote..."
echo "This will take several minutes. Please wait..."
pg_dump "$REMOTE_DB" \
    -n public \
    --exclude-table='public._*' \
    --exclude-table='public.storage_*' \
    "${EXCLUDE_TABLES[@]}" \
    "${ADDITIONAL_EXCLUDES[@]}" \
    --data-only \
    --no-owner \
    --no-acl | \
sed '/SET transaction_timeout/d' | \
psql "$LOCAL_DB" -v ON_ERROR_STOP=0 -v session_replication_role=replica

echo "✓ Data synced!"

# Step 4: Run deferred migrations (plot views that need all data loaded first)
echo ""
echo "Step 4: Creating plot_nested_json views (post-data)..."
psql "$LOCAL_DB" -f migrations/20250312143819_functions.sql -q -v ON_ERROR_STOP=0

echo "✓ Views and functions created"

# Step 5: Quick verification
echo ""
echo "Step 5: Verifying sync..."
psql "$LOCAL_DB" -c "
SELECT 
    tablename,
    pg_size_pretty(pg_total_relation_size('public.'||tablename)) AS size
FROM pg_tables 
WHERE schemaname = 'public'
AND tablename NOT LIKE '_%'
AND tablename NOT LIKE 'storage_%'
ORDER BY pg_total_relation_size('public.'||tablename) DESC
LIMIT 10;
"

echo ""
echo "=== Sync completed successfully! ==="
echo ""
echo "To exclude large tables, run:"
echo "./sync-remote-to-local.sh --exclude-table-data='public.record_changes'"
echo ""
echo "To populate plot_nested_json_cached (optional, takes ~5 min):"
echo "psql '$LOCAL_DB' -c 'SELECT public.refresh_plot_nested_json_cached();'"
