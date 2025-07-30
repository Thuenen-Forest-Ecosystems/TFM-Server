#! /bin/bash

#set -e  # Exit on error
set -a && source ../.env && set +a

# psql all .sql files in directory
for file in seeds/public/*.sql; do
    psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/postgres" -f $file
done;

for file in hidden/public/*.sql; do
    psql "postgres://postgres:$POSTGRES_PASSWORD@134.110.100.75:3389/postgres" -f $file
done;