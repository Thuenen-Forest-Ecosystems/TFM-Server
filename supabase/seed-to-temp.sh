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
    -n inventory_archive \
    --schema-only \
    --enable-row-security \
    > tmp/inventory_archive_schema.sql
clean_sql_file tmp/inventory_archive_schema.sql

# DUMP inventory_archive data
docker exec -u postgres supabase_db_supabase pg_dump \
    -h 127.0.0.1 \
    -p 5432 \
    -U postgres \
    -d postgres \
    -n inventory_archive \
    --data-only \
    --enable-row-security \
    > tmp/inventory_archive.sql
clean_sql_file tmp/inventory_archive.sql

# Truncate all tables in inventory_archive schema
#psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" \
#  -t \
#  -c "SELECT 'TRUNCATE TABLE inventory_archive.' || tablename || ' CASCADE;' 
#      FROM pg_tables 
#      WHERE schemaname = 'inventory_archive';" | \
#while read cmd; do
#  psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" -c "$cmd"
#done
#
#sleep 1
#
#psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB" -f tmp/inventory_archive.sql

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