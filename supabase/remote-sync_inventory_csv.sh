#! /bin/bash

#set -e  # Exit on error
set -a && source ../.env && set +a

# DUMP inventory_archive schema
docker exec -u postgres supabase_db_supabase pg_dump \
    -h 127.0.0.1 \
    -p 5432 \
    -U postgres \
    -d postgres \
    -n inventory_archive \
    --schema-only \
    --enable-row-security \
    > tmp/inventory_archive_schema.sql

# Remove transaction_timeout line and add replication role setting
sed -i '' '/SET transaction_timeout/d' tmp/inventory_archive_schema.sql
echo "SET session_replication_role = replica;" | cat - tmp/inventory_archive_schema.sql > temp && mv temp tmp/inventory_archive_schema.sql

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

# Add all data in inventory_archive schema using COPY commands
# Get list of all tables in the schema
docker exec -u postgres supabase_db_supabase psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -t -c \
  "SELECT tablename FROM pg_tables WHERE schemaname = 'inventory_archive' ORDER BY tablename;" | \
while IFS= read -r table; do
  # Trim whitespace
  table=$(echo "$table" | xargs)
  
  if [ -n "$table" ]; then
    echo "Copying table: $table"
    
    # Export table data to CSV
    docker exec -u postgres supabase_db_supabase psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -c \
      "COPY inventory_archive.\"$table\" TO STDOUT WITH (FORMAT csv, HEADER false, DELIMITER ',', NULL '\\N');" \
      > "tmp/${table}.csv"
    
    # Import to remote database with session_replication_role set
    PGPASSWORD=$POSTGRES_PASSWORD psql -h 134.110.100.75 -p 3389 -U postgres -d $POSTGRES_DB -c \
      "SET session_replication_role = replica; COPY inventory_archive.\"$table\" FROM STDIN WITH (FORMAT csv, HEADER false, DELIMITER ',', NULL '\\N');" \
      < "tmp/${table}.csv"
    
    # Clean up CSV file
    rm "tmp/${table}.csv"
    
    echo "Completed: $table"
  fi
done

echo "All tables synced successfully"