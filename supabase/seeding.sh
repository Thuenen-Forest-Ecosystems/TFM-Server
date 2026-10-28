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

PSQL="docker exec -i -u postgres supabase_db_supabase psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -X -v ON_ERROR_STOP=1"

# Only released inventories and no training data go into the seeds.
# - released: plot not in inventory_archive.embargoed_plots(), the function behind the
#   release_gate policies (driven by inventory_archive.interval_release). interval_release
#   is read from THIS database — mirror it from production first.
# - training: cluster.is_training. The release gate lets training clusters through
#   (exempt_training), so they are excluded here explicitly.
# pg_dump cannot filter rows, so the filtered rows are copied into the scratch schema
# seed_export, dumped from there and renamed back to inventory_archive in the INSERTs.
echo "Seed content per interval (local interval_release):"
$PSQL -c "
    SELECT p.interval_name,
           r.published_at,
           count(*) FILTER (WHERE e.plot_id IS NULL AND NOT c.is_training) AS plots_seeded,
           count(e.plot_id) FILTER (WHERE NOT c.is_training)              AS plots_embargoed,
           count(*) FILTER (WHERE c.is_training)                          AS plots_training
    FROM inventory_archive.plot p
    JOIN inventory_archive.cluster c ON c.id = p.cluster_id
    LEFT JOIN inventory_archive.interval_release r ON r.interval_name = p.interval_name
    LEFT JOIN inventory_archive.embargoed_plots() e ON e.plot_id = p.id
    GROUP BY 1, 2 ORDER BY 1" || { echo "release check failed, aborting" >&2; exit 1; }

# WHERE clause selecting the seeded rows of an inventory_archive table (alias t)
seed_filter() {
    local plots="t.plot_id IN (SELECT id FROM seed_export.seed_plot_ids)"
    case "$1" in
        cluster)          echo "NOT t.is_training" ;;
        cluster_move)     echo "t.cluster_id IN (SELECT id FROM inventory_archive.cluster WHERE NOT is_training)" ;;
        plot)             echo "t.id IN (SELECT id FROM seed_export.seed_plot_ids)" ;;
        plot_coordinates) echo "EXISTS (SELECT 1 FROM inventory_archive.plot p JOIN seed_export.seed_plot_ids s ON s.id = p.id
                                        WHERE p.cluster_name = t.cluster_name AND p.plot_name = t.plot_name)" ;;
        tree_coordinates) echo "t.tree_id IN (SELECT x.id FROM inventory_archive.tree x WHERE x.plot_id IN (SELECT id FROM seed_export.seed_plot_ids))" ;;
        edges_coordinates) echo "t.edge_id IN (SELECT x.id FROM inventory_archive.edges x WHERE x.plot_id IN (SELECT id FROM seed_export.seed_plot_ids))" ;;
        subplots_relative_position_coordinates)
                          echo "t.subplots_relative_position_id IN (SELECT x.id FROM inventory_archive.subplots_relative_position x
                                                                   WHERE x.plot_id IN (SELECT id FROM seed_export.seed_plot_ids))" ;;
        *)                echo "$plots" ;;
    esac
}

# dump_filtered <table> <target dir>
dump_filtered() {
    local table=$1 dir=$2
    $PSQL -q -c "CREATE TABLE seed_export.$table AS
                 SELECT t.* FROM inventory_archive.$table t WHERE $(seed_filter $table)" \
        || { echo "filtering $table failed, aborting" >&2; exit 1; }
    docker exec -u postgres supabase_db_supabase pg_dump \
        -h 127.0.0.1 \
        -p 5432 \
        -U postgres \
        -d postgres \
        --table seed_export.$table \
        --inserts \
        --data-only \
        | sed "s/^INSERT INTO seed_export\./INSERT INTO inventory_archive./" \
        > $dir/$table.sql
    clean_sql_file $dir/$table.sql
    echo "$table: $(grep -c '^INSERT' $dir/$table.sql) rows"
}

$PSQL -q -c "DROP SCHEMA IF EXISTS seed_export CASCADE; CREATE SCHEMA seed_export;
             CREATE TABLE seed_export.seed_plot_ids AS
             SELECT p.id FROM inventory_archive.plot p
             JOIN inventory_archive.cluster c ON c.id = p.cluster_id
             WHERE NOT c.is_training
               AND p.id NOT IN (SELECT plot_id FROM inventory_archive.embargoed_plots());
             CREATE UNIQUE INDEX ON seed_export.seed_plot_ids (id);" \
    || { echo "creating seed_export failed, aborting" >&2; exit 1; }
trap '$PSQL -q -c "DROP SCHEMA IF EXISTS seed_export CASCADE"' EXIT

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
    do dump_filtered $table seeds/public
done;

for table in plot_coordinates notes position tree_coordinates edges_coordinates subplots_relative_position_coordinates plot_support_points
    do dump_filtered $table seeds/intern
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