#!/bin/bash

set -a && source ../.env && set +a

# Create tmp directory if it doesn't exist
mkdir -p tmp

echo "=== Starting sync FROM remote TO local ==="
echo "⚠️  WARNING: This will OVERRIDE your local auth users and public schema data!"
echo "Remote server will NOT be modified (read-only operations)"
echo ""

REMOTE_DB="postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB"
LOCAL_DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"

clean_sql_file() {
    local file=$1
    sed -i '' '/SET transaction_timeout/d' "$file"
    echo "SET session_replication_role = replica;" | cat - "$file" > temp && mv temp "$file"
}

# Step 1: Dump from REMOTE server (parallel for speed)
echo "Step 1: Dumping public schema from REMOTE..."
pg_dump "$REMOTE_DB" \
    -n public \
    --exclude-table='public._*' \
    --exclude-table='public.storage_*' \
    --schema-only \
    --no-owner \
    --no-acl \
    -v \
    > tmp/remote_public_schema.sql 2>&1 &
DUMP1=$!

pg_dump "$REMOTE_DB" \
    -n public \
    --exclude-table='public._*' \
    --exclude-table='public.storage_*' \
    --data-only \
    --disable-triggers \
    --no-owner \
    --no-acl \
    -v \
    > tmp/remote_public_data.sql 2>&1 &
DUMP2=$!

echo "Step 2: Dumping auth schema from REMOTE..."
pg_dump "$REMOTE_DB" \
    -n auth \
    --schema-only \
    --no-owner \
    --no-acl \
    -v \
    > tmp/remote_auth_schema.sql 2>&1 &
DUMP3=$!

pg_dump "$REMOTE_DB" \
    -n auth \
    --data-only \
    --disable-triggers \
    --no-owner \
    --no-acl \
    -v \
    > tmp/remote_auth_data.sql 2>&1 &
DUMP4=$!

echo "Waiting for all dumps to complete (this may take several minutes for large databases)..."
echo "Progress: Monitoring dump processes..."

# Monitor progress
while kill -0 $DUMP1 2>/dev/null || kill -0 $DUMP2 2>/dev/null || kill -0 $DUMP3 2>/dev/null || kill -0 $DUMP4 2>/dev/null; do
    sleep 5
    echo -n "."
done
echo ""

wait $DUMP1 $DUMP2 $DUMP3 $DUMP4
echo "✓ All dumps from remote completed!"

# Clean SQL files
echo "Cleaning SQL files..."
clean_sql_file tmp/remote_public_schema.sql
clean_sql_file tmp/remote_public_data.sql
clean_sql_file tmp/remote_auth_schema.sql
clean_sql_file tmp/remote_auth_data.sql

# Step 2: Drop existing tables in LOCAL (auth first, then public)
echo ""
echo "Step 3: Dropping auth tables on LOCAL..."
psql "$LOCAL_DB" -c "
DO
\$do\$
BEGIN
    EXECUTE (
        SELECT string_agg('DROP TABLE IF EXISTS auth.' || tablename || ' CASCADE;', ' ')
        FROM pg_tables
        WHERE schemaname = 'auth'
    );
END
\$do\$;
"

echo "Step 4: Dropping public tables on LOCAL..."
# Drop public tables but exclude Supabase internal ones
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

# Step 3: Restore to LOCAL
echo ""
echo "Step 5: Restoring auth schema to LOCAL..."
psql "$LOCAL_DB" -f tmp/remote_auth_schema.sql

echo "Step 6: Restoring auth data to LOCAL..."
psql "$LOCAL_DB" -v ON_ERROR_STOP=1 <<-EOSQL
	SET session_replication_role = replica;
	\i tmp/remote_auth_data.sql
	SET session_replication_role = default;
EOSQL
echo "✓ Auth schema synced!"

echo ""
echo "Step 7: Restoring public schema to LOCAL..."
psql "$LOCAL_DB" -f tmp/remote_public_schema.sql

echo "Step 8: Restoring public data to LOCAL (with triggers disabled)..."
psql "$LOCAL_DB" -v ON_ERROR_STOP=1 <<-EOSQL
	SET session_replication_role = replica;
	\i tmp/remote_public_data.sql
	SET session_replication_role = default;
EOSQL
echo "✓ Public schema synced!"

echo ""
echo "=== Sync completed successfully! ==="
echo "Local Supabase now matches remote server data"
echo "Remote server was NOT modified (read-only)"
