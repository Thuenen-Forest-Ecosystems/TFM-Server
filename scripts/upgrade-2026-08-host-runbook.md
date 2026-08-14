# Host runbook — 2026-08 upgrade (PG 15.14 + services + Envoy sidecar)

Copy-paste command sequence for `/home/sadmin/TFM-Server` on prod (`ci.thuenen.de`).
Executes units 0–3 of [.todo/upgrade-2026-08-pg15-services-envoy.md](../.todo/upgrade-2026-08-pg15-services-envoy.md)
in a single maintenance window. **Unit 4 (gateway cutover to Envoy) is deliberately NOT
in this runbook** — Kong keeps serving; Envoy comes up on loopback `:8001` only.

Prerequisite: `kong_upgrade` contains the two stats commits from `origin/main`
(`ffe091a`, `62bca9b`) and is pushed.

Rule for the whole window: **never run a bare `docker compose up -d` until step B7.**
Services are recreated one at a time, in order.

**Status 2026-08-14: PHASE A IS COMPLETE.** A1 ✅ · A2 ✅ · A2b ✅ · A3 ✅ · A4 ✅ · A5 ✅ ·
A6 ✅ · A7 ✅ · **Envoy sidecar deployed and validated on loopback `:8001`** (differential
test: table paths identical to Kong; `/rest/v1/` root is service-role-only by design — see
Phase C note). Key fingerprints `.env` = Envoy = Kong verified identical.

**Next action: schedule the Phase B maintenance window.** One task carries over — copy the
A4 dumps off the host (the two `scp` commands in A4); they currently sit on the same disk as
the data they protect. Host is ARMED: new pins on disk — no `up -d` on any other service
until B2 backups exist (`restart` is safe).

Four findings from A2b–A7 that change how the window runs — read all four before Phase B:

| # | Finding | Where | Blocking? |
| --- | --- | --- | --- |
| 1 | **`build auth` would have shipped a certless GoTrue** and broken all outbound mail. `.env` fixed. | A7 | **Was** — fixed |
| 2 | **`sudo` needs a password** — B2 cannot run unattended, and `du` on the data dir under-reports instead of failing | B2 | No, but plan for it |
| 3 | **`PGRST_DB_MAX_ROWS=1000` is new** — silent REST truncation; verified safe for current traffic | A6 | No |
| 4 | **A4 dump needs `--disable-triggers`** to restore (circular FKs); B2 snapshot is the real rollback | Rollback | No |

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

### A2b. Verify what the discarded local edits contained — ✅ CLEARED 2026-08-14

**Both discards were harmless. Nothing to port forward.**

- **`config/sync_rules.yaml`**: active-vs-branch diff is exactly the expected single line
  (`- SELECT * FROM "lookup"."lookup_bark_condition"`, which the branch adds) plus a
  trailing newline. No hotfix was destroyed. Active rules saved at
  `~/upgrade-20260814/sync-rules-active.yaml`.
- **`volumes/functions`**: the reflog confirms prod *was* ahead of the pin — it sat on
  `b34f07f`, and the discard reverted it to the pinned `e8d7e22`. But
  `git diff e8d7e22 b34f07f` is a **pure `LICENSE` → `LICENSE.md` rename, 0 insertions,
  0 deletions**. No functional code change, so reverting it costs nothing.

**Repo hygiene note (not blocking, fix outside the window):** this repo carries the
functions repo as **two** submodules at **different pins** — `supabase/functions` →
`b34f07f`, `volumes/functions` → `e8d7e22`. Only `volumes/functions` is mounted into the
container (`docker-compose.yaml:475`), and it is the *stale* one. They should be pinned
together, or the unused one dropped. The working tree also has `supabase/functions`
checked out backwards to `e8d7e22` (source of the `modified: supabase/functions` line in
`git status`) — cosmetic, not runtime.

<details>
<summary>Original A2b verification commands (kept for reference)</summary>

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

</details>

### A3. Baseline record — ✅ DONE 2026-08-14

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

# Collation reference output — placeholder RESOLVED, see note below.
docker compose exec -T db sh -c 'psql -U postgres -d "$PGDATABASE" -A -t -c \
  "SELECT intkey FROM inventory_archive.plot ORDER BY intkey;"' \
  > ~/upgrade-20260814/orderby-reference.txt
docker compose exec -T db sh -c 'psql -U postgres -d "$PGDATABASE" -A -t -c \
  "SELECT intkey FROM inventory_archive.tree ORDER BY intkey;"' \
  > ~/upgrade-20260814/orderby-reference-tree.txt
