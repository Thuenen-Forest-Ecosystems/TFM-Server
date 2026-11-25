# Host runbook — 2026-11 security upgrade (images, PG 15.20, Kong → Envoy, #437)

Command sequence for `/home/sadmin/TFM-Server` on prod (`vwswo14-bs`, 134.110.2.52, reached as
`ciP` through the jump host). Branch: `upgrade-2026-11`. Window: **Saturday 2026-11-28**.
Users sync and log out on Friday 27th and come back on Monday 30th. Sunday is buffer.

Why: Node/Brotli CVE-2026-111497 in storage-api, postgres-meta, studio and powersync; Kong 2.8.1
(nginx 1.19.9, end of life) is the public gateway; PostgreSQL 15.14 lacks the fixes of 15.15–15.20.
The institute's Apache has rejected `Content-Encoding: br` requests since 2026-11-19 — a stopgap.

## Rules for the window

1. Until step S12 every `docker compose up -d` names **one service** and carries `--no-deps`.
   `rest`, `auth`, `realtime`, `storage` and `meta` depend on `db`; without `--no-deps` Compose
   recreates Postgres with them.
2. Never `--remove-orphans`.
3. Never `source .env` — the prod file is not shell-safe. Read keys with `grep '^KEY=' .env | cut -d= -f2-`.
4. Lossless rollback ends at **S10** (gateway opened to the public). Note the time.
5. Run everything from `/home/sadmin/TFM-Server`.

## Target versions (all pinned by digest in the branch)

| Service | Running | Target |
| --- | --- | --- |
| db | supabase/postgres 15.14.1.159 | 15.20.0.002 |
| storage | storage-api v1.68.9 | v1.89.12 (Node 26.13.0) |
| meta | postgres-meta v0.96.8 | v0.100.1 (Node 22.23.5) |
| studio | 2026.08.03 | 2026.11.02-sha-a05e7ec (Node 22.23.4) |
| powersync | 1.23.3 | 1.28.3 (Node 24.22.3) |
| rest | postgrest v14.16 | v14.18 |
| auth | gotrue v2.195.0 | v2.197.0 (built from `Dockerfile.auth`, `INSTALL_CERTS=true`) |
| realtime | v2.124.0 | v2.148.3 (new entrypoint script) |
| functions | edge-runtime v1.74.3 | v1.77.9 |
| imgproxy | v3.30.1 | v4.0.21 |
| mongo | 7.0.39 | 7.0.48 |
| gateway | Kong 2.8.1 live, Envoy v1.39.0 shadow | Envoy v1.39.6 live, Kong stopped as rollback |

Drop order if a step fails its gate and time runs short: auth, imgproxy, realtime, functions,
mongo, then the gateway cutover. To drop a service, restore its old `image:` line (table above,
digests in `git show main:docker-compose.yaml`) before its `up`.

## What the rehearsals established (2026-11-25)

- Local, full stack on a fresh database (worktree `TFM-Server-rehearsal`, project `tfm-rehearsal`):
  every service healthy on the target versions; PowerSync 1.23.3 → 1.28.3 kept its slot and did
  not re-replicate; gateway switch takes about 2 s each way.
- On prod, on a throttled copy of the live data directory (volume `rh-pgdata`): PostgreSQL 15.20
  starts and recovers; slot readable through `pgoutput`; collation version unchanged (no REINDEX);
  no btree index on a `bpchar` column (no 15.20 REINDEX); PostGIS, pg_graphql, pg_jsonschema work;
  writability matrix and guard verdict as expected; `437-renumber-trees.sql` dry run passes;
  storage-api v1.89.12 migrates 62 → 80 and uploads, downloads, transforms (imgproxy v4), deletes.
- Candidate Envoy beside the prod Kong: `gateway-diff.sh` 62 cases, 0 unapproved differences;
  records guard in enforce mode through Envoy: HTTP test 13/13, real supabase_flutter and
  supabase-js pass.

Findings that became steps below:

- **db-config volume.** It shadows `/etc/postgresql-custom` and still holds the files of the image
  that created it (on prod: `supautils.conf` from December 2024, empty `conf.d`). Step S4 runs
  `scripts/db-config-sync.sh --apply`.
- **Kong and recreated backends.** Kong answered 502 after a backend was recreated (stale DNS).
  Kong is therefore started last in S6; if it answers 502, `docker restart supabase-kong`.
- **Second local run with last night's prod dump (2026-11-25, 122,321 records, runbook followed
  step by step):** PowerSync 1.28.3 ran two storage migrations on the real bucket data in seconds,
  kept its slot, did not re-snapshot, and served the same buckets and operation counts as before.
  A refresh token issued on prod under gotrue v2.195 refreshed under v2.197; an access token
  from before the upgrade kept working against PostgREST and PowerSync. `437-renumber-trees.sql`
  committed (24 plots), `gateway-diff.sh` 62/0, guard test passed through Kong and Envoy, the
  final `up -d --dry-run` showed nothing to recreate.
- **A full PowerSync re-snapshot took about 35 minutes** in that run (Docker Desktop, 24 GB). That
  is the price of the "PowerSync alone" rollback. With too little memory MongoDB gets killed and
  the snapshot restarts from zero each time — prod has the memory, the Mac at 12 GB did not.
- **The auth image is built locally and keeps its tag.** After `docker compose build auth` the tag
  `tfm-server-auth` points at v2.197.0 whatever commit is checked out. S2 therefore tags the old
  image, and the rollback retags it.
- **Rollback drill:** swapping the data directory, restoring the config volume and replacing the
  MongoDB volume took 20 s in total. Starting the OLD versions on the restored state was not
  rehearsed (the drill's `git checkout` was blocked by a local file edit — hence the
  `git status` gates below).

## State on prod before the window (checked 2026-11-25)

- Repo on `main` at `e1f059c`, clean; a stash from an older change exists and is left alone.
- No `analytics` / `vector` containers any more. `supabase-studio` and `supabase-imgproxy` are stopped.
- One replication slot, `powersync_18_58a7` (pgoutput). Guard mode `enforce`.
- Free disk 286 GB; PGDATA 33.6 GB (23 GB of it the unused `_supabase` database); MongoDB 9.3 GB.
- Leftovers from the rehearsal: stopped containers `rh-db`, `rh-storage`, `rh-imgproxy`, volumes
  `rh-pgdata`, `rh-db-config`, `rh-storage`, network `rh-net`, `~/rehearsal/`. Remove after the window.
- The webhook `tfm-hook` (PM2) is stopped for good. Edge functions are deployed with `./deploy.sh`.

## Friday 27 November

Daytime:

- Manual #437 corrections are done by the domain side. 13124/2 and 13124/3 are also in the script
  list (target numbers 18–20 and 18–25): keep those numbers free.
- Go/no-go by noon. Commit and push the branch, tag the release commit `upgrade-2026-11-rc`.

Evening, once everyone has synced and logged out — **before** the host OS update:

```bash
cd /home/sadmin/TFM-Server
# 1. #437: does the fixed list still match? Dry run, writes nothing.
docker exec -i supabase-db psql -U postgres -d postgres -X -v ON_ERROR_STOP=1 -f - \
  < scripts/oneoff/437-renumber-trees.sql | tail -30
#    Expect "Kontrolle bestanden: 55 Bäume …". If it aborts ("Ecke inzwischen verändert", "neue
#    Nummer schon vergeben"), regenerate the list with 437-tree-number-conflicts.sql and re-test locally.

# 2. Fresh logical dump, copied off the host and verified there.
docker compose -f ../TFM-Server-Backup/docker-compose.yaml exec backup /scripts/backup.sh
ls -lt ../TFM-Server-Backup/backups | head -3
#    on the Mac: scp the newest db_*.dump, then `pg_restore --list <file> | wc -l` must succeed.

# 3. Pull the target images (no container is touched).
git fetch origin
git show origin/upgrade-2026-11:docker-compose.yaml > /tmp/compose-target.yaml
git show origin/upgrade-2026-11:services/powersync.yaml > /tmp/ps-target.yaml
git show origin/upgrade-2026-11:services/mongo.yaml > /tmp/mongo-target.yaml
grep -hoE 'image: [^ ]+' /tmp/compose-target.yaml /tmp/ps-target.yaml /tmp/mongo-target.yaml \
  | awk '{print $2}' | grep '@sha256' | sort -u | xargs -n1 docker pull -q
docker pull -q "$(grep -oE 'FROM supabase/gotrue[^ ]+' <(git show origin/upgrade-2026-11:Dockerfile.auth) | awk '{print $2}')"
```

Then the host OS update and reboot (operator / IT). **Do not run `docker compose up` around the
reboot** — the containers have `restart: unless-stopped` and come back by themselves. After it:

```bash
docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}'      # same images as before, all Up
docker version --format 'engine {{.Server.Version}}'; docker compose version --short
docker exec supabase-db psql -U postgres -d postgres -Atc \
  "select slot_name, active, wal_status from pg_replication_slots"   # powersync slot active
curl -s -o /dev/null -w '%{http_code}\n' https://ci.thuenen.de/auth/v1/health?apikey=$(grep '^ANON_KEY=' .env | cut -d= -f2-)   # 200
```

Cold cache after the reboot is expected (`view_records_details` may time out until warm); nobody
is logged in, so no prewarm is needed before Saturday.

## Saturday 28 November

Open a `tmux` session first so a dropped SSH connection does not interrupt a step.

### S0 — preconditions

```bash
cd /home/sadmin/TFM-Server
TS=20261128
ls -lt ../TFM-Server-Backup/backups | head -3            # 02:00 dump exists; copy it off-host too
git rev-parse HEAD > ~/upgrade-$TS-git-before.txt
docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.ID}}' > ~/upgrade-$TS-containers-before.txt
docker inspect --format '{{.Name}} {{.Image}}' $(docker ps -aq) > ~/upgrade-$TS-imageids-before.txt
docker exec supabase-db psql -U postgres -d postgres -Atc \
  "select slot_name, confirmed_flush_lsn from pg_replication_slots; select count(*) from public.records;
   select max(logged_at) from records_guard.write_log;" | tee ~/upgrade-$TS-db-before.txt
```

Gate: the last entry in `records_guard.write_log` is from Friday (no client is still writing).

### S1 — stop writers, S2 — snapshots (the rollback)

```bash
docker compose stop powersync
docker compose stop                      # everything; from here the API is down
docker ps --format '{{.Names}}' | grep -E 'supabase|tfm-server' || echo "all stopped"

# Postgres data directory (no sudo needed: root inside the helper container). ~10 min.
docker run --rm -v /home/sadmin/TFM-Server/volumes/db:/v alpine \
  sh -c "cp -a /v/data /v/data.preupgrade-$TS && du -sm /v/data /v/data.preupgrade-$TS"
# Config volume and MongoDB storage
docker volume create tfm-server_db-config_pre$TS && docker run --rm \
  -v tfm-server_db-config:/s:ro -v tfm-server_db-config_pre$TS:/d alpine sh -c 'cp -a /s/. /d/ && ls -ln /d'
docker volume create tfm-server_mongo_storage_pre$TS && docker run --rm \
  -v tfm-server_mongo_storage:/s:ro -v tfm-server_mongo_storage_pre$TS:/d alpine sh -c 'cp -a /s/. /d/ && du -sm /d'
cp -p .env .env.bak-preupgrade-$TS
docker tag tfm-server-auth tfm-server-auth:pre$TS      # the build in S6 moves the plain tag
```

Gate: both `du` sizes of the data directory match; the Mongo copy is about 9 GB.

### S3 — code and maintenance mode

```bash
git status --short            # must print nothing, otherwise the checkout can refuse
git fetch origin && git checkout upgrade-2026-11 && git log --oneline -1
printf '\n# gateway mode, see scripts/gateway-switch.sh\nCOMPOSE_PROFILES=gw-kong\n' >> .env
# maintenance: the gateway listens on loopback only until S10
sed -i 's/^KONG_HTTP_PORT=8000$/KONG_HTTP_PORT=127.0.0.1:8000/' .env && grep '^KONG_HTTP_PORT=' .env
docker compose config -q && docker compose config --images | sort
```

Gate: `config -q` is silent; the image list equals the target table (plus `kong:2.8.1` and `tfm-server-auth`).

### S4 — Postgres 15.20

