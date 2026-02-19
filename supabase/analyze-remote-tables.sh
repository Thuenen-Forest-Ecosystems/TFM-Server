#!/bin/bash

set -a && source ../.env && set +a

REMOTE_DB="postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/$POSTGRES_DB"

echo "=== Analyzing remote database table sizes ==="
echo ""

# Get table sizes from remote
psql "$REMOTE_DB" -c "
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    pg_total_relation_size(schemaname||'.'||tablename) AS bytes
FROM pg_tables 
WHERE schemaname IN ('public', 'auth')
    AND tablename NOT LIKE '_%'
    AND tablename NOT LIKE 'storage_%'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;
"

echo ""
echo "=== To exclude large tables from sync, use: ==="
echo "./remote-to-local-sync-selective.sh --exclude-table='public.large_table_name'"
