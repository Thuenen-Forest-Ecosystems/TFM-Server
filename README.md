# TFM Server

## Requirements
Make sure you have the following installed:
- [Docker](https://docs.docker.com/engine/install/)
- [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started)

## Clone Repository
```bash
git clone --recurse-submodules -j8 https://github.com/Thuenen-Forest-Ecosystems/TFM-Server.git
cd TFM-Server
cp .env.example .env
```

## Local development

##Requirements
- window in virtueller umgebung (wsl)
- nvm installieren
- Docker Berechtigungen
- 

### Start Supabase and Powersync
```bash
supabase start
```

### Stop Supabase and Powersync
```bash
supabase stop
```

### Start Powersync
```bash
docker compose --env-file .env.local -f docker-compose.local.yaml up 
```

### Stop Powersync
```bash
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
