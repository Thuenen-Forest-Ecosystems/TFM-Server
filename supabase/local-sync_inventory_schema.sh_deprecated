#! /bin/bash

#set -e  # Exit on error
set -a && source ../.env && set +a

# Remove all tables in inventory_archive schema
psql "postgres://postgres:postgres@127.0.0.1:54322/postgres" \
  -t \
  -c "SELECT 'DROP TABLE inventory_archive.' || tablename || ' CASCADE;' 
      FROM pg_tables 
      WHERE schemaname = 'inventory_archive';" | \
while read cmd; do
  psql "postgres://postgres:postgres@127.0.0.1:54322/postgres" -c "$cmd"
done

sleep 1

# Add all tables in inventory_archive schema from inventory_archive_schema.sql
psql "postgres://postgres:postgres@127.0.0.1:54322/postgres" -f tmp/inventory_archive_schema.sql

sleep 1

# Add all data in inventory_archive schema from inventory_archive.sql
psql "postgres://postgres:postgres@127.0.0.1:54322/postgres" -f tmp/inventory_archive.sql



# Start 18:44