# Host runbook — 2026-08 upgrade (PG 15.14 + services + Envoy sidecar)

Copy-paste command sequence for `/home/sadmin/TFM-Server` on prod (`ci.thuenen.de`).
Executes units 0–3 of [.todo/upgrade-2026-08-pg15-services-envoy.md](../.todo/upgrade-2026-08-pg15-services-envoy.md)
in a single maintenance window. **Unit 4 (gateway cutover to Envoy) is deliberately NOT
in this runbook** — Kong keeps serving; Envoy comes up on loopback `:8001` only.

Prerequisite: `kong_upgrade` contains the two stats commits from `origin/main`
(`ffe091a`, `62bca9b`) and is pushed.

Rule for the whole window: **never run a bare `docker compose up -d` until step B7.**
Services are recreated one at a time, in order.

---

## Phase A — preparation (stack keeps serving, no downtime)

### A1. Confirm prod checkout matches assumptions — ✅ DONE 2026-08-14

Results: prod at `25d734e` (verified ancestor of `kong_upgrade` — branch switch loses no
commits), compose v2.32.1 (`include:` OK). Local edits to `config/sync_rules.yaml` and the
`volumes/functions` **submodule** were discarded on the host — see A2b before proceeding.

```bash
cd /home/sadmin/TFM-Server
git log --oneline -1            # expected: at/after b0b9cbe (2026-05-27)
git status --porcelain          # MUST be empty — record and reconcile any local edits first
docker compose config --services
docker compose ps -a
docker compose version          # include: syntax needs >= 2.20.3
```

### A2. supabase-vector / analytics — ✅ RESOLVED 2026-08-14, hybrid outcome

`docker compose config --services` lists neither, so both are **orphans** — but both
containers are **up, and `supabase-analytics` is healthy**: log shipping
(vector → kong `/analytics/v1` → analytics) is plausibly alive and feeding Studio's Logs
tab, contrary to the planning doc's hypothesis-A guess.

Consequences for this window:

- Leave both containers running. `docker compose stop` / `up -d` does not touch orphans.
- **Never pass `--remove-orphans`** during this upgrade — B7's bare `up -d` will print an
  orphan warning for `analytics`/`vector`; that is expected, ignore it.
- The keep-or-kill decision moves to unit 4 (cutover): Envoy has no `/analytics/v1` route,
  so cutover breaks the shipping path unless vector is repointed directly at
  `http://analytics:4000/api/logs` first.

### A2b. Verify what the discarded local edits contained

Both discarded files are runtime-live on prod (bind mount / submodule), so confirm the
branch carries the same content before restarting anything.

**`config/sync_rules.yaml`** — PowerSync stores the active sync rules in Mongo; diff them
against the branch file (DB name = last path segment of `PS_MONGO_URI` in `.env`):

```bash
docker exec tfm-server-mongo-1 mongosh <powersync_db> --quiet --eval \
  'db.sync_rules.find({}, {content: 1}).sort({_id: -1}).limit(1).forEach(d => print(d.content))' \
  > ~/upgrade-20260814/sync-rules-active.yaml
diff ~/upgrade-20260814/sync-rules-active.yaml config/sync_rules.yaml
```

Expected: identical, or the only delta is `lookup_bark_condition` (which the branch adds).
If identical, PowerSync will not even reprocess on restart. If the active rules contain
**anything the branch file lacks**, the discard destroyed a hotfix — port it onto the
branch before B6.

**`volumes/functions` submodule** (branch pins `e8d7e22`) — the reflog survives a discard:

```bash
cd volumes/functions && git log --oneline -1 && git reflog -10 && cd ../..
```

If the reflog shows the submodule sat on a commit **newer** than `e8d7e22` (a deployed
hotfix — the functions container was restarted 8 days ago), that commit is what production
is actually running: update the submodule pin on the branch first, or accept reverting it
knowingly.

### A3. Baseline record

```bash
mkdir -p ~/upgrade-20260814
docker ps --no-trunc --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | tee ~/upgrade-20260814/containers-before.txt
docker images --digests | tee ~/upgrade-20260814/images-before.txt

cd /home/sadmin/TFM-Server
docker compose exec -T db sh -c 'psql -U postgres -d "$PGDATABASE" -c "select version();"' \
  | tee ~/upgrade-20260814/pg-version.txt
docker compose exec -T db sh -c 'psql -U postgres -d "$PGDATABASE" -c "\dx"' \
  | tee ~/upgrade-20260814/extensions.txt
docker compose exec -T db sh -c 'psql -U postgres -d "$PGDATABASE" -c \
  "SELECT datname, datcollate, datctype, datcollversion FROM pg_database;"' \
  | tee ~/upgrade-20260814/collation.txt

# Collation reference output — ADJUST to a real indexed text column (plot/cluster codes).
# This exact query is re-run after the PG bump and diffed byte-for-byte.
docker compose exec -T db sh -c 'psql -U postgres -d "$PGDATABASE" -c \
  "SELECT <text_column> FROM <schema.table> ORDER BY <text_column>;"' \
  > ~/upgrade-20260814/orderby-reference.txt
```

### A4. Database dumps (MVCC-consistent, safe while serving)

```bash
docker compose exec -T db sh -c 'pg_dump -U postgres -Fc "$PGDATABASE"' \
  > ~/upgrade-20260814/tfm-preupgrade.dump
docker compose exec -T db sh -c 'pg_dumpall -U postgres --roles-only' \
  > ~/upgrade-20260814/roles-preupgrade.sql
ls -lh ~/upgrade-20260814/
```

Then **from your laptop**, copy both off the host and verify the dump is readable:

```bash
scp sadmin@ci.thuenen.de:upgrade-20260814/tfm-preupgrade.dump .
scp sadmin@ci.thuenen.de:upgrade-20260814/roles-preupgrade.sql .
pg_restore --list tfm-preupgrade.dump | head
```

### A5. Check out the branch (running containers are unaffected)

```bash
cd /home/sadmin/TFM-Server
git fetch origin
git checkout kong_upgrade
git pull --ff-only origin kong_upgrade
git submodule update --init volumes/functions   # only after A2b cleared the pin question
```

The checkout moves prod forward from `25d734e` by ~20 commits, which delivers migration
**files** it has never had — `20260702…_stats_views` (modified), `20260708…_preserve_updated_by`,
`20260709…_control_troop_read_only`, `20260713…_guard_records_properties_app_only`,
`20260714…_read_only_troop`. **Files arriving is not SQL applied** — migrations are applied
manually in this repo, prod does not track migration history, and at least the
`records.properties` guard is deliberately *not* applied yet (decision pending). The docker
upgrade neither needs nor runs them; just don't mistake their presence for state.

### A6. Update `.env`

```bash
cp .env .env.bak-preupgrade-$(date +%Y%m%d)
```

Add these 11 keys. Copy the **values from the local dev checkout's `.env`**
(generated 2026-08-07) — do not re-generate on the host:

```
SECRET_KEY_BASE                   # fresh secret (replaces the published upstream default)
PG_META_CRYPTO_KEY                # fresh secret
S3_PROTOCOL_ACCESS_KEY_ID         # fresh secret
S3_PROTOCOL_ACCESS_KEY_SECRET     # fresh secret
REALTIME_DB_ENC_KEY=supabaserealtime   # MUST stay this value — decrypts the existing tenant row
STORAGE_TENANT_ID=stub            # keep historical value — baked into storage.objects rows
REGION=stub
GLOBAL_S3_BUCKET=stub
PGRST_DB_MAX_ROWS
PGRST_DB_EXTRA_SEARCH_PATH
IMGPROXY_AUTO_WEBP
```

**Do NOT touch `JWT_SECRET`** — TFM-app and PowerSync authenticate with it.

Then verify the compose file resolves with **zero** unset-variable warnings:

```bash
docker compose config > /dev/null     # any "variable is not set" warning = .env incomplete, fix before continuing
```

### A7. Pull images and build auth (still no downtime)

```bash
docker compose pull                   # pulls all new pinned digests alongside running stack
docker compose build auth             # HARICA certs from volumes/auth/certs (exist on prod)
```

---

## Phase B — maintenance window

