#!/bin/bash

# ============================================================================
# Runner for test_inventory_archive_release_gate.sql (DRY RUN — always ROLLBACK)
#
#   ./run_release_gate.sh            -> local supabase stack
#   ./run_release_gate.sh --remote   -> remote server (creds from ../../.env)
#
# Container of the local stack via DB_CONTAINER (default: sync-server-db).
# ============================================================================

set -euo pipefail
cd "$(dirname "$0")"

SQL_FILE="test_inventory_archive_release_gate.sql"

if [[ "${1:-}" == "--remote" ]]; then
    set -a && source ../../.env && set +a
    HOST="${REMOTE_HOST:-134.110.100.75}"
    PORT="${REMOTE_PORT:-3389}"
    USER="${REMOTE_USER:-postgres}"
    DB="${POSTGRES_DB:?POSTGRES_DB not set in ../../.env}"
    export PGPASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD not set in ../../.env}"

    echo "Archivfreigabe / Sichtbarkeitsmatrix — DRY RUN (eine Transaktion, immer ROLLBACK)"
    echo "Ziel: REMOTE  $USER@$HOST:$PORT/$DB"
    echo ""
    psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" \
         --no-psqlrc --set ON_ERROR_STOP=on \
         -f "$SQL_FILE"
else
    DB_CONTAINER="${DB_CONTAINER:-sync-server-db}"

    echo "Archivfreigabe / Sichtbarkeitsmatrix — DRY RUN (eine Transaktion, immer ROLLBACK)"
    echo "Ziel: LOCAL  docker exec $DB_CONTAINER (postgres/postgres)"
    echo ""
    docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres \
         --no-psqlrc --set ON_ERROR_STOP=on \
         -f - < "$SQL_FILE"
fi
