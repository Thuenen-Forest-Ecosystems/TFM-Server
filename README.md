# TFM Server

## Requirements
Make sure you have the following installed:
- [Git](https://git-scm.com/downloads)
- [Docker](https://docs.docker.com/engine/install/)
- [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started)

## Clone Repository

```bash
git clone --recurse-submodules -j8 https://github.com/Thuenen-Forest-Ecosystems/TFM-Server.git
cd TFM-Server
cp .env.example .env
```

### Thünen internal seeds repository

For ***Thünen employees only*** with access to *DMZ*, you can clone the internal seeds repository:

```bash
git submodule add -f https://git-dmz.thuenen.de/tfm-seeds/intern.git supabase/seeds/intern
```

## Local development

### Start Supabase and Powersync
```bash
supabase start
```

### Stop Supabase and Powersync
```bash
supabase stop
```

## Sync Service

### Start Powersync
```bash
docker compose --env-file .env.local -f docker-compose.local.yaml up 
```

### Stop Powersync
```bash
docker compose --env-file .env.local -f docker-compose.local.yaml down 
```

## Remote Server

```bash
docker compose start
```