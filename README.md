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

### For Thünen Employees
If you are a Thünen employee, you can add the Thünen GitLab repository as a remote:
```bash
git submodule add https://gitlab.thuenen.de/Thuenen-Forest-Ecosystems/TFM-Server.git
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