```

**Baseline results:** PostgreSQL **15.6**, all DBs `en_US.UTF-8`, `datcollversion` **2.39**
(glibc) — uniform, so a single collation check covers the whole cluster. Data dir **29 GB**;
`_supabase` (16 GB) is larger than `postgres` (7.5 GB). Free space **349 GB** — ample for
B2's copy.

**Why `intkey`:** it is indexed `varchar` on the two largest inventory tables, and
**783,136 of 783,532 plot rows contain punctuation** (`-plot-10000-1-_bwi2012`). glibc sorts
punctuation at a secondary level, so this column is precisely where a collation-version
change reorders rows — the strongest available canary. Zero non-ASCII, so the risk is
punctuation handling, not encoding. Reference files (regenerate the same way after B3):

| File | Rows | MD5 |
| --- | --- | --- |
| `orderby-reference.txt` (plot) | 783,532 | `ee46a9fa88665c31750a226155639ccd` |
| `orderby-reference-tree.txt` (tree) | 1,722,099 | `46c549091f758157b4789e1417e6a51c` |

An `md5sum` match after B3 is sufficient; `diff` only if it fails.

### A4. Database dumps (MVCC-consistent, safe while serving) — ✅ DONE 2026-08-14

Completed 19:57–20:09 UTC (~12 min) while the stack kept serving.
`tfm-preupgrade.dump` **1.4 GB**, 2654 TOC entries, `pg_restore --list` reads cleanly,
dumped from 15.6. `roles-preupgrade.sql` 6.4 KB, 47 role statements.
**Read the circular-FK caveat in [Rollback](#rollback) before relying on this dump.**
Still to do from your laptop: the two `scp` copies below — the dumps are currently only on
the host, which is the same disk as the data they protect.

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

### A5. Check out the branch (running containers are unaffected) — ✅ DONE 2026-08-14

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

### A6. Update `.env` — ✅ DONE 2026-08-14

All 11 keys present, `REALTIME_DB_ENC_KEY=supabaserealtime` and the three `stub` values
confirmed correct, `JWT_SECRET` untouched (128 chars, unchanged), backup at
`.env.bak-preupgrade-20260814`. **`docker compose config` resolves with zero warnings.**

> **⚠️ Behaviour change — `PGRST_DB_MAX_ROWS=1000` is NEW.** The currently running
> PostgREST has **no** `PGRST_DB_MAX_ROWS` at all (verified via `docker inspect
> supabase-rest`), i.e. today it is unlimited. From B5 onward every REST response is
> capped at 1000 rows. This is a **silent** truncation — PostgREST returns 200 with a
> partial `Content-Range`, not an error.
>
> Checked, and it is **safe to proceed**: the heaviest observed traffic over the last 7
> days of Kong logs tops out at `limit=500` (`lookup_tree_species`), with the rest at
> `limit=200`. The one unbounded reader in the codebase is
> `validation.js:1139` (`lookupByAbbreviation`), which fetches a whole `lookup_*` table
> with no limit and no pagination — but every live call site passes `'tree_species'`
> (**125 rows**), far under the cap.
>
> **Latent landmine, worth fixing separately:** that same function would silently
> mis-validate if ever pointed at `lookup_municipality` (**13,401 rows**) or `lookup_ffh`
> (**4,666 rows**) — it ends in `tableData.filter(...)[0]`, so a truncated table yields
> `undefined`, not an error. `lookup_forest_office` (840) and `lookup_vogel_schutzgebiet`
> (808) are already close to the cap and growing.
>
> Add to Phase C: confirm a >1000-row REST read is not part of any Comparison-Tool or
> R-Server workflow before announcing done.

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

### A7. Pull images and build auth (still no downtime) — ✅ DONE 2026-08-14

All 13 images pulled (exit 0); `auth` skipped by `pull` since it builds locally. Auth image
built and **verified**: 5 HARICA entries in its trust bundle, identical to the running
production container.

> **⚠️ RUNBOOK BUG, FIXED 2026-08-14 — `docker compose build auth` was NOT sufficient.**
> `Dockerfile.auth` is a two-stage select on `ARG INSTALL_CERTS`, which **defaults to
> `false`**, and `docker-compose.yaml:176` passes `INSTALL_CERTS=${INSTALL_CERTS:-false}`.
> **`INSTALL_CERTS` was not set in prod `.env`**, so the documented command would have
> built a certless GoTrue — silently, exit 0, no warning.
>
> Impact had it shipped at B5: `relay-dmz.ux.thuenen.de:25` presents
> `CN=relay-dmz.ux.thuenen.de` ← `GEANT TLS RSA 1` ← `HARICA TLS RSA Root CA 2021` —
> exactly the two certs in `volumes/auth/certs/`. Without them GoTrue cannot verify the
> relay, so **every outbound auth mail (invite, password recovery, email change) fails**.
> Phase C would have missed it: its auth check is login + token refresh, which sends no mail.
>
> **Fix applied:** `INSTALL_CERTS=true` added to prod `.env` (with a comment, next to the
> SMTP block). Note `volumes/auth/certs/` is **untracked in git** — the certs exist only on
> this host, so a fresh checkout elsewhere cannot build a working prod auth image. Worth
> committing them, or documenting where they come from.

```bash
docker compose pull                   # pulls all new pinned digests alongside running stack

