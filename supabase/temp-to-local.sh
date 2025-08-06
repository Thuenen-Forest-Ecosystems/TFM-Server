#! /bin/bash

#set -e  # Exit on error
set -a && source ../.env && set +a

psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "
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

sleep 1

# Tables already exist, so we skip schema creation and go directly to data insertion
# Add all data in lookup schema from lookup.sql
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f tmp/lookup_schema.sql
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f tmp/lookup.sql

sleep 2

# Remove all tables in inventory_archive schema
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  -t \
  -c "SELECT 'DROP TABLE inventory_archive.' || tablename || ' CASCADE;' 
      FROM pg_tables 
      WHERE schemaname = 'inventory_archive';" | \
while read cmd; do
  psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "$cmd"
done

sleep 1

# Add all tables in inventory_archive schema from inventory_archive_schema.sql
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f tmp/inventory_archive_schema.sql
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f tmp/inventory_archive.sql