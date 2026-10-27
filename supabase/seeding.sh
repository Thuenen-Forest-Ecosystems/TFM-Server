#! /bin/bash

# run seed-to-temp.sh first
./seed-to-temp.sh

# Set the chunk size (e.g., 50MB = 50000000 bytes)
CHUNK_SIZE=50000

#set -e  # Exit on error
set -a && source ../.env.local && set +a

# Create directories if they don't exist
mkdir -p seeds/public seeds/intern

# Function to add replication role and remove transaction_timeout
clean_sql_file() {
    local file=$1
    # Remove transaction_timeout line and add replication role setting
    sed -i '' '/SET transaction_timeout/d' "$file"
    echo "SET session_replication_role = replica;" | cat - "$file" > temp && mv temp "$file"
}

# Function to add ON CONFLICT clause to INSERT INTO statements
add_on_conflict_clause() {
    local file=$1
    local conflict_column=${2:-"code"}  # Default to 'code', but allow override

    # Use awk to process INSERT statements and add ON CONFLICT clause
    # This approach correctly identifies INSERT statement blocks and only modifies their ending semicolons
    awk -v conflict_col="$conflict_column" '
    /^INSERT INTO.*VALUES/ { in_insert = 1 }
    in_insert && /;[[:space:]]*$/ { 
        gsub(/;[[:space:]]*$/, " ON CONFLICT (" conflict_col ") DO NOTHING;")
        in_insert = 0
    }
    { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# Only released inventories go into the seeds: the inventory_archive tables are
# dumped as role "authenticated", so the RESTRICTIVE release_gate policies
# (embargoed_plots() & co., driven by inventory_archive.interval_release) filter
# the rows exactly as they do for logged-in non-admin users.
# interval_release is read from THIS database — sync it from production first.
echo "Release state used for this seed (local interval_release):"
docker exec -u postgres supabase_db_supabase psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -X -c "
    SELECT p.interval_name,
           r.published_at,
           count(*) FILTER (WHERE e.plot_id IS NULL) AS plots_seeded,
           count(e.plot_id)                          AS plots_embargoed
    FROM inventory_archive.plot p
    LEFT JOIN inventory_archive.interval_release r ON r.interval_name = p.interval_name
    LEFT JOIN inventory_archive.embargoed_plots() e ON e.plot_id = p.id
    GROUP BY 1, 2 ORDER BY 1" || { echo "release check failed, aborting" >&2; exit 1; }

# Remove all sql files in folder
rm -f seeds/public/*.sql
rm -f seeds/intern/*.sql

# Dump lookup schema
# Add "ON CONFLICT (code) DO NOTHING" to every insert in lookup.sql
docker exec -u postgres supabase_db_supabase pg_dump \
    -h 127.0.0.1 \
    -p 5432 \
    -U postgres \
    -d postgres \
    -n lookup \
    --inserts \
    --data-only \
    --rows-per-insert=10000 \
    --enable-row-security \
    > seeds/public/lookup.sql
clean_sql_file seeds/public/lookup.sql
# Modify the lookup.sql file to include "ON CONFLICT (code) DO NOTHING"
add_on_conflict_clause seeds/public/lookup.sql "code"




for table in cluster cluster_move plot deadwood edges regeneration structure_lt4m structure_gt4m tree subplots_relative_position
    do docker exec -u postgres supabase_db_supabase pg_dump \
        -h 127.0.0.1 \
        -p 5432 \
        -U postgres \
        -d postgres \
        -n inventory_archive \
        --role=authenticated \
        --table inventory_archive.$table \
        --inserts \
        --data-only \
        --enable-row-security \
        > seeds/public/$table.sql
    clean_sql_file seeds/public/$table.sql

done;

for table in plot_coordinates notes position tree_coordinates edges_coordinates subplots_relative_position_coordinates plot_support_points
    do docker exec -u postgres supabase_db_supabase pg_dump \
        -h 127.0.0.1 \
        -p 5432 \
        -U postgres \
        -d postgres \
        -n inventory_archive \
        --role=authenticated \
        --table inventory_archive.$table \
        --inserts \
        --data-only \
        --enable-row-security \
        > seeds/intern/$table.sql
    clean_sql_file seeds/intern/$table.sql

done;


# split into smaller files
split -l $CHUNK_SIZE seeds/public/plot.sql seeds/public/plot_part_
# Add necessary PostgreSQL headers to each chunk
for file in seeds/public/plot_part_*; do
    clean_sql_file $file
    # Add ON CONFLICT clause to plot chunks
    #add_on_conflict_clause_pk $file
    mv "$file" "$file.sql"
done;
# remove base file
rm seeds/public/plot.sql


# split into smaller files
split -l $CHUNK_SIZE seeds/public/tree.sql seeds/public/tree_part_
# Add necessary PostgreSQL headers to each chunk
for file in seeds/public/tree_part_*; do
    clean_sql_file $file
    # Add ON CONFLICT clause to tree chunks
    #add_on_conflict_clause_pk $file
    mv "$file" "$file.sql"
done;
# remove base file
rm seeds/public/tree.sql