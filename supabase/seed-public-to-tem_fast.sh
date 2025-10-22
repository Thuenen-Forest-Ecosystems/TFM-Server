#! /bin/bash

#set -e  # Exit on error
set -a && source ../.env && set +a

# Export password for pg_dump to use
export PGPASSWORD=$POSTGRES_PASSWORD

# #create tmp directory if it doesn't exist
mkdir -p tmp
# clean up tmp directory
rm -f tmp/*.sql

clean_sql_file() {
    local file=$1
    # Remove transaction_timeout line and add replication role setting
    sed -i '' '/SET transaction_timeout/d' "$file"
    echo "SET session_replication_role = replica;" | cat - "$file" > temp && mv temp "$file"
}
# Export schema and data from remote supabase instance
#need  password file (windows %appdata%\postgresql\pgpass.conf) (linux ~/.pgpass) otherwise it will prompt for password

pg_dump -h 134.110.100.75 -p 3389 -U postgres -d postgres -n public --exclude-table=record_changes > tmp/public_full.sql
clean_sql_file tmp/public_full.sql

#pg_dump -h 134.110.100.75 -p 3389  -U postgres  -d postgres -n public  --schema-only --jobs=4 > tmp/public_schema.sql
#clean_sql_file tmp/public_schema.sql
#
#pg_dump -h 134.110.100.75 -p 3389  -U postgres  -d postgres -n public  --data-only --jobs=4 --exclude-table=record_changes > tmp/public.sql
#clean_sql_file tmp/public.sql



# Import data into local supabase instance
# need local psql Installation to import whith supabase docker container

# Remove all tables in inventory_archive schema
psql -d "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  -t \
  -c "SELECT 'DROP TABLE \"public\".\"' || tablename || '\" CASCADE;' 
      FROM pg_tables 
      WHERE schemaname = 'public';" | \
while read cmd; do
  psql -d "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "$cmd"
done

sleep 1

psql -d "postgresql://postgres:postgres@127.0.0.1:54322/postgres"  -f "tmp/public_full.sql"

#psql -d "postgresql://postgres:postgres@127.0.0.1:54322/postgres"  -f "tmp/public_schema.sql"
#
#sleep 1
#
#psql -d "postgresql://postgres:postgres@127.0.0.1:54322/postgres"  -f "tmp/public.sql"
#
unset PGPASSWORD



