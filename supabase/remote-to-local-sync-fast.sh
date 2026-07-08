#!/bin/bash

set -a && source ../.env && set +a

echo "=== Starting FAST sync FROM remote TO local ==="
echo "⚠️  WARNING: This will OVERRIDE your local auth users and public schema data!"
echo "Remote server will NOT be modified (read-only operations)"
echo ""
echo "Using direct streaming (no intermediate files) for maximum speed..."
echo ""

REMOTE_DB="postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB"
LOCAL_DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"

# Step 1: Drop existing tables in LOCAL first
echo "Step 1: Dropping auth tables on LOCAL..."
psql "$LOCAL_DB" -c "
DO \$do\$
BEGIN
    EXECUTE (
        SELECT string_agg('DROP TABLE IF EXISTS auth.' || tablename || ' CASCADE;', ' ')
        FROM pg_tables
        WHERE schemaname = 'auth'
    );
END \$do\$;
"

echo "Step 2: Dropping public tables on LOCAL..."
psql "$LOCAL_DB" \
  -t \
  -c "SELECT 'DROP TABLE IF EXISTS public.' || tablename || ' CASCADE;' 
      FROM pg_tables 
      WHERE schemaname = 'public'
      AND tablename NOT LIKE '_%'
      AND tablename NOT LIKE 'storage_%';" | \
while read cmd; do
  [ -n "$cmd" ] && psql "$LOCAL_DB" -c "$cmd"
done

# Step 2: Stream auth schema+data directly (no files)
echo ""
echo "Step 3: Streaming auth schema from remote to local..."
pg_dump "$REMOTE_DB" \
    -n auth \
    --schema-only \
    --no-owner \
    --no-acl | \
psql "$LOCAL_DB" -q

echo "Step 4: Streaming auth data from remote to local..."
pg_dump "$REMOTE_DB" \
    -n auth \
    --data-only \
    --disable-triggers \
    --no-owner \
    --no-acl | \
psql "$LOCAL_DB" -q -v ON_ERROR_STOP=1 -c "SET session_replication_role = replica;" --single-transaction

echo "✓ Auth schema synced!"

# Step 3: Stream public schema+data directly (compressed in transit)
echo ""
echo "Step 5: Streaming public schema from remote to local..."
pg_dump "$REMOTE_DB" \
    -n public \
    --exclude-table='public._*' \
    --exclude-table='public.storage_*' \
    --schema-only \
    --no-owner \
    --no-acl | \
psql "$LOCAL_DB" -q

echo "Step 6: Streaming public data from remote to local (this is the slow part)..."
echo "Progress: Starting large data transfer..."

# Use custom format with compression for speed
pg_dump "$REMOTE_DB" \
    -n public \
    --exclude-table='public._*' \
    --exclude-table='public.storage_*' \
    --data-only \
    --disable-triggers \
    --no-owner \
    --no-acl \
    -Fc -Z6 | \
pg_restore -d "$LOCAL_DB" \
    --disable-triggers \
    --no-owner \
    --no-acl \
    --single-transaction

echo "✓ Public schema synced!"

# Re-enable triggers
psql "$LOCAL_DB" -q -c "SET session_replication_role = default;"

echo ""
echo "=== Sync completed successfully! ==="
echo "Local Supabase now matches remote server data"
echo "Remote server was NOT modified (read-only)"
