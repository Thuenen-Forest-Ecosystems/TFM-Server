# TFM Server

## Local development

### Start Supabase and Powersync
```bash
supabase start
docker compose --env-file .env.local -f docker-compose.local.yaml up 
```

### Stop Supabase and Powersync
```bash
supabase stop
docker compose --env-file .env.local -f docker-compose.local.yaml down 
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
```