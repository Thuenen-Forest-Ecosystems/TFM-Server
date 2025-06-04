#! /bin/bash

#set -e  # Exit on error
set -a && source ../.env && set +a

clean_sql_file() {
    local file=$1
    # Remove transaction_timeout line and add replication role setting
    sed -i '' '/SET transaction_timeout/d' "$file"
    echo "SET session_replication_role = replica;" | cat - "$file" > temp && mv temp "$file"
}

# DUMP custom types/enums first
docker exec -u postgres supabase_db_supabase pg_dump \
    -h 127.0.0.1 \
    -p 5432 \
    -U postgres \
    -d postgres \
    --schema-only \
    --no-owner \
    --no-privileges \
    | grep -A 20 "CREATE TYPE" > tmp/custom_types.sql

# DUMP inventory_archive schema
docker exec -u postgres supabase_db_supabase pg_dump \
    -h 127.0.0.1 \
    -p 5432 \
    -U postgres \
    -d postgres \
    -n inventory_archive \
    --schema-only \
    --enable-row-security \
    > tmp/inventory_archive_schema_only.sql

# Combine them
cat tmp/custom_types.sql tmp/inventory_archive_schema_only.sql > tmp/inventory_archive_schema.sql
clean_sql_file tmp/inventory_archive_schema.sql

## DUMP inventory_archive
PGPASSWORD=postgres pg_dump \
    -h 127.0.0.1 \
    -p 54322 \
    -U postgres \
    -d postgres \
    -n inventory_archive \
    --data-only \
    --enable-row-security \
    > tmp/inventory_archive.sql
clean_sql_file tmp/inventory_archive.sql


sleep 1


# Remove all tables in inventory_archive schema
psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" \
  -t \
  -c "SELECT 'DROP TABLE inventory_archive.' || tablename || ' CASCADE;' 
      FROM pg_tables 
      WHERE schemaname = 'inventory_archive';" | \
while read cmd; do
  psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" -c "$cmd"
done

sleep 1

# Add all tables in inventory_archive schema from inventory_archive_schema.sql
psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" -f tmp/inventory_archive_schema.sql

sleep 1

# Add all data in inventory_archive schema from inventory_archive.sql
psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" -f tmp/inventory_archive.sql



# Start 18:44