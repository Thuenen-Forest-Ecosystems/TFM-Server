# TFM Server

## Local development
```bash
supabase start
docker compose --env-file .env.local -f docker-compose.local.yaml up 
```

## Start Server

```bash
docker compose start
```


## Make Changes
```bash
supabase db diff -f [migration-file-name]
```



## Pull from production
```bash
supabase db pull --db-url postgres://[user]:[password]@[host]:[port]/[database]
```

## Push to production
```bash
supabase db push --include-all --db-url postgres://[user]:[password]@[host]:[port]/[database]
supabase db push --include-all --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres
```

## Repair migrations
```bash
supabase migration repair --status reverted 20241220150942 --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres
supabase migration repair --status reverted 20241220154421 --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres
supabase migration repair --status reverted 20241220160729 --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres

supabase migration repair --status applied 20250106132702 --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres
supabase migration repair --status applied 20250107083526 --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres
supabase migration repair --status applied 20250107101118 --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres
supabase migration repair --status applied 20350107083527 --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres
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

supabase db dump --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres -f tmp/seed.sql --data-only

supabase db push --include-all --db-url postgres://postgres:your-super-secret-and-long-postgres-password@134.110.100.75:3389/postgres