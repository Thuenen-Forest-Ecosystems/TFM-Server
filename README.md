# TFM Server

## Local development
```bash
supabase start
docker compose --env-file .env.local -f docker-compose.local.yaml start 
```

## Start Server

```bash
docker compose start
```

supabase db reset

supabase db pull --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres

supabase db push --include-all --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres

supabase db reset
supabase db reset --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres

supabase migration repair --status applied applied --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres


supabase migration fetch --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres

supabase migration up --include-all --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres


----
supabase db diff -f test

supabase db push --include-all --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres


----
# Seeding Project
## Data
supabase db dump --local -f supabase/seeds/schema.sql --data-only -s private_ci2027_001

## Roles
supabase db dump --local -f supabase/seeds/roles.sql --role-only

supabase db push --include-all --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres