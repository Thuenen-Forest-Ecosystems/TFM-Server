#! /bin/bash

#set -e  # Exit on error
set -a && source ../.env && set +a

clean_sql_file() {
    local file=$1
    # Remove transaction_timeout line and add replication role setting
    sed -i '' '/SET transaction_timeout/d' "$file"
    echo "SET session_replication_role = replica;" | cat - "$file" > temp && mv temp "$file"
    echo "SET search_path TO public, inventory_archive;" | cat - "$file" > temp && mv temp "$file"
}

# DUMP inventory_archive
PGPASSWORD=postgres pg_dump \
    -h 127.0.0.1 \
    -p 54322 \
    -U postgres \
    -d postgres \
    -n inventory_archive \
    -c \
    --enable-row-security \
    > new.sql

clean_sql_file new.sql

#Drop all tables
#psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/postgres" -f "drop_all.sql"

#psql
psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/postgres" -f "new.sql"

rm new.sql