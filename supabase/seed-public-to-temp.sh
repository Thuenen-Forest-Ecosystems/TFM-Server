#! /bin/bash

#set -e  # Exit on error
set -a && source ../.env && set +a
#POSTGRES_PASSWORD=ESG34Epm97hndHHUVe5YvwV


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

pg_dump -h 134.110.100.75 -p 3389  -U postgres  -d postgres -n public  --schema-only --enable-row-security > tmp/public_schema.sql
clean_sql_file tmp/public_schema.sql

pg_dump -h 134.110.100.75 -p 3389  -U postgres  -d postgres -n public  --data-only --enable-row-security > tmp/public.sql
clean_sql_file tmp/public.sql

#   docker exec -u postgres supabase_db_supabase psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/postgres"\
#       -c "copy (SELECT * FROM public.records  LIMIT 5) to stdout with csv" > tmp/records.csv
      
#       docker cp ./tmp/records.csv supabase_db_supabase:/records.csv
#    #  COPY the_table_where_the_data_will_go FROM '/name_of_file.csv' CSV HEADER;

#   docker exec -u postgres supabase_db_supabase psql "postgres://postgres:postgres@127.0.0.1:5432/postgres"\
#      -c "copy  public.records FROM '/name_of_file.csv' CSV HEADER" 

#copy (select field1,field2 from table1) to stdout with csv" )
# docker exec -i supabase_db_supabase /bin/bash -c "PGPASSWORD=ESG34Epm97hndHHUVe5YvwV pg_dump --username postgres postgres \
# -h 134.110.100.75 -p 3389 -n public --schema-only --enable-row-security" > tmp/public_schema.sql



# Import data into local supabase instance

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

psql -d "postgresql://postgres:postgres@127.0.0.1:54322/postgres"  -f "tmp/public_schema.sql"

sleep 1

psql -d "postgresql://postgres:postgres@127.0.0.1:54322/postgres"  -f "tmp/public.sql"



