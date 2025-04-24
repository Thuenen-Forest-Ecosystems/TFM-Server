clean_sql_file() {
    local file=$1
    # Remove transaction_timeout line and add replication role setting
    sed -i '' '/SET transaction_timeout/d' "$file"
    echo "SET session_replication_role = replica;" | cat - "$file" > temp && mv temp "$file"
}

# DUMP inventory_archive
PGPASSWORD=postgres pg_dump \
    -h 127.0.0.1 \
    -p 54322 \
    -U postgres \
    -d postgres \
    -n inventory_archive \
    --data-only \
    --enable-row-security \
    > tmp/icp_dictionaries.sql
clean_sql_file tmp/icp_dictionaries.sql