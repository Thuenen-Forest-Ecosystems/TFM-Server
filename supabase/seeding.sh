#! /bin/bash

#set -e  # Exit on error
set -a && source ../.env.local && set +a

# Create directories if they don't exist
mkdir -p seeds/public seeds/hidden

# Function to add replication role and remove transaction_timeout
clean_sql_file() {
    local file=$1
    # Remove transaction_timeout line and add replication role setting
    sed -i '' '/SET transaction_timeout/d' "$file"
    echo "SET session_replication_role = replica;" | cat - "$file" > temp && mv temp "$file"
}

# Dump lookup schema
PGPASSWORD=$POSTGRES_PASSWORD pg_dump \
    -h 127.0.0.1 \
    -p 54322 \
    -U postgres \
    -d postgres \
    -n lookup \
    --inserts \
    --rows-per-insert=10000 \
    --data-only \
    --enable-row-security \
    > seeds/public/lookup.sql
clean_sql_file seeds/public/lookup.sql


for table in cluster plot deadwood edges regeneration structure_lt4m tree
    do PGPASSWORD=$POSTGRES_PASSWORD pg_dump \
        -h 127.0.0.1 \
        -p 54322 \
        -U postgres \
        -d postgres \
        -n inventory_archive \
        --table inventory_archive.$table \
        --inserts \
        --rows-per-insert=10000 \
        --data-only \
        --enable-row-security \
        > seeds/public/$table.sql
    clean_sql_file seeds/public/$table.sql
done;

for table in plot_coordinates plot_landmark position subplots_relative_position
    do PGPASSWORD=$POSTGRES_PASSWORD pg_dump \
        -h 127.0.0.1 \
        -p 54322 \
        -U postgres \
        -d postgres \
        -n inventory_archive \
        --table inventory_archive.$table \
        --inserts \
        --rows-per-insert=10000 \
        --data-only \
        --enable-row-security \
        > seeds/hidden/$table.sql
    clean_sql_file seeds/hidden/$table.sql
done;