### B1. Stop writers

```bash
# TFM-R-Server (adjust path/method to how it runs on this host):
cd /home/sadmin/TFM-R-Server && docker compose stop     # r-plumber, r-derived-listener

cd /home/sadmin/TFM-Server
docker compose stop powersync
# Optional but recommended: put the reverse proxy into maintenance so no app writes land.
```

### B2. Full stop + filesystem snapshot — THIS IS THE ROLLBACK

```bash
docker compose stop
sudo cp -a volumes/db/data volumes/db/data.preupgrade-$(date +%Y%m%d_%H%M%S)
du -sh volumes/db/data volumes/db/data.preupgrade-*     # sizes must match
```

The snapshot predates the PG bump **and** all storage/realtime schema migrations, and no
writers run until B8 — so this one snapshot covers rollback for the entire window.

### B3. Postgres 15.6 → 15.14

```bash
docker compose up -d db
docker compose logs -f db
# wait for: "database system is ready to accept connections"
# WATCH FOR: "collation version mismatch" — this is the silent-wrong-results failure mode
```

If a collation mismatch is logged, before anything else:

```bash
docker compose exec -T db sh -c 'psql -U postgres -d "$PGDATABASE" -c "REINDEX DATABASE \"$PGDATABASE\";"'
docker compose exec -T db sh -c 'psql -U postgres -d "$PGDATABASE" -c "ALTER DATABASE \"$PGDATABASE\" REFRESH COLLATION VERSION;"'
```

Then extensions + stats, and the byte-for-byte collation check:

```bash
docker compose exec -T db sh -c 'psql -U postgres -d "$PGDATABASE"' <<'SQL'
ALTER EXTENSION postgis UPDATE;
ALTER EXTENSION postgis_topology UPDATE;
ANALYZE;
SQL

# same query as A3:
docker compose exec -T db sh -c 'psql -U postgres -d "$PGDATABASE" -c \
  "SELECT <text_column> FROM <schema.table> ORDER BY <text_column>;"' \
  > ~/upgrade-20260814/orderby-after.txt
diff ~/upgrade-20260814/orderby-reference.txt ~/upgrade-20260814/orderby-after.txt && echo "COLLATION OK"
```

**STOP** if the diff is non-empty and B3's REINDEX did not resolve it.

### B4. Mongo 7.0.39

```bash
docker compose up -d mongo mongo-rs-init
docker compose ps mongo               # wait: healthy. mongo-rs-init exiting 0 is expected.
```

### B5. Services, one at a time — wait for healthy before the next

```bash
docker compose up -d imgproxy   && sleep 5 && docker compose ps imgproxy
docker compose up -d meta       && sleep 5 && docker compose ps meta
docker compose up -d functions  && sleep 5 && docker compose ps functions
docker compose up -d studio     && sleep 20 && docker compose ps studio   # must reach "healthy" — api-gw depends on it
# NOTE: the OLD studio has been "(unhealthy)" for ~5 months (pre-existing, baselined 2026-08-14).
# The new image + healthcheck should clear it. If it stays unhealthy, api-gw will not start —
# that blocks only the Envoy sidecar, NOT Kong traffic; debug via:
#   docker compose exec studio node -e "fetch('http://localhost:3000/api/platform/profile').then(r => console.log(r.status))"
docker compose up -d api-gw     && sleep 5 && docker compose ps api-gw    # Envoy, loopback :8001, carries no traffic
docker compose up -d rest       && sleep 5 && docker compose ps rest
docker compose up -d auth       && sleep 5 && docker compose ps auth
docker compose up -d realtime   && sleep 5 && docker compose ps realtime
docker compose up -d storage    && sleep 5 && docker compose ps storage
docker compose logs storage | tail -50    # 57 minors of schema migrations run here — read them
docker compose up -d kong       && docker compose ps kong                 # unchanged image, still THE gateway
```

If any single service misbehaves: repin **that one image line** to its old digest
(recorded in `containers-before.txt`), `docker compose up -d <service>`, continue.

### B6. PowerSync — verify the existing replication slot survives