grep -q '^INSTALL_CERTS=true' .env || echo "STOP: INSTALL_CERTS missing -> certless auth build"
docker compose build auth             # HARICA certs from volumes/auth/certs (exist on prod)

# verify the certs actually landed — must print 5, matching the running container:
docker run --rm --entrypoint sh tfm-server-auth -c \
  'grep -c HARICA /etc/ssl/certs/ca-certificates.crt'
```

---

## Scheduling the window

**Do not start Phase B until the A4 dumps are copied off the host and
`pg_restore --list` has passed on the receiving machine.** The `scp` is not technically
blocking — it reads a file off disk while Phase B touches containers and
`volumes/db/data` — but it is the off-host safety net, and B2 is where the data it
protects starts changing. Running the window with the only backup on the disk you are
mutating defeats the point. B2's 29 GB copy would also compete with the transfer for disk
bandwidth.

Anchor data point: **the A4 dump of this database took 12 minutes** (19:57–20:09 UTC,
2026-08-14, while serving).

| Step | Estimate | Notes |
| --- | --- | --- |
| B1 stop writers | ~2 min | |
| **B2 snapshot 29 GB** | **5–15 min** | disk-bound; needs an interactive `sudo` password |
| B3 Postgres + `ANALYZE` | 10–20 min | **+30–60 min if REINDEX is required — see below** |
| B4 Mongo | ~2 min | |
| B5 services, one at a time | 15–20 min | storage's 57 migrations land here |
| B6 PowerSync | ~5 min | |
| B7 full `up -d` | ~2 min | |
| **Phase C smoke (12 items)** | **30–45 min** | manual, and it gates B8 |

**Realistic total 1.5–2.5 h. Book 3.5–4 h.**

`sda` reports rotational, but it is a *Virtual Disk* — that flag is unreliable on a VM, so
B2's range is deliberately wide. Measure real throughput once to tighten it.

### The one thing that can blow the estimate

Everything above is predictable except **B3's collation branch**. If the new image ships a
different glibc, `datcollversion` moves off `2.39` and `REINDEX DATABASE` becomes mandatory
on 7.5 GB — the longest single operation in the window, and not optional, because the
failure mode is silently wrong query results rather than an error.

It is binary and unknowable until the container starts, so either book the wider slot or
settle it in advance:

```bash
# throwaway container on a COPY of the data — answers the question without touching prod
docker run --rm -e POSTGRES_PASSWORD=x \
  supabase/postgres:15.14.1.159 \
  postgres -c 'shared_buffers=128MB' &
# then: SELECT datname, datcollversion FROM pg_database;   -- 2.39 => no REINDEX needed
```

This pairs naturally with the `pg_restore --disable-triggers` rehearsal noted in
[Rollback](#rollback) — both want a scratch PG 15.14 container, so do them together.

### Timing

Phase C is followed by a **1–2 week Envoy soak** before unit 4, so pick a slot that leaves
someone attentive afterwards. **B8 is the point of no cheap return:** once writers resume,
rollback means losing field data written since.

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

> **⚠️ `sudo` on this host requires a password** (verified 2026-08-14: `sudo -n true`
> fails). This step **cannot** be run non-interactively or pasted into an unattended
> script — a human must be at the terminal to type it. Budget for it, and do not start
> the window over a connection that cannot prompt.
>
> Note also that `volumes/db/data` is `drwx------ _apt root`, so **plain `du`/`ls` on it
> silently reports 4.0K instead of failing loudly** — always use `sudo` for the size
> check below, or read the size from inside the container
> (`docker compose exec -T db du -sh /var/lib/postgresql/data` → **29 GB**).

```bash
docker compose stop
sudo cp -a volumes/db/data volumes/db/data.preupgrade-$(date +%Y%m%d_%H%M%S)
sudo du -sh volumes/db/data volumes/db/data.preupgrade-*   # must BOTH read ~29G
df -h /home                                                # 349G free before copy
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

