#! /bin/bash

#set -e  # Exit on error
set -a && source ../.env && set +a

# Drop all tables in the 'inventory_archive' schema
psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" -c "
DO
\$do\$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_tables
        WHERE schemaname = 'inventory_archive'
    ) THEN
        EXECUTE (
            SELECT string_agg('DROP TABLE IF EXISTS inventory_archive.' || tablename || ' CASCADE;', ' ')
            FROM pg_tables
            WHERE schemaname = 'inventory_archive'
        );
    END IF;
END
\$do\$;
"

sleep 1

# Tables already exist, so we skip schema creation and go directly to data insertion
# Add all data in lookup schema from lookup.sql
psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" -f tmp/inventory_archive_schema.sql
psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" -f tmp/inventory_archive.sql