```bash
docker compose up -d powersync
docker compose logs powersync | tail -50
docker compose exec -T db sh -c 'psql -U postgres -d "$PGDATABASE" -c \
  "select slot_name, active, wal_status from pg_replication_slots;"'
```

Expected: the **pre-existing** slot, `active = t` — not a freshly created one. The
`sync_rules.yaml` change (`lookup_bark_condition`) makes PowerSync reprocess sync rules on
start; that is expected log output, **not** a client re-sync.

### B7. Whole stack + final state

```bash
docker compose up -d                  # now safe — everything already recreated
                                      # orphan warning for analytics/vector is EXPECTED — do NOT add --remove-orphans
docker compose ps -a                  # all healthy / expected-exited, nothing restarting
docker ps --no-trunc --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | tee ~/upgrade-20260814/containers-after.txt
```

### B8. Restart writers — only after Phase C smoke passes

```bash
cd /home/sadmin/TFM-R-Server && docker compose up -d
# re-enable reverse proxy if it was in maintenance
```

---

## Phase C — smoke test (before B8 / before announcing done)

Runbook section 6, in order:

1. `docker compose ps` — all healthy, nothing restarting.
2. Auth: login + token refresh; custom access-token hook returns expected claims.
3. REST: authenticated read **and write** on `records`; RLS enforced for a non-privileged role.
4. PostGIS: spatial query on plot coordinates returns correct results.
5. Collation: `orderby-after.txt` diff was byte-identical (B3).
6. Storage: upload, download, imgproxy transform. Spot-check `storage.objects` rows against files on disk.
7. Edge functions: invoke one; confirm the `WEBHOOK_TOKEN` path.
8. PowerSync: `/sync/` health, a client syncs and a write round-trips — **without a full re-sync**.
9. TFM-R-Server: `r-plumber` and `r-derived-listener` connect and process (after B8).
10. Studio loads and introspects the schema (the `meta`/PG15 check).
11. Realtime: subscribe, receive a change through the gateway.

Envoy shadow check (zero traffic impact, start of the soak period):

```bash
# do NOT `source .env` — it is not shell-safe (unquoted spaces, & in PS_MONGO_URI)
ANON_KEY=$(grep '^ANON_KEY=' .env | cut -d'=' -f2-)
for p in 8000 8001; do
  printf "port %s: " "$p"
  curl -s -o /dev/null -w '%{http_code}\n' -H "apikey: $ANON_KEY" \
    "http://127.0.0.1:$p/rest/v1/records?select=id&limit=1"
done   # 8000 = Kong, 8001 = Envoy — status codes must match on TABLE paths
```

**Known deliberate divergence (found 2026-08-14):** the bare OpenAPI root `/rest/v1/`
returns 200 on Kong but **403 on Envoy with the anon key** — the `rest-v1-openapi-protected`
route (`lds.template.yaml:338`) restricts the OpenAPI document to `SERVICE_ROLE_KEY` only.
This is upstream's intended hardening, same family as the `/api/mcp` and `/realtime/v1/api/*`
lockdowns. NOT a failure. Before cutover, confirm no TFM consumer fetches `/rest/v1/` root
with the anon key (schema-introspection tools, Comparison-Tool, generated API docs).

Then differential-test real TFM request shapes against `:8001` for 1–2 weeks
(especially URLs containing `%2F`) before scheduling unit 4.

---

## Rollback

| Scope | Commands | Cost |
| --- | --- | --- |
| Everything (before writers resume) | `docker compose down` → `sudo mv volumes/db/data volumes/db/data.failed-$(date +%s)` → `sudo mv volumes/db/data.preupgrade-<ts> volumes/db/data` → `git checkout main` → `docker compose up -d` | minutes, zero data loss |
| One service | repin that image line to the digest in `containers-before.txt`, `docker compose up -d <service>` | seconds |
| Envoy | `docker compose rm -sf api-gw` | zero — it never carried traffic |
| `.env` | restore `.env.bak-preupgrade-<date>` | — |

PG 15.14 cannot be minor-downgraded in place and storage/realtime migrations do not
reverse — the B2 snapshot is the only full way back, and it is only lossless **before
writers resume (B8)**. After that, rolling back means losing field data written since.