```bash
scripts/db-config-sync.sh            # report: supautils.conf differs = yes, conf.d in volume empty
scripts/db-config-sync.sh --apply    # key md5 before == after
docker compose up -d --no-deps db
docker compose logs -f db            # until "database system is ready to accept connections"
docker exec supabase-db psql -U postgres -d postgres -Atc "select version();
  select slot_name, plugin, wal_status from pg_replication_slots;
  select datname, datcollversion, pg_database_collation_actual_version(oid) from pg_database where datallowconn;
  select count(*) from public.records; select mode from records_guard.settings;"
docker exec supabase-db id postgres  # uid=100 gid=101, as before
```

Gate: 15.20; slot `powersync_18_58a7` present; collation versions equal (2.40 / 2.40); record
count equals S0; guard `enforce`. If Postgres does not come up, `log_min_messages=fatal` hides the
reason — read it with
`docker compose run --rm --no-deps --entrypoint sh db -c 'su postgres -s /bin/sh -c "postgres -D /var/lib/postgresql/data -c config_file=/etc/postgresql/postgresql.conf -C shared_buffers"'`.

Warm the cache now, it takes a while and nothing else needs the disk:

```bash
docker exec supabase-db psql -U postgres -d postgres -Atc "
  select pg_prewarm('public.records');
  select pg_prewarm(reltoastrelid) from pg_class where oid = 'public.records'::regclass;
  select sum(pg_prewarm(indexrelid)) from pg_index where indrelid = 'public.records'::regclass;"
```

### S5 — MongoDB

```bash
docker compose up -d --no-deps mongo && docker compose up -d --no-deps mongo-rs-init
docker compose ps -a mongo mongo-rs-init          # mongo healthy, rs-init Exited (0)
```

### S6 — services, one at a time

```bash
docker compose build auth                          # INSTALL_CERTS=true comes from .env
for s in imgproxy meta studio rest auth realtime functions storage; do
  docker compose up -d --no-deps $s; sleep 15; docker compose ps $s
done
docker compose exec -T auth auth version           # v2.197.0 — proves the rebuilt image is running
docker compose logs --since 10m auth | grep -iE 'migrat|error|fatal' | tail
docker compose logs --since 10m storage realtime | grep -iE 'migrat|error|fatal' | tail
docker compose up -d --no-deps kong && docker compose up -d --no-deps api-gw
docker compose ps
for s in storage meta studio; do printf "$s "; docker compose exec -T $s node -v; done   # 26.13.0 / 22.23.5 / 22.23.4
```

Gate: every service healthy (kong and meta have no healthcheck: `Up`); auth log says
"GoTrue migrations applied successfully"; no error lines.

### S7 — checks through Kong on loopback

```bash
A=$(grep '^ANON_KEY=' .env | cut -d= -f2-)
for u in auth/v1/health rest/v1/ functions/v1/health; do
  printf '%-22s %s\n' $u $(curl -s -o /dev/null -w '%{http_code}' -H "apikey: $A" -H "Authorization: Bearer $A" http://127.0.0.1:8000/$u); done
```

From the Mac through a tunnel (`ssh -S ~/.ssh/cm-ciP -O forward -L 18000:127.0.0.1:8000 ciP`), with
the anon key of prod and the test account:

```bash
API_URL=http://127.0.0.1:18000 supabase/tests/run_app_only_guard_http.sh enforce    # 13/13, TEST PASSED
```

Also: password login and token refresh, one storage download from bucket `validation`, Studio
with basic auth. Gate: all green. **A failure here means whole-window rollback — still lossless.**

### S8 — PowerSync

```bash
docker compose up -d --no-deps powersync
docker compose logs -f powersync      # "Running migrations up" → two "Executing … (up)" lines
                                      # → "Successfully activated storage: mongodb." → replication
docker compose logs --since 5m powersync | grep -c 'Replicating \\"public'   # 0 = no re-snapshot
docker exec supabase-db psql -U postgres -d postgres -Atc \
  "select slot_name, active, wal_status, pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) from pg_replication_slots"
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8181/probes/liveness
docker compose exec -T powersync node -v            # v24.22.3
```

Gate: the old slot is active again and its lag goes to ~0 (no new slot, no re-snapshot); liveness 200.
The warning about deprecated `bucket_definitions` is expected. If the storage migration fails or a
new slot appears with a full re-snapshot, wait for it to finish (clients are logged out) or take
the PowerSync row of the rollback table.

### S8b — #437, automated renumbering

```bash
docker exec -i supabase-db psql -U postgres -d postgres -X -v ON_ERROR_STOP=1 -f - \
  < scripts/oneoff/437-renumber-trees.sql | tail -30                 # dry run, must pass
docker exec -i supabase-db psql -U postgres -d postgres -X -v ON_ERROR_STOP=1 -v commit=1 -f - \
  < scripts/oneoff/437-renumber-trees.sql | tail -8                  # "COMMIT: Umnummerierung geschrieben …"
docker exec supabase-db psql -U postgres -d postgres -Atc \
  "select count(*) from backup_restore.records_437_renumber_20261109"   # 24 rows (one per plot)
```

Gate: "Kontrolle bestanden: 55 Bäume umnummeriert, sonst keine Änderung" and `COMMIT`. PowerSync
replicates the 24 changed records; S10 checks one of them on the test device (e.g. 18360/3 → 13, 14, 15).
Undo: the `UPDATE … FROM backup_restore.records_437_renumber_20261109` in the script header. A
whole-window rollback before S10 also undoes it; run it again afterwards.

### S9 — Kong against Envoy, both on loopback

```bash
ENV_FILE=.env A_URL=http://127.0.0.1:8000 B_URL=http://127.0.0.1:8001 \
  TFM_TEST_EMAIL=… TFM_TEST_PASSWORD=… scripts/gateway-diff.sh | grep -vE '^SAME|^OK '
```

Gate: "0 unapproved difference(s)". Then the guard test through Envoy (tunnel to 8001):
`API_URL=http://127.0.0.1:18001 supabase/tests/run_app_only_guard_http.sh enforce` → 13/13.

### S10 — open to the public, still on Kong

```bash
sed -i 's/^KONG_HTTP_PORT=127.0.0.1:8000$/KONG_HTTP_PORT=8000/' .env && grep '^KONG_HTTP_PORT=' .env
docker compose up -d --no-deps --force-recreate kong
date -u +%H:%M:%S        # ← lossless rollback ends here, write it down
```

Through `https://ci.thuenen.de`, save the output for the comparison in S11:

- `curl -sI https://ci.thuenen.de/ | grep -i '^server'` → `kong/2.8.1`
- `API_URL=https://ci.thuenen.de supabase/tests/run_app_only_guard_http.sh enforce` → 13/13
- `GUARD_TEST_URL=https://ci.thuenen.de … flutter test test/records_guard_app_header_test.dart`
- the documentation site in a browser: login, a table page (`/rest/v1/` with the anon key), one validation call
- the test device: logs in, syncs, uploads its pending edit, shows the renumbered trees of one #437 plot
- Brotli block still active: `curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Encoding: br' --data-binary x https://ci.thuenen.de/storage/v1/` → 403

### S11 — cutover to Envoy

```bash
scripts/gateway-switch.sh envoy          # "OK: supabase-envoy is the live gateway"
curl -sI https://ci.thuenen.de/ | grep -i '^server'      # no longer kong/2.8.1
```

Repeat the S10 list. Additionally request a password-recovery mail for the test account and check
that the link points to `https://ci.thuenen.de/…`. Any difference that is not in the approved list
of `gateway-diff.sh`: `scripts/gateway-switch.sh kong` first, diagnose afterwards.

### S12 — close

```bash
docker compose up -d --dry-run 2>&1 | grep -iE 'recreate' && echo "STOP: something would be recreated" || echo "nothing to recreate"
docker compose up -d                                   # never --remove-orphans
docker compose ps -a
docker compose -f ../TFM-Server-Backup/docker-compose.yaml exec backup /scripts/backup.sh   # copy off-host
docker exec supabase-db psql -U postgres -d postgres -Atc "select count(*) from public.records"
```

Gate: all services healthy, `supabase-kong` Exited and left in place, record count as in S0, backup written.

## Rollback

| Scope | How | Cost |
| --- | --- | --- |
| Gateway | `scripts/gateway-switch.sh kong` | ~2 s, up to a minute of 503 from Apache; works on Monday too |
| meta, studio, rest, functions, imgproxy, mongo | old `image:` line, `docker compose up -d --no-deps <svc>` | seconds |
| PowerSync alone (not after Monday morning without need: ~35 min+ without sync) | stop it; `docker exec tfm-server-mongo-1 mongosh --quiet --eval 'db.getSiblingDB("powersync").dropDatabase()'`; drop every inactive `powersync_*` slot (`select pg_drop_replication_slot(slot_name) from pg_replication_slots where not active and slot_name like 'powersync_%'`), otherwise it pins up to 8 GB of WAL; old image line; start | full re-replication (about 35 min in the rehearsal); every device re-downloads; pending uploads are kept (they go through PostgREST) |
| Whole window, before S10 | below | ~20 min, lossless, no client re-sync |
| Postgres, auth, realtime, storage after S10 | fix forward only: the snapshot lacks the writes made since, and storage 1.68.9 must not run on the migrated schema | — |

Whole-window rollback (before S10 only):

```bash
TS=20261128
docker compose --profile gw-kong down                # containers only; no -v. The profile makes it include Kong.
git status --short                                   # must print nothing
git checkout "$(cat ~/upgrade-$TS-git-before.txt)"
cp -p .env.bak-preupgrade-$TS .env
docker run --rm -v /home/sadmin/TFM-Server/volumes/db:/v alpine \
  sh -c "mv /v/data /v/data.failed-$TS && mv /v/data.preupgrade-$TS /v/data && ls /v"
docker run --rm -v tfm-server_db-config_pre$TS:/s:ro -v tfm-server_db-config:/d alpine sh -c 'cp -a /s/. /d/'
docker volume rm tfm-server_mongo_storage && docker volume create tfm-server_mongo_storage
docker run --rm -v tfm-server_mongo_storage_pre$TS:/s:ro -v tfm-server_mongo_storage:/d alpine \
  sh -c 'cp -a /s/. /d/ && du -sm /d'
docker tag tfm-server-auth:pre$TS tfm-server-auth:latest
docker compose up -d
docker compose exec -T auth auth version             # v2.195.0
docker exec supabase-db psql -U postgres -d postgres -Atc "select version(); select count(*) from public.records;
  select slot_name, active from pg_replication_slots"
```

The PostgreSQL snapshot and the MongoDB copy are a pair (same slot position): restore both or neither.

The copied config volume restores the old `supautils.conf`; the files added to `conf.d` stay and
are harmless for 15.14 (the old image ships the same five files). The uid of postgres is 100:101 in
both images — the chown trap of August does not apply.

Records guard emergency lever, independent of everything above:
`update records_guard.settings set mode = 'log';`

## Monday 30 November

In this order:

1. Envoy access log: `docker logs --since 2h supabase-envoy | awk '{print $9}' | sort | uniq -c` —
   look at 400, 401 on `/rest/v1/records`, 403 and 5xx. The last field of each line is `X-Client-Info`.
2. `select client_info, count(*) from records_guard.write_log where logged_at > '2026-11-30' group by 1`
   — only `supabase-flutter/…` and `tfm-web/…` with real users.
3. auth log for `refresh_token_already_used`; PowerSync log for errors, its memory against the
   1000 MB heap cap; `pg_replication_slots` lag; free disk.
4. First `view_records_details` timeouts are a cold cache, see S4.

Tripwire: an unexplained client-facing anomaly → `scripts/gateway-switch.sh kong`, then diagnose.

## After the window

- Remove the rehearsal leftovers and, once Monday went well, the snapshots
  (`volumes/db/data.preupgrade-20261128`, the two `_pre20261128` volumes, the older
  `data.preupgrade-20260816_135657`).
- Remove the Kong service and `volumes/api/kong.yml` once Envoy has run for two weeks.
- Ask IT to drop the `/hook/` route in the Apache and to restrict 8000/8181 to the Apache host.
- `TFM-Server-Backup` still pins `supabase/postgres:15.6.1.146` for `pg_dump`; align it with 15.20.
- Separate window, early 2027: PostgreSQL 17 and MongoDB 8. Drop the unused 23 GB `_supabase`
  database beforehand.
