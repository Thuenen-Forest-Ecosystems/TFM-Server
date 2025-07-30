#! /bin/bash

#set -e  # Exit on error
set -a && source ../.env && set +a

clean_sql_file() {
    local file=$1
    # Remove transaction_timeout line and add replication role setting
    sed -i '' '/SET transaction_timeout/d' "$file"
    echo "SET session_replication_role = replica;" | cat - "$file" > temp && mv temp "$file"
}

# DUMP inventory_archive
PGPASSWORD=postgres pg_dump \
    -h 127.0.0.1 \
    -p 54322 \
    -U postgres \
    -d postgres \
    -n lookup \
    --data-only \
    --enable-row-security \
    > tmp/lookup.sql
clean_sql_file tmp/lookup.sql

# DUMP inventory_archive
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

# Truncate all tables in lookup schema
psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" \
  -t \
  -c "SELECT 'TRUNCATE TABLE lookup.' || tablename || ' CASCADE;' 
      FROM pg_tables 
      WHERE schemaname = 'lookup';" | \
while read cmd; do
  psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" -c "$cmd"
done

# Truncate all tables in inventory_archive schema
psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" \
  -t \
  -c "SELECT 'TRUNCATE TABLE inventory_archive.' || tablename || ' CASCADE;' 
      FROM pg_tables 
      WHERE schemaname = 'inventory_archive';" | \
while read cmd; do
  psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" -c "$cmd"
done

sleep 1

for file in tmp/*.sql; do
    psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" -f $file
done;