# Deploying TFM-Server on Linux (Production)

This guide describes a full production deployment of
[TFM-Server](https://github.com/Thuenen-Forest-Ecosystems/TFM-Server) on a Linux host:
self-hosted Supabase + PowerSync via Docker Compose, followed by the initial database
setup from the SQL **migrations** and **seeds** shipped in the `supabase/` folder.

::: warning
The database is **not** initialised automatically. Docker Compose only starts an empty
Postgres. Migrations and seeds must be applied manually once, in the order described in
[Initialise the database](#_5-initialise-the-database).
:::

## 1. Architecture

A single `docker compose up` starts the whole stack. All Supabase containers share the
`supabase-net` bridge network; PowerSync is attached to both `supabase-net` and its own
default network (where MongoDB lives).

| Service           | Container                    | Image / build                    | Purpose                                          |
| ----------------- | ---------------------------- | -------------------------------- | ------------------------------------------------ |
| `db`              | `supabase-db`                | `supabase/postgres:15.6.1.146`   | Postgres (PostGIS, logical replication)          |
| `kong`            | `supabase-kong`              | `kong:2.8.1`                     | API gateway — single public entry point          |
| `auth`            | `supabase-auth`              | built from `Dockerfile.auth`     | GoTrue authentication                            |
| `rest`            | `supabase-rest`              | `postgrest/postgrest:v12.2.0`    | REST API (`/rest/v1`)                            |
| `realtime`        | `realtime-dev.supabase-realtime` | `supabase/realtime:v2.33.70` | Realtime channels                                |
| `storage`         | `supabase-storage`           | `supabase/storage-api:v1.11.13`  | File storage                                     |
| `imgproxy`        | `supabase-imgproxy`          | `darthsim/imgproxy:v3.8.0`       | Image transformations                            |
| `meta`            | `supabase-meta`              | `supabase/postgres-meta:v0.84.2` | Schema introspection for Studio                  |
| `functions`       | `supabase-edge-functions`    | `supabase/edge-runtime:v1.65.3`  | Edge functions from `volumes/functions`          |
| `studio`          | `supabase-studio`            | `supabase/studio:2025.06.30-…`   | Admin dashboard — **do not expose publicly**     |
| `powersync`       | —                            | `journeyapps/powersync-service:latest` | Sync service for the TFM app               |
| `mongo`           | —                            | `mongo:7.0`                      | PowerSync bucket storage (replica set `rs0`)     |
| `mongo-rs-init`   | —                            | `mongo:7.0`                      | One-shot replica-set initialisation              |

### Published ports

| Port                | Service    | Exposure                                                    |
| ------------------- | ---------- | ----------------------------------------------------------- |
| `${KONG_HTTP_PORT}` (8000) | Kong | Behind the reverse proxy — the only port that needs the public internet |
| `${KONG_HTTPS_PORT}` (8443) | Kong | Optional, if Kong terminates TLS itself                   |
| `${PS_PORT}` (8181) | PowerSync  | Behind the reverse proxy (`/sync/`)                          |
| `${POSTGRES_PORT}`  | Postgres   | Firewall to admin/VPN networks only                          |
| `${STUDIO_PORT}`    | Studio     | Localhost / VPN only                                         |
| `27017`             | MongoDB    | **Must not be reachable from outside the host**              |

On the Thünen production host the stack is published as `https://ci.thuenen.de`, with the
reverse proxy routing `/rest/v1`, `/auth/v1`, `/storage/v1`, `/functions/v1` to Kong
(`8000`) and `/sync/` to PowerSync (`8181`).

## 2. Host requirements

- Linux with **Docker Engine** and the **Compose plugin ≥ 2.20.3** (the compose file uses
  the `include:` syntax).
- `git`, and a Postgres 15 client (`psql`, `pg_dump`) on the host or via
  `docker exec supabase-db psql`.
- Optional but recommended: the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started)
  for applying migrations.
- **RAM:** MongoDB alone reserves 4 GB and is limited to 7 GB
  (`--wiredTigerCacheSizeGB 5`); PowerSync is capped at ~1 GB heap
  (`NODE_OPTIONS=--max-old-space-size=1000`). Plan for **≥ 16 GB**.
- **Disk:** the seed data is large — roughly 1.3 GB (`seeds/public`) plus 1.8 GB
  (`seeds/intern`) of SQL, and a loaded `volumes/db/data` grows to several GB. Plan for
  **≥ 100 GB** including backups.
- Postgres runs with `shm_size: 1g`, `wal_level=logical`, `max_connections=500` — these
  are already set in the compose file, no host tuning required.

## 3. Clone the repository

```bash
git clone --recurse-submodules -j8 \
  https://github.com/Thuenen-Forest-Ecosystems/TFM-Server.git
cd TFM-Server
cp .env.example .env
```

The submodules provide the deployable content:

| Submodule            | Contents                                        |
| -------------------- | ----------------------------------------------- |
| `supabase/seeds/public` | Public seed data (lookup + inventory archive) |
| `supabase/functions`    | Edge function sources                         |
| `volumes/functions`     | Edge functions mounted into the edge runtime  |

Verify they are populated:

```bash
git submodule status
ls supabase/seeds/public | head
```

### Internal seed data (Thünen only)

The non-public seeds (coordinates, notes, positions) are **not** a submodule — they are
cloned separately from the DMZ GitLab and are only accessible to Thünen employees:

```bash
git clone https://git-dmz.thuenen.de/tfm-seeds/intern.git supabase/seeds/intern
```

::: tip
`.gitmodules` still lists a legacy `supabase/seeds/hidden` entry. The path actually used
by `supabase/config.toml` is `supabase/seeds/intern`; the `hidden` submodule can stay
uninitialised.
:::

## 4. Configure `.env`

Compose reads `.env` from the project root automatically. Everything in the "Secrets"
block of `.env.example` **must** be replaced before going live.

### Secrets

```bash
# 32+ character random values
openssl rand -base64 48   # POSTGRES_PASSWORD
openssl rand -base64 48   # JWT_SECRET
```

`ANON_KEY` and `SERVICE_ROLE_KEY` are JWTs signed with `JWT_SECRET` and carrying
`{"role": "anon"}` / `{"role": "service_role"}`. Generate them with the
[Supabase JWT generator](https://supabase.com/docs/guides/self-hosting/docker#securing-your-services)
after choosing `JWT_SECRET` — **never keep the demo keys from `.env.example`**, they are
publicly known.

Also change `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` (Kong basic auth in front of
Studio) and `WEBHOOK_TOKEN`.

### Database and API

```bash
POSTGRES_USER=postgres
POSTGRES_HOST=supabase-db          # container name on supabase-net
POSTGRES_DB=postgres
POSTGRES_PORT=5432                 # container *and* host port — see note below

PGRST_DB_SCHEMAS=inventory_archive,derived,lookup,inventory,public,storage,graphql_public
PGRST_OPENAPI_SERVER_PROXY_URI=https://<your-domain>/rest/v1
```

::: warning `POSTGRES_PORT` is used twice
The compose file maps `${POSTGRES_PORT}:${POSTGRES_PORT}` and passes `PGPORT` into the
container, so Postgres *listens* on that port inside the container as well. Changing it to
a non-default value (production uses `3389`) shifts both sides — use the same value in
every connection string, including `PS_DATA_SOURCE_URI`.
:::

### Public URLs

```bash
SITE_URL=https://<your-domain>
API_EXTERNAL_URL=https://<your-domain>
SUPABASE_PUBLIC_URL=https://<your-domain>
ADDITIONAL_REDIRECT_URLS=<app deep links, comma separated>
DISABLE_SIGNUP=true                # users are invited, not self-registered
ENABLE_EMAIL_AUTOCONFIRM=false
FUNCTIONS_VERIFY_JWT=false
```

### Mail

Production uses the internal relay:

```bash
SMTP_HOST=relay-dmz.ux.thuenen.de
SMTP_PORT=25
SMTP_ADMIN_EMAIL=<sender address>
SMTP_SENDER_NAME=<sender name>
GOTRUE_MAILER_EXTERNAL_HOSTS=<allowed hosts>
```

If the relay presents a certificate from an internal CA, build GoTrue **with** the CA
bundle: put `HARICA-GEANT-TLS-R1.crt` and `HARICA-TLS-Root-2021-RSA.crt` into
`volumes/auth/certs/` and set:

```bash
INSTALL_CERTS=true
```

`Dockerfile.auth` then copies them into the image and runs `update-ca-certificates`.
Rebuild after changing this flag: `docker compose build auth`.

### PowerSync

```bash
PS_PORT=8181
PS_DATA_SOURCE_URI=postgres://${POSTGRES_USER}:<password>@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}
PS_MONGO_URI=mongodb://mongo:27017/powersync?replicaSet=rs0&connectTimeoutMS=30000&socketTimeoutMS=60000&serverSelectionTimeoutMS=30000&maxPoolSize=10&minPoolSize=2
PS_SUPABASE_JWT_SECRET=${JWT_SECRET}
PS_JWKS_URL=http://kong:8000/auth/v1/.well-known/jwks.json
```

PowerSync authenticates clients against Supabase JWTs (`client_auth.supabase: true` in
[`config/powersync.yaml`](https://github.com/Thuenen-Forest-Ecosystems/TFM-Server/blob/main/config/powersync.yaml)),
so `PS_SUPABASE_JWT_SECRET` must match `JWT_SECRET` exactly.

::: warning
`config/powersync.yaml` sets `sslmode: disable` for the replication connection. This is
only acceptable because PowerSync reaches Postgres over the internal Docker network. Never
point `PS_DATA_SOURCE_URI` at a database outside the host without enabling TLS.
:::

### Validate `.env` before starting anything

```bash
docker compose config -q && echo "compose file resolves"
```

Compose interpolates and validates the **whole** file up front, regardless of which
services you later select. A single missing variable therefore aborts the command before
any container starts — an empty `PS_PORT`, for example, reduces `${PS_PORT}:${PS_PORT}` to
`:` and fails with `no port specified: :<empty>`.

::: warning
`.env.example` has historically lagged behind `docker-compose.yaml`. Run the check above
after copying it; if it reports unresolved variables, add them to `.env` rather than
guessing at runtime. Unset variables are only *warnings* until one of them is used in a
`ports:` entry — then they are fatal.
:::

## 5. Initialise the database

::: tip
The whole of sections 5 and 6 is automated in `scripts/deploy.sh` (see 6.2). The manual
steps below document what that script does and why the order matters — read them once,
then use the script.
:::

### 5.1 Start Postgres and auth

```bash
docker compose up -d db
docker compose logs -f db      # wait for "database system is ready to accept connections"
```

On the very first start the init scripts in `volumes/db/` (`roles.sql`, `jwt.sql`,
`webhooks.sql`, `realtime.sql`, `logs.sql`, `pooler.sql`, `_supabase.sql`) run
automatically and create the Supabase roles and internal schemas. They run **only** when
`volumes/db/data` is empty.

Then start **auth** and wait for it to become healthy:

```bash
docker compose up -d auth
docker compose ps auth         # wait for "healthy"
```

::: warning Auth must migrate before the application migrations
GoTrue owns the `auth` schema and adds its columns through its own migrations when the
container starts. The application migrations depend on them — `20250115140818_public.sql`
creates a trigger `AFTER UPDATE OF email_confirmed_at ON auth.users`, and twelve
migrations in total reference the `auth` schema. Applying them against a database where
only `db` has ever run fails with:

```text
ERROR: column old.email_confirmed_at does not exist
```

This never shows up in local development, because `supabase start` brings GoTrue up before
applying anything.
:::

Verify the precondition before continuing:

```bash
docker compose exec -T db psql -U postgres -d postgres -tAc \
  "select count(*) from information_schema.columns
   where table_schema='auth' and table_name='users' and column_name='email_confirmed_at';"
# must print 1
```

Define a connection string for the following steps:

```bash
export DB_URL="postgres://postgres:<POSTGRES_PASSWORD>@127.0.0.1:${POSTGRES_PORT}/postgres"
psql "$DB_URL" -c 'select version();'
```

### 5.2 Apply the migrations

All 45 migrations live in `supabase/migrations/` and are named
`<timestamp>_<name>.sql`. They build the whole application schema: extensions
(PostGIS, `http`, `pg_jsonschema`, `moddatetime`), the `lookup`, `inventory_archive`,
`public` and `derived` schemas, roles, RLS policies, triggers, guards and views.

**Recommended — Supabase CLI** (tracks applied migrations in
`supabase_migrations.schema_migrations`, so later deployments only apply the delta):

```bash
supabase db push --db-url "${DB_URL}?sslmode=disable"
```

::: warning `sslmode=disable` and percent-encoding
Nothing in this stack terminates TLS at Postgres, and the CLI requires SSL by default —
without `sslmode=disable` it aborts with *"The server does not support SSL connections"*.
Because the credentials then cross the wire in clear, run the CLI **on the server against
`127.0.0.1`**, or tunnel the port over SSH. Never point it at a public database port.

The password must also be percent-encoded in the URL if it contains `@ : / ? #` —
`openssl rand -base64` output regularly does.
:::

**Alternative — plain `psql`** (no CLI needed; you are responsible for not re-running
files):

```bash
for f in supabase/migrations/*.sql; do
  echo "→ $f"
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$f" || break
done
```

The glob expands in lexicographic order, which equals chronological order because of the
timestamp prefix — do not reorder the files. Migrations must run **before** any seed,
because the seeds are data-only `INSERT` statements.

Sanity check:

```bash
psql "$DB_URL" -c "\dn"                                  # lookup, inventory_archive, derived, public …
psql "$DB_URL" -c "select count(*) from information_schema.tables
                   where table_schema = 'inventory_archive';"
```

### 5.3 Load the seed data

::: danger Seeds are always a manual step
`supabase db push` applies **migrations only** — it ignores `[db.seed]` entirely. The
`sql_paths` list below is honoured just by `supabase db reset` and `supabase start`, and
both of those **drop and recreate the database**. Never run either against a production
server. On a self-hosted instance the seed load is the separate, explicit step described
here.
:::

`supabase/config.toml` defines the canonical order:

```toml
[db.seed]
sql_paths = ['./seeds/public/*.sql', './seeds/intern/*.sql']
```

::: tip No `psql` on the host?
Every `psql "$DB_URL" … -f file.sql` below can be run with the client inside the database
container instead — pipe the file in on stdin, because the container cannot see the
repository path:

```bash
docker compose exec -T db psql -U postgres -d postgres \
    --no-psqlrc -q -v ON_ERROR_STOP=1 -f - < path/to/file.sql
```

Installing `postgresql-client` on the server is still worthwhile: `pg_dump` is required for
the backup procedure in section 10.
:::

Load public seeds first, then the internal ones:

```bash
cd supabase

for f in seeds/public/*.sql; do
  echo "→ $f"
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$f" || break
done

for f in seeds/intern/*.sql; do
  echo "→ $f"
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$f" || break
done
```

What the files contain:

- `seeds/public/lookup.sql` — the complete `lookup` schema data. Its inserts carry
  `ON CONFLICT (code) DO NOTHING`, so it is safe to re-run.
- `seeds/public/{cluster,cluster_move,deadwood,edges,regeneration,structure_lt4m,structure_gt4m,subplots_relative_position}.sql`
  — `inventory_archive` tables of past inventories.
- `seeds/public/plot_part_a*.sql` (and `tree_part_*.sql`, when present in the seeds
  repository) — the `plot` and `tree` tables split into chunks of 50 000 lines because a
  single dump would be too large. Load **all** chunks; the alphabetical order of the
  suffixes is the original row order.
- `seeds/intern/*.sql` — coordinates, notes and positions (`plot_coordinates`,
  `tree_coordinates`, `edges_coordinates`, `subplots_relative_position_coordinates`,
  `position`, `notes`). Only available with DMZ access; skip if you deploy a public-data
  instance.

Every seed file starts with `SET session_replication_role = replica;`, which disables
triggers and FK checks for that session — this is intentional and lets the chunked files
load independently of each other's order.

::: tip Loading takes a while
The public seeds alone are >1 GB of `INSERT` statements. Run the loop inside `tmux`/
`screen`, and expect the plot and tree chunks to dominate the runtime.
:::

::: warning Load the seeds before PowerSync runs for the first time
`20250306114617_publications.sql` adds every `lookup` and `inventory_archive` table to the
`powersync` publication. If PowerSync is already replicating, each of the millions of seed
rows is written to WAL, decoded and pushed into MongoDB row by row — slow, and it can grow
the replication slot far beyond `max_slot_wal_keep_size`. Loading first means PowerSync
performs a single snapshot-based initial replication when it starts.

`SET session_replication_role = replica` at the top of each seed file disables *triggers*
only; it does not stop logical decoding.

If you must seed an instance where PowerSync already runs, stop it for the duration:
`docker compose stop powersync`.
:::

::: warning Only `lookup.sql` is re-runnable
The `inventory_archive` seed files contain plain `INSERT` statements — `seeding.sh` adds
the `ON CONFLICT` clause to `lookup.sql` alone. Loading them into a database that already
holds inventory data produces duplicates or primary-key errors. They are meant for an
empty instance.
:::

Verify:

```bash
psql "$DB_URL" -c "select count(*) from lookup.lookup_cover_percentage;"
psql "$DB_URL" -c "select count(*) from inventory_archive.plot;"
psql "$DB_URL" -c "select count(*) from inventory_archive.tree;"
```

The seeds are produced from a reference database by
[`supabase/seeding.sh`](https://github.com/Thuenen-Forest-Ecosystems/TFM-Server/blob/main/supabase/seeding.sh)
— that script is a *maintenance* tool for regenerating the seed repositories, not part of
a deployment.

## 6. Start the full stack

```bash
docker compose up -d
docker compose ps
```

Startup order is handled by health checks: `mongo` → `mongo-rs-init` → `powersync`, and
`db` → `auth`/`rest`/`storage`. `mongo-rs-init` runs once, initialises the `rs0` replica
set and exits with status 0 — an exited `mongo-rs-init` container is expected.

Check PowerSync picked up its replication slot:

```bash
docker compose logs powersync | tail -50
psql "$DB_URL" -c "select slot_name, active, wal_status from pg_replication_slots;"
```

::: warning Sync rules are not hot-reloaded
`config/sync_rules.yaml` defines which rows each client receives. After editing it you
must restart the service: `docker compose restart powersync`. Changes that alter bucket
definitions cause clients to re-sync their data.
:::

### 6.1 Running without PowerSync

A deployment that only serves the REST/API side — an API-only instance, a staging copy, a
data-analysis host — can leave PowerSync and MongoDB switched off. This saves the ~4–7 GB
of RAM those two containers reserve.

**What still works:** REST (`/rest/v1`), Auth, Storage, Realtime, edge functions, Studio,
and every migration and seed described above. Nothing in `volumes/api/kong.yml` routes to
PowerSync — the sync service is published directly on `${PS_PORT}` — so the gateway needs
no change, only the `/sync/` entry in the reverse proxy becomes obsolete.

**What stops working:** the TFM app's offline synchronisation. The app is sync-first, so
without PowerSync it cannot load or write field data.

Because `mongo` and `mongo-rs-init` are pulled in through `include:` at the top of
`docker-compose.yaml`, a bare `docker compose up -d` starts them too. Name the services
explicitly instead:

```bash
docker compose up -d db kong auth rest realtime storage imgproxy meta functions studio
```

Or scale the three sync containers to zero:

```bash
docker compose up -d --scale powersync=0 --scale mongo=0 --scale mongo-rs-init=0
```

To make it permanent, put the sync services behind a Compose profile — add
`profiles: ["sync"]` to the `powersync` service in `docker-compose.yaml` and to `mongo`
and `mongo-rs-init` in `services/mongo.yaml`. They are then skipped by default and started
with `docker compose --profile sync up -d`.

Notes:

- **The `PS_*` variables must stay defined**, even though PowerSync never starts. Compose
  interpolates and validates the *whole* file before it decides which services to run, so
  an empty `PS_PORT` turns the `ports: - ${PS_PORT}:${PS_PORT}` entry into `:` and the
  command aborts with `no port specified: :<empty>` — without starting anything. Keeping
  the values in `.env` costs nothing: the service is simply not created.
- Leave the database as it is. Migration `20250306114617_publications.sql` creates the
  `powersync` publication, and Postgres keeps `wal_level=logical` — both are harmless
  without a subscriber. **No replication slot exists until PowerSync connects**, so there
  is no WAL retention and no risk of the disk filling up.
- Enabling sync later needs no migration: start `mongo` first, wait for `mongo-rs-init` to
  exit 0, then start `powersync`. It creates its slot and performs one full initial
  replication of the published tables, which takes a while on a fully seeded database.

### 6.2 Automated deployment with `scripts/deploy.sh`

Sections 5 and 6 are scripted in `scripts/deploy.sh`. It performs the same steps in the
same order and encodes the ordering constraints that are easy to get wrong by hand.

```bash
./scripts/deploy.sh                       # migrations + start the stack
./scripts/deploy.sh --seed                # + public seeds (fresh install)
./scripts/deploy.sh --seed --seed-intern  # + internal seeds (DMZ access required)
./scripts/deploy.sh --migrate-only        # structure only, start nothing else
```

| Flag | Effect |
| --- | --- |
| `--seed` | Loads `supabase/seeds/public/*.sql` after the migrations |
| `--seed-intern` | Additionally loads `supabase/seeds/intern/*.sql` |
| `--migrate-only` | Applies the structure and exits without starting other services |
| `--no-migrate` | Skips the migration step (data-only run) |
| `--force-seed` | Loads bulk seeds even when the target already holds inventory data |
| `--yes` | Skips the interactive confirmation before a bulk load |

What it does, in order:

1. Loads `.env` and verifies the compose file resolves (`docker compose config -q`).
2. Starts `db`, waits for Postgres, then starts `auth` and waits until
   `auth.users.email_confirmed_at` exists — the precondition described in 5.1.
3. Applies the migrations with `supabase db push` when the CLI is installed, so the
   history is tracked and later runs apply only the delta. Without the CLI it falls back
   to the `psql` loop and warns that the fallback records no history and cannot be
   re-run.
4. With `--seed`: stops PowerSync if it is running, loads the seed files, restarts it.
5. Starts the remaining services and prints a verification summary (schemas, row counts,
   replication slot).

::: tip Re-running is safe by default
Without `--seed` the script only reconciles structure and services, which is what a normal
release deployment needs. If `inventory_archive.plot` already contains rows, `--seed`
loads just `lookup.sql` — the one idempotent seed file — and skips the bulk files instead
of duplicating them. `--force-seed` overrides that guard.
:::

::: warning What it deliberately does not do
It never truncates, drops or resets anything. Recovering from a partially loaded seed set
requires a truncate-and-reload, which destroys data and is left as a manual decision. It
also does not record *which version* of the seed data was loaded — migration history is
tracked by the Supabase CLI, but the bulk data has no equivalent ledger.
:::

## 7. Reverse proxy and TLS

Terminate TLS in front of Kong (nginx, Apache or Traefik on the host) and forward:

| Public path                                                                | Upstream                     |
| -------------------------------------------------------------------------- | ---------------------------- |
| `/rest/v1/`, `/auth/v1/`, `/storage/v1/`, `/functions/v1/`, `/graphql/v1/` | `127.0.0.1:8000` (Kong)      |
| `/sync/`                                                                   | `127.0.0.1:8181` (PowerSync) |

Omit the `/sync/` route entirely on a deployment that runs without PowerSync (see 6.1).

Rules:

- WebSocket upgrade headers must be forwarded for `/sync/` and for Realtime.
- Do **not** publish Studio (`${STUDIO_PORT}`), MongoDB (`27017`) or Postgres
  (`${POSTGRES_PORT}`) to the internet. Restrict them with the host firewall to
  admin/VPN networks.
- Keep `SUPABASE_PUBLIC_URL`, `API_EXTERNAL_URL` and `SITE_URL` identical to the public
  HTTPS origin, otherwise auth redirects and the OpenAPI spec point to the wrong host.

## 8. Edge functions

Edge functions are served from the `volumes/functions` submodule, mounted read-only into
the edge runtime (`/home/deno/functions`), with `main` as the entry service. Deployed
functions include `health`, `invite-user`, `validate-record`, `validation` and
`update-edge-functions`.

Deploying a new version = updating the submodule and restarting the container. On the
server, the repository ships the pattern as `deploy.sh` in the repository root — a
separate, much smaller script than `scripts/deploy.sh` from 6.2, and concerned only with
edge functions:

```bash
#!/bin/bash
cd volumes/functions
git pull origin main
docker compose restart functions
echo "Deployment completed at $(date)"
```

Optionally, `hook/pull.js` runs a small webhook listener (port `9000`) that pulls the
repository when GitLab posts a push event with the correct `x-gitlab-token`
(`WEBHOOK_KEY` from `.env`). Restrict that port to the GitLab runner's address if you use
it.

## 9. Verification checklist

```bash
# Gateway + REST reachable
curl -sS https://<your-domain>/rest/v1/ -H "apikey: $ANON_KEY" | head

# Auth
curl -sS https://<your-domain>/auth/v1/health

# Edge functions
curl -sS https://<your-domain>/functions/v1/health

# PowerSync
curl -sS http://127.0.0.1:8181/probes/liveness

# Containers healthy, mongo-rs-init exited 0
docker compose ps
```

A public health overview is also published at
[Health Check](https://thuenen-forest-ecosystems.github.io/TFM-Documentation/health-check).

## 10. Operations

### Updating the server

```bash
git pull
git submodule update --init --recursive
supabase db push --db-url "$DB_URL"    # apply new migrations
docker compose pull
docker compose up -d
```

Always apply new migrations **before** restarting the services that depend on the changed
schema, and check whether the release also changes `config/sync_rules.yaml`
(→ restart `powersync`).

### Backups

- **Logical:** `pg_dump "$DB_URL" -Fc -f tfm-$(date +%F).dump` — the only backup that is
  safe to take while the stack runs.
- **Physical:** stopping the stack and archiving `volumes/db/data` is possible but must
  never be done on a running database.
- Also back up `.env` (it holds the JWT secret — without it every issued token and the
  storage keys become unusable) and, if in use, `volumes/storage`.

### Logs

```bash
docker compose logs -f --tail=100 <service>
```

### Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Init scripts in `volumes/db/` did not run | `volumes/db/data` was not empty. A first-time init requires an empty data directory. |
| Migration fails with `column old.email_confirmed_at does not exist` | The `auth` container has not migrated the `auth` schema yet. Start it and wait for `healthy` before applying migrations (see 5.1). |
| PowerSync restarts with Mongo errors | `mongo-rs-init` did not complete; check `docker compose logs mongo-rs-init` and that the replica set `rs0` is initiated. |
| Clients authenticate against REST but not against sync | `PS_SUPABASE_JWT_SECRET` ≠ `JWT_SECRET`. |
| `PGRST` returns `schema not found` | Schema missing from `PGRST_DB_SCHEMAS`; restart `rest` after changing it. |
| Auth cannot send mail (`x509: certificate signed by unknown authority`) | Set `INSTALL_CERTS=true`, place the CA files in `volumes/auth/certs/`, `docker compose build auth`. |
| Replication slot grows / `wal_status = lost` | PowerSync was down too long. `max_slot_wal_keep_size` is 8 GB; if the slot is lost, PowerSync re-replicates from scratch. |
| Seed loading aborts mid-file | Re-run that single file — `lookup.sql` is idempotent; for the chunked files, truncate the affected table and reload all its chunks. |

## Appendix: Testing the deployment

Rehearse this guide on a **disposable VM** before touching a real server, and again
whenever migrations, `docker-compose.yaml` or `.env` change.

### Why a separate machine is required

A test stack cannot be isolated from a production stack on the same host:

- `docker-compose.yaml` sets fixed `container_name:` values (`supabase-db`, `supabase-kong`, …),
  so a second project collides on container names.
- The database lives in a **bind mount** (`./volumes/db/data`), not a named volume — a
  second checkout on the same host is a different directory, but `docker compose -p <name>`
  alone changes nothing about which directory is written.
- Host ports (`${KONG_HTTP_PORT}`, `${POSTGRES_PORT}`, `${PS_PORT}`, `27017`) are fixed.

A VM with 4 vCPU / 16 GB RAM / 100 GB disk is enough for the full run; 8 GB is enough if
you test without PowerSync (see 6.1).

### Provisioning the VM

Any Debian/Ubuntu image works. Install Docker from the official repository — the
distribution packages are usually too old for the `include:` syntax (needs Compose ≥ 2.20.3):

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER" && newgrp docker
docker compose version          # must be >= 2.20.3
```

Take a **VM snapshot right after this point**. Reverting to that snapshot is the fastest
and most honest reset — it also restores the state of `/var/lib/docker`, which
`docker compose down -v` does not fully do.

Then follow the guide from section 3 (Clone the repository) onwards.

### Two passes

**Pass 1 — schema only (~15 min, repeat as often as needed).** Skip the seeds. This
exercises the parts most likely to break: `.env` completeness, the `volumes/db/` init
scripts, all migrations applied from zero against the *compose* Postgres, the Mongo
replica set, PowerSync's replication slot and the Kong routes.

::: tip
Local development normally runs `supabase start`, which bootstraps Postgres differently
from `docker compose up db`. "All migrations apply cleanly from zero on the compose image"
is therefore the least-exercised step of the whole procedure — it is what pass 1 is for.
:::

**Pass 2 — full seed load (once).** Only after pass 1 is green. It measures the real
loading time of the >3 GB of seed data, confirms the `plot_part_*` / `tree_part_*` chunks
load in glob order, and reveals whether the seed repositories actually contain everything
this instance needs.

### Automated smoke test

`scripts/deploy-smoke-test.sh` in TFM-Server runs pass 1 unattended and asserts each stage —
and with `--seed` / `--seed-intern` it runs pass 2 the same way:

```bash
./scripts/deploy-smoke-test.sh --reset --seed-lookup           # pass 1, full stack
./scripts/deploy-smoke-test.sh --reset --no-powersync          # API-only variant
./scripts/deploy-smoke-test.sh --reset --seed-lookup --teardown --yes   # CI style
./scripts/deploy-smoke-test.sh --reset --seed-intern --yes     # pass 2, all seeds
```

| Flag | Effect |
| --- | --- |
| `--reset` | `docker compose down -v` + `rm -rf volumes/db/data` before starting (asks for confirmation) |
| `--seed-lookup` | Loads `seeds/public/lookup.sql` only, and loads it twice to prove it is idempotent |
| `--seed` | Loads **all** of `seeds/public/` (~1.3 GB) after the lookup check, then asserts every seeded `inventory_archive` table is non-empty |
| `--seed-intern` | `--seed` plus `seeds/intern/` (~1.8 GB, DMZ only). A checkout without the intern seeds warns and continues |
| `--no-powersync` | Starts the Supabase services only, and asserts that no Mongo container and no replication slot exist |
| `--teardown` | Removes the stack and the data directory afterwards |
| `--yes` | Skips the interactive confirmation |

It checks, in order: Compose version, `.env` variables, submodule contents, Postgres
readiness, that the init scripts actually ran (the `authenticator` role exists), every
migration file applied individually with `ON_ERROR_STOP`, the presence of the `lookup`,
`inventory_archive`, `derived` and `public` schemas and of the `powersync` publication,
seed idempotency, seeded row counts, container states, `mongo-rs-init` exiting 0,
`GET /rest/v1/`, `/auth/v1/health`, `/functions/v1/health`, PowerSync's `/probes/liveness`,
and an active replication slot. It exits non-zero if any assertion fails.

Seeding happens in stage 5, before the full stack (and with it PowerSync) starts in stage 6
— the same reason `deploy.sh` stops PowerSync around the load: every seeded table is in the
`powersync` publication, and replicating millions of rows through logical decoding instead
of one initial snapshot is what makes a seed load crawl. Each file is printed with its size
and load time, so a multi-hundred-MB chunk is not mistaken for a hang. Only `lookup.sql` is
re-run for the idempotency assertion; the bulk files are plain `INSERT`s and would duplicate
rows.

::: warning
The script is destructive with `--reset` and deletes `volumes/db/data` of its own
checkout. Run it on the disposable VM only.
:::

::: warning The smoke test records no migration history
To assert every file individually, the smoke test applies migrations with a plain
`psql` loop — it never writes `supabase_migrations.schema_migrations`. Running
`scripts/deploy.sh` (or `supabase db push`) afterwards **against the same database**
therefore re-applies all migrations from zero and fails on the first non-idempotent
statement (a duplicate-key error on the `lookup` data inserts). Either reset before
switching to `deploy.sh`, or backfill the ledger first:

```bash
supabase migration repair --db-url "${DB_URL}?sslmode=disable" \
  --status applied $(ls supabase/migrations | cut -d_ -f1)
```

:::

### Manual reset between runs

```bash
docker compose down -v --remove-orphans
rm -rf volumes/db/data
```

The `rm -rf` is the part that is easy to forget. Without it, `volumes/db/data` is not
empty on the next start, the init scripts in `volumes/db/` are silently skipped, and the
migrations fail — `20250115140817_inventory_archive.sql` uses `CREATE SCHEMA
inventory_archive;` without `IF NOT EXISTS`, so the migration run is **not** re-runnable
against an already-migrated database.

::: warning `rm` may fail with *Permission denied*
The files in `volumes/db/data` are owned by the container's `postgres` uid, so an
unprivileged host user cannot delete them. Either use `sudo rm -rf volumes/db/data`, or
delete through a container — the Docker daemon has the rights:

```bash
docker run --rm -v "$PWD/volumes/db:/mnt" alpine:3 rm -rf /mnt/data
```

`deploy-smoke-test.sh --reset` uses the container fallback automatically and aborts if
the directory still exists afterwards. Verify a manual reset the same way: if
`volumes/db/data` still exists, the next start will silently reuse the old database.
:::

### Testing the application layer

Schema-level tests live in `supabase/tests/` and run inside `BEGIN … ROLLBACK`, so they are
safe against live data:

```bash
cd supabase/tests
DB_CONTAINER=supabase-db ./run_writability_matrix.sh
```

::: warning These are staging/production tests, not install tests
`test_immutable_columns.sql` and `test_records_writability_matrix.sql` read fixtures from
`public.records` (`SELECT * FROM public.records LIMIT 2`). The seeds populate `lookup` and
`inventory_archive` — **not** `public.records` — so these tests cannot pass on a freshly
seeded installation. Run them against an instance that already holds inventory data.
Note also that `run_writability_matrix.sh` defaults to `DB_CONTAINER=sync-server-db`;
against this stack it must be overridden to `supabase-db`.
:::

PowerSync has no scripted test. The end-to-end check is to point a TFM app build at the
test host and confirm that the initial sync completes and a record edit round-trips.