# same queries as A3:
docker compose exec -T db sh -c 'psql -U postgres -d "$PGDATABASE" -A -t -c \
  "SELECT intkey FROM inventory_archive.plot ORDER BY intkey;"' \
  > ~/upgrade-20260814/orderby-after.txt
docker compose exec -T db sh -c 'psql -U postgres -d "$PGDATABASE" -A -t -c \
  "SELECT intkey FROM inventory_archive.tree ORDER BY intkey;"' \
  > ~/upgrade-20260814/orderby-after-tree.txt

# expected, byte-for-byte:
#   ee46a9fa88665c31750a226155639ccd  orderby-after.txt       (783532 rows)
#   46c549091f758157b4789e1417e6a51c  orderby-after-tree.txt  (1722099 rows)
md5sum ~/upgrade-20260814/orderby-after.txt ~/upgrade-20260814/orderby-after-tree.txt
diff ~/upgrade-20260814/orderby-reference.txt      ~/upgrade-20260814/orderby-after.txt \
  && diff ~/upgrade-20260814/orderby-reference-tree.txt ~/upgrade-20260814/orderby-after-tree.txt \
  && echo "COLLATION OK"
```

Also re-check `datcollversion` is still `2.39` — if the new image ships a different glibc,
that number moves and a REINDEX is mandatory even without a logged warning:

```bash
docker compose exec -T db sh -c 'psql -U postgres -d "$PGDATABASE" -c \
  "SELECT datname, datcollversion FROM pg_database;"'
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
   **Also send one real email** (invite or password reset) — login alone does not exercise
   SMTP, and the HARICA/`INSTALL_CERTS` trap in A7 fails *only* on the mail path. A
   `x509: certificate signed by unknown authority` line in `docker compose logs auth`
   is that failure.
3. REST: authenticated read **and write** on `records`; RLS enforced for a non-privileged role.
4. PostGIS: spatial query on plot coordinates returns correct results.
5. Collation: `orderby-after.txt` diff was byte-identical (B3).
6. Storage: upload, download, imgproxy transform. Spot-check `storage.objects` rows against files on disk.
7. Edge functions: invoke one; confirm the `WEBHOOK_TOKEN` path.
8. PowerSync: `/sync/` health, a client syncs and a write round-trips — **without a full re-sync**.
9. TFM-R-Server: `r-plumber` and `r-derived-listener` connect and process (after B8).
10. Studio loads and introspects the schema (the `meta`/PG15 check).
11. Realtime: subscribe, receive a change through the gateway.
12. **New — row cap:** confirm nothing depends on a >1000-row REST response (see A6). Quick
    probe: a request that used to return >1000 rows now comes back with exactly 1000 and a
    partial `Content-Range`, with **no** error status:
    ```bash
    ANON_KEY=$(grep '^ANON_KEY=' .env | cut -d'=' -f2-)
    curl -s -D- -o /dev/null -H "apikey: $ANON_KEY" -H 'Accept-Profile: lookup' \
      'http://127.0.0.1:8000/rest/v1/lookup_municipality?select=code' | grep -i content-range
    # 0-999/* => cap is active (13401 rows exist). Confirm no consumer relies on the full set.
    ```

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
lockdowns. NOT a failure.

**That open question is now answered (2026-08-14): no live consumer is affected.** The only
`/rest/v1/` root fetcher in the codebase is `getSchema()` at `validation.js:1123` — and it is
**dead code, never called** (`grep -rn 'getSchema()'` returns nothing outside its own
definition). Even if it were called, the edge functions authenticate with
`SUPABASE_SERVICE_ROLE_KEY` (`volumes/functions/validation/index.ts:19`), which Envoy's
`rest-v1-openapi-protected` route explicitly allows. Cleared on both counts.

Still unverified, because it lives outside this repo: whether the **Comparison-Tool** or any
generated API-doc tooling introspects `/rest/v1/` with the anon key. Confirm that before
unit 4 — it is the last remaining consumer question.

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

> **⚠️ The A4 dump is a safety net, NOT the rollback path — and it will not restore
> cleanly as-is.** `pg_dump` warned: *"there are circular foreign-key constraints on this
> table"* (`key`). Restoring it requires `pg_restore --disable-triggers` (which needs
> superuser) or dropping the offending constraints first. A plain `pg_restore` will fail
> partway on FK violations.
>
> This does not weaken the plan — **B2's filesystem snapshot is the rollback**, and it is
> a byte copy with no such caveat. But if the dump is ever the last resort, expect this
> and do not discover it under pressure. The A4 `pg_restore --list` check verifies the
> dump is *readable*; it does **not** prove it is *restorable*.
>
> Worth doing outside the window: a one-off restore rehearsal into a throwaway PG 15.14
> container, to convert that assumption into a fact.
