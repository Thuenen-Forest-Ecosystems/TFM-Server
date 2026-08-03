#!/bin/bash

# ============================================================================
# Runner for test_records_writability_matrix.sql (DRY RUN — always ROLLBACK)
#
#   ./run_writability_matrix.sh            -> local supabase stack (54322)
#   ./run_writability_matrix.sh --remote   -> remote server (creds from ../../.env)
# ============================================================================

set -euo pipefail
cd "$(dirname "$0")"

SQL_FILE="test_records_writability_matrix.sql"

if [[ "${1:-}" == "--remote" ]]; then
    # Same convention as supabase/test.sh: credentials from TFM-Server/.env
    set -a && source ../../.env && set +a
    HOST="${REMOTE_HOST:-134.110.100.75}"
    PORT="${REMOTE_PORT:-3389}"
    USER="${REMOTE_USER:-postgres}"
    DB="${POSTGRES_DB:?POSTGRES_DB not set in ../../.env}"
    export PGPASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD not set in ../../.env}"

    echo "Records writability matrix — DRY RUN (single transaction, always rolled back)"
    echo "Target: REMOTE  $USER@$HOST:$PORT/$DB"
    echo ""
    psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" \
         --no-psqlrc --set ON_ERROR_STOP=on \
         -f "$SQL_FILE"
else
    # Local self-hosted stack: run psql inside the db container (no password needed)
    DB_CONTAINER="${DB_CONTAINER:-sync-server-db}"

    echo "Records writability matrix — DRY RUN (single transaction, always rolled back)"
    echo "Target: LOCAL  docker exec $DB_CONTAINER (postgres/postgres)"
    echo ""
    docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres \
         --no-psqlrc --set ON_ERROR_STOP=on \
         -f - < "$SQL_FILE"
fi
