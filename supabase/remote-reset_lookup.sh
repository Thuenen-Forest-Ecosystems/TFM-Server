#! /bin/bash

#set -e  # Exit on error
set -a && source ../.env && set +a

clean_sql_file() {
    local file=$1
    # Remove transaction_timeout line and add replication role setting
    sed -i '' '/SET transaction_timeout/d' "$file"
    echo "SET session_replication_role = replica;" | cat - "$file" > temp && mv temp "$file"
}

# DUMMP inventory_archive schema
docker exec -u postgres supabase_db_supabase pg_dump \
    -h 127.0.0.1 \
    -p 5432 \
    -U postgres \
    -d postgres \
    -n lookup \
    --schema-only \
    --enable-row-security \
    > tmp/lookup_schema.sql
clean_sql_file tmp/lookup_schema.sql

# DUMP lookup
docker exec -u postgres supabase_db_supabase pg_dump \
    -h 127.0.0.1 \
    -p 5432 \
    -U postgres \
    -d postgres \
    -n lookup \
    --data-only \
    --enable-row-security \
    > tmp/lookup.sql
clean_sql_file tmp/lookup.sql

psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" -c "
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
psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" -f tmp/lookup_schema.sql
psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" -f tmp/lookup.sql