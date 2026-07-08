#!/bin/bash

set -a && source ../.env && set +a

# Create tmp directory if it doesn't exist
mkdir -p tmp

echo "=== Starting full sync to remote server ==="

clean_sql_file() {
    local file=$1
    sed -i '' '/SET transaction_timeout/d' "$file"
    echo "SET session_replication_role = replica;" | cat - "$file" > temp && mv temp "$file"
}

# Step 1: Dump both schemas in parallel from local Supabase
echo "Step 1: Dumping lookup schema..."
docker exec -u postgres supabase_db_supabase pg_dump \
    -h 127.0.0.1 \
    -p 5432 \
    -U postgres \
    -d postgres \
    -n lookup \
    --schema-only \
    --enable-row-security \
    > tmp/lookup_schema.sql &
DUMP1=$!

docker exec -u postgres supabase_db_supabase pg_dump \
    -h 127.0.0.1 \
    -p 5432 \
    -U postgres \
    -d postgres \
    -n lookup \
    --data-only \
    --enable-row-security \
    > tmp/lookup.sql &
DUMP2=$!

echo "Step 2: Dumping inventory_archive schema..."
docker exec -u postgres supabase_db_supabase pg_dump \
    -h 127.0.0.1 \
    -p 5432 \
    -U postgres \
    -d postgres \
    -n inventory_archive \
    --schema-only \
    --enable-row-security \
    > tmp/inventory_archive_schema.sql &
DUMP3=$!

docker exec -u postgres supabase_db_supabase pg_dump \
    -h 127.0.0.1 \
    -p 5432 \
    -U postgres \
    -d postgres \
    -n inventory_archive \
    --data-only \
    --enable-row-security \
    > tmp/inventory_archive.sql &
DUMP4=$!

# Wait for all dumps to complete
echo "Waiting for all dumps to complete..."
wait $DUMP1 $DUMP2 $DUMP3 $DUMP4
echo "All dumps completed!"

# Clean all SQL files
echo "Cleaning SQL files..."
clean_sql_file tmp/lookup_schema.sql
clean_sql_file tmp/lookup.sql
clean_sql_file tmp/inventory_archive_schema.sql
clean_sql_file tmp/inventory_archive.sql

REMOTE_DB="postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB"

# Step 2: Upload lookup first (relationships dependency)
echo "Step 3: Dropping lookup tables on remote..."
psql "$REMOTE_DB" -c "
DO
\$do\$
BEGIN
    EXECUTE (
        SELECT string_agg('DROP TABLE IF EXISTS lookup.' || tablename || ' CASCADE;', ' ')
        FROM pg_tables
        WHERE schemaname = 'lookup'
    );
END
\$do\$;
"

echo "Step 4: Uploading lookup schema and data to remote..."
psql "$REMOTE_DB" -f tmp/lookup_schema.sql
psql "$REMOTE_DB" -f tmp/lookup.sql
echo "Lookup schema uploaded!"

# Step 3: Upload inventory_archive
echo "Step 5: Dropping inventory_archive tables on remote..."
psql "$REMOTE_DB" \
  -t \
  -c "SELECT 'DROP TABLE IF EXISTS inventory_archive.' || tablename || ' CASCADE;' 
      FROM pg_tables 
      WHERE schemaname = 'inventory_archive';" | \
while read cmd; do
  [ -n "$cmd" ] && psql "$REMOTE_DB" -c "$cmd"
done

echo "Step 6: Uploading inventory_archive schema and data to remote..."
psql "$REMOTE_DB" -f tmp/inventory_archive_schema.sql
psql "$REMOTE_DB" -f tmp/inventory_archive.sql
echo "Inventory_archive schema uploaded!"

echo "=== Sync completed successfully! ==="
