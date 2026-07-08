#!/bin/bash

set -a && source ../.env && set +a

echo "=== Starting SELECTIVE sync FROM remote TO local ==="
echo "⚠️  WARNING: This will OVERRIDE your local public schema data!"
echo "Note: Auth schema will NOT be synced (it's managed by Supabase)"
echo ""

REMOTE_DB="postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB"
LOCAL_DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"

# Common tables to exclude for development (too large, not needed locally)
# Uncomment or add tables you want to skip:
EXCLUDE_TABLES=(
    # Examples - modify as needed:
    # "--exclude-table-data=public.logs"
    # "--exclude-table-data=public.analytics"
    # "--exclude-table-data=public.audit_trail"
)

# Add any additional excludes from command line
ADDITIONAL_EXCLUDES=("$@")

# Step 1: Drop existing PUBLIC tables only (skip auth - it's managed by Supabase)
echo "Step 1: Dropping public tables on LOCAL..."
psql "$LOCAL_DB" -q \
  -t \
  -c "SELECT 'DROP TABLE IF EXISTS public.' || tablename || ' CASCADE;' 
      FROM pg_tables 
      WHERE schemaname = 'public'
      AND tablename NOT LIKE '_%'
      AND tablename NOT LIKE 'storage_%';" | \
while read cmd; do
  [ -n "$cmd" ] && psql "$LOCAL_DB" -q -c "$cmd"
done

# Step 2: Sync public schema structure
echo ""
echo "Step 2: Streaming public schema structure..."
pg_dump "$REMOTE_DB" \
    -n public \
    --exclude-table='public._*' \
    --exclude-table='public.storage_*' \
    --schema-only \
    --no-owner \
    --no-acl | \
psql "$LOCAL_DB" -q

# Step 3: Sync public data (with exclusions, using compressed custom format)
echo ""
echo "Step 3: Streaming public data (excluding large tables)..."
if [ ${#EXCLUDE_TABLES[@]} -gt 0 ] || [ ${#ADDITIONAL_EXCLUDES[@]} -gt 0 ]; then
    echo "Excluding tables:"
    printf '%s\n' "${EXCLUDE_TABLES[@]}" "${ADDITIONAL_EXCLUDES[@]}" | grep -v "^$"
fi

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
    --disable-triggers \
    --no-owner \
    --no-acl \
    --single-transaction 2>&1 | grep -v "WARNING"

echo "✓ Public schema synced!"

echo ""
echo "=== Sync completed successfully! ==="
echo "Local public schema now matches remote (excluding large tables)"
echo "Note: Auth schema was NOT synced (managed by Supabase)"
echo ""
echo "To exclude specific tables, run:"
echo "./remote-to-local-sync-selective.sh --exclude-table-data='public.table_name'"
