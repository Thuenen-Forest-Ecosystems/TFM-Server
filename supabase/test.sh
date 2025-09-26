#!/bin/bash

# PGPASSWORD=your_password pg_dump -h 134.110.100.75 -p 3389 -U postgres -d $POSTGRES_DB > remote_dump.sql

# Exit immediately if a command exits with a non-zero status.
set -e

# Load environment variables from .env file
set -a && source ../.env && set +a

# Remote database connection details
REMOTE_HOST="134.110.100.75"
REMOTE_PORT="3389"
REMOTE_USER="postgres"
REMOTE_DB="$POSTGRES_DB"
REMOTE_PASSWORD="$POSTGRES_PASSWORD"

# Directory to store the dumps
DUMP_DIR="tmp"
mkdir -p "$DUMP_DIR"

# File paths for dumps
SCHEMA_DUMP_FILE="$DUMP_DIR/public_schema.sql"
DATA_DUMP_FILE="$DUMP_DIR/public_data.sql"

echo "Starting dump from remote server..."

# Export password for pg_dump to use
export PGPASSWORD=$REMOTE_PASSWORD

# Dump the public schema (schema-only)
echo "Dumping public schema structure to $SCHEMA_DUMP_FILE..."
pg_dump \
    -h "$REMOTE_HOST" \
    -p "$REMOTE_PORT" \
    -U "$REMOTE_USER" \
    -d "$REMOTE_DB" \
    -n public \
    --schema-only \
    > "$SCHEMA_DUMP_FILE"

echo "Schema dump complete."

# Dump the public schema data (data-only)
echo "Dumping public schema data to $DATA_DUMP_FILE..."
pg_dump \
    -h "$REMOTE_HOST" \
    -p "$REMOTE_PORT" \
    -U "$REMOTE_USER" \
    -d "$REMOTE_DB" \
    -n public \
    --data-only \
    > "$DATA_DUMP_FILE"

echo "Data dump complete."

# Unset the password variable for security
unset PGPASSWORD

echo "Successfully created dumps for the public schema in '$DUMP_DIR/'."