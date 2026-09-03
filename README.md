# TFM Server

## Requirements

Make sure you have the following installed:

- [Git](https://git-scm.com/downloads)
- [Docker](https://docs.docker.com/engine/install/)
- [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started)

## Clone Repository

```bash
git clone --branch version_2 --recurse-submodules -j8 https://github.com/Thuenen-Forest-Ecosystems/TFM-Server.git
cd TFM-Server
cp .env.example .env
```

### Thünen internal seeds repository

For **_Thünen employees only_** with access to _DMZ_, you can clone the internal seeds repository:

```bash
git clone https://git-dmz.thuenen.de/tfm-seeds/intern.git supabase/seeds/intern
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

### Apply database migrations

On a database that was created by the CLI, the migrations in `supabase/migrations`
are applied by

```bash
supabase migration up --local
supabase migration list --local   # shows which files the database has recorded
```

`supabase db reset` also works, but it **drops and rebuilds the database** — never
run it on a local instance that holds a restored production snapshot.

After a schema change, reload the PostgREST cache so the REST API sees new
columns (the migrations in this repository already end with this statement):

```sql
NOTIFY pgrst, 'reload schema';
```

#### When the local database came from a production backup

A restored snapshot brings two things along that break the normal workflow:
production's **migration history** and production's **object ownership**.

##### The history is not an inventory

Production does not keep a migration history, so the restored
`supabase_migrations.schema_migrations` is empty or stale while the schema is
current. The symptom is a history that ends long before objects that visibly
exist, and a failure such as

```
column view_records_details.responsible_read_only_troop does not exist
trigger "update_records_messages_on_records_change_trigger" for relation "records" already exists (SQLSTATE 42710)
```

against a dashboard that works fine on the remote server.

Do **not** reach for `supabase migration up --include-all` on a stale ledger. It
replays every file the history does not list, including the ones the snapshot
already contains. Most are idempotent and pass silently, which is the dangerous
part — the run keeps going until it hits one that is not, and by then it has
re-executed dozens of migrations for no gain. The snapshot already has them.
(`--include-all` becomes the *correct* flag once the ledger is baselined; see
step 3.)

##### Fix it at the source, so the next restore needs none of this

Everything below is only necessary because production ships no history. It does
not have to stay that way:

- `scripts/deploy.sh` records a ledger when the Supabase CLI is present on the
  server (`supabase db push`). Since 2026-09-03 its `psql` fallback records one
  too, and skips versions already recorded — so that path is re-runnable and no
  longer produces a history-less database.
- A production database deployed **before** that needs a one-time baseline, run
  on the server once its schema is confirmed to match the files:

  ```bash
  supabase migration repair --db-url "$DB_URL" --status applied <every version>
  ```

A snapshot taken from a database that keeps its own history needs no
reconciliation at all — `supabase migration up --local` just works. Until every
production database has been baselined, use the procedure below.

##### Ownership: `must be owner of function ... (SQLSTATE 42501)`

The CLI connects as `postgres`. On a CLI-created database `postgres` owns
everything in `public`; in a production dump much of it is owned by
`supabase_admin` — in the current snapshot 41 tables and 60 functions,
`view_records_details`, `record_changes`, `records_messages` and
`handle_record_changes()` among them. `postgres` is neither a superuser nor a
member of `supabase_admin`, so every `CREATE OR REPLACE FUNCTION`, `ALTER TABLE`
or `CREATE OR REPLACE VIEW` on one of those objects fails.

Fix it once, as `supabase_admin` (a superuser). Role memberships live in
`pg_auth_members`, a **cluster-wide** catalog, so this survives `supabase
stop`/`start` and even dropping and recreating the database — it has to be
repeated only if the Postgres volume itself is recreated:

```bash
docker exec supabase_db_supabase \
  psql "postgres://supabase_admin:postgres@127.0.0.1:5432/postgres" \
  -c "GRANT supabase_admin TO postgres;"
```

As with the default URL in `scripts/repair-migration-history.sh`, the password is
the CLI default rather than a secret — the port is bound to loopback only. Note
that `supabase_admin` authenticates with `scram-sha-256` even on the container's
unix socket, so `docker exec … psql -U supabase_admin` prompts for a password;
always give it the full connection URL.

`postgres` is created with `INHERIT`, so it picks the membership up
automatically — no `SET ROLE`, which the CLI would never issue. From here the
standard commands work unchanged in both environments:

```bash
supabase migration up --local     # local
supabase db push --linked         # remote
```

This does give `postgres` full access to `supabase_admin`'s objects (and
`SET ROLE` to a superuser), so keep it to local development databases.
Reversible with `REVOKE supabase_admin FROM postgres;`.

Re-owning the objects instead (`ALTER FUNCTION … OWNER TO postgres`) is the
wrong lever: it is not one function — eight of the ten migrations pending in
the current snapshot touch `supabase_admin`-owned objects, 58 of which live in
`public` and `lookup`. It is also not neutral. 19 `SECURITY DEFINER` functions in
`public` would change the role they execute as, and two views deliberately run
without `security_invoker` — `view_record_workflow_history` is documented in
`20260825000000` as owner-privileged precisely so the workflow code does not
depend on who is looking. And it is the least durable of the options: the next
restore brings production's owners straight back.

##### Procedure

The same five steps every time a snapshot is restored. Steps 1–2 only decide;
nothing is written until step 3.

**0. Grant `supabase_admin` to `postgres`** — once per Postgres volume, as
above. Without it every `CREATE OR REPLACE` on a production-owned object fails
with `42501` and the rest of this is unreadable.

**1. Establish what is actually applied — there is no single cut-off.** A
restored snapshot is *not* a contiguous prefix of the migration list. The dump
is whatever production happened to contain, and production's schema was partly
maintained by hand, so migrations in the middle can be missing while later ones
are present. Treat every migration as an independent question, and ask it two
ways — a file has to pass both.

*(a) Which files conflict with the snapshot?* Replay each unrecorded file
inside a transaction that is rolled back. A file that errors is one the snapshot
already contains, or one a later migration superseded; those get baselined in
step 3. A file that replays cleanly proves nothing on its own — it may be
missing, or merely idempotent.

```bash
LAST=$(docker exec supabase_db_supabase psql -U postgres -d postgres -Atc \
  "select coalesce(max(version), '0') from supabase_migrations.schema_migrations;")
for f in $(ls supabase/migrations | awk -F_ -v l="$LAST" '$1 > l'); do
  out=$( { echo 'BEGIN;'; cat "supabase/migrations/$f"; echo 'ROLLBACK;'; } \
       | docker exec -i supabase_db_supabase psql -U postgres -d postgres \
           -v ON_ERROR_STOP=1 -q 2>&1 )
  printf '%-62s %s\n' "$f" "$(printf '%s' "$out" | grep -i 'ERROR' | head -1 | cut -c1-110)"
done
```

*(b) Which files left no trace?* For every file that replayed cleanly, probe the
objects it creates. This is where the silent holes are, and they are the ones
that cost a day later. Probe through the database container
(`supabase_db_<project-id>`, find it with
`docker ps --format '{{.Names}}' | grep supabase_db`):

```bash
docker exec supabase_db_supabase psql -U postgres -d postgres -At -F' | ' -c "
select 'troop.is_read_only',     exists(select 1 from information_schema.columns where table_schema='public' and table_name='troop' and column_name='is_read_only');
select 'lookup_workflow_status', exists(select 1 from pg_tables where schemaname='lookup' and tablename='lookup_workflow_status');
select 'v_stats_* views',        count(*) from information_schema.views where table_schema='public' and table_name like 'v\_%';
"
```

Three traps here.

`information_schema` and `pg_tables` match names **case-sensitively** —
`lookup_TEMPLATE` is stored as `lookup_template`, so an exact-match probe using
the spelling from the migration files reports a false negative.

A marker that exists proves only that *something* created it. The
`handle_updated_at` trigger on `records` was present in the 2026-09-03 snapshot,
but it ran `extensions.moddatetime`, not the `public.update_updated_at_column()`
that `20260603000001` installs — so the trigger's presence said nothing about
whether that migration had run.

And a present object can still be the wrong version of itself.
`add_plot_ids_to_records` existed, still carrying the `OFFSET total_processed`
bug that `20260618000000` removes. For a `CREATE OR REPLACE FUNCTION` migration,
compare the body, not the name:

```bash
docker exec supabase_db_supabase psql -U postgres -d postgres -Atc \
  "select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'add_plot_ids_to_records';"
```

`supabase db diff --from migrations --to "$DB_URL"` — what
`scripts/repair-migration-history.sh` runs — is the tempting shortcut, and is not
one on a snapshot this far from the files. On 2026-09-03 it emitted 1481
structural statements, nearly all of them the differ restating objects that in
fact match, so it could not say which migration was missing. Run it *after*
reconciling, as a check that the database stayed reconciled.

**2. Clear the two blockers that recur on every snapshot.**

*A foreign key that cannot validate.* A partial dump leaves rows pointing at
parents it did not bring along, and `ADD CONSTRAINT` validates the whole table.
Count them first; if they are dump artefacts, add the constraint `NOT VALID` —
it enforces every INSERT and UPDATE from then on and only skips the existing
rows. Run the migration's statements by hand with `NOT VALID` appended, then
record it in step 3.

```bash
docker exec supabase_db_supabase psql -U postgres -d postgres -Atc \
  "select count(*) from public.records r
    where r.plot_id is not null
      and not exists (select 1 from inventory_archive.plot p where p.id = r.plot_id);"
```

Validate later, once the data is complete:
`ALTER TABLE public.records VALIDATE CONSTRAINT records_plot_id_fkey;`

*A view that cannot be replaced.* `CREATE OR REPLACE VIEW` can neither rename nor
drop a column, so any view the snapshot holds in a different shape blocks its
migration (`cannot change name of view column ...`, `cannot drop columns from
view`). Drop it and let the migration rebuild it — check for dependents first,
and never use `CASCADE` without reading what it would take with it:

```bash
docker exec supabase_db_supabase psql -U postgres -d postgres -Atc \
  "select distinct d.relname from pg_depend dep
     join pg_rewrite r on r.oid = dep.objid
     join pg_class d on d.oid = r.ev_class
    where dep.refobjid = 'public.v_stats_troop_completed_latest'::regclass
      and d.relname <> 'v_stats_troop_completed_latest';"
```

**3. Baseline only what step 1 verified as applied**, so the CLI stops replaying
the snapshot's own migrations. This step is not optional: `migration up` applies
everything newer than the newest *recorded* version, so with a ledger that stops
in March 2025 even a plain `up` re-runs the whole year — which is how you get
`trigger ... already exists (SQLSTATE 42710)`.

Mark them with the CLI rather than an `INSERT`; it needs no `psql`:

```bash
supabase migration repair --local --status applied 20260206000000 20260224000000 ...
```

Do **not** baseline by cut-off. Marking a migration applied that never ran means
its content never lands, and nothing will ever tell you — that is the failure
mode this whole procedure exists to prevent.

**4. Apply the rest.** The pending files are now all *older* than the newest
recorded version, so a plain `up` refuses them:

```
Found local migration files to be inserted before the last migration on remote database.
```

That is expected. `--include-all` is the right flag here — and only here: the
ledger is honest now, so it applies exactly the files step 1 identified as
missing. Read the list it prints and check it matches before letting it run.

```bash
supabase migration list --local              # confirm what is still pending
supabase migration up --local --include-all
```

If a single file has to run outside the CLI, pipe it into the container, one
transaction per file, and then record it:

```bash
docker exec -i supabase_db_supabase \
  psql "postgres://supabase_admin:postgres@127.0.0.1:5432/postgres" \
  -v ON_ERROR_STOP=1 --single-transaction \
  < supabase/migrations/20260903000000_view_records_details_ci2027.sql

supabase migration repair --local --status applied 20260903000000
```

**5. Verify.** Every file recorded, nothing pending, and the objects the
formerly-missing migrations were supposed to create actually there:

```bash
supabase migration list --local
```

##### Worked example — the snapshot of 2026-09-03

51 migration files, ledger stopped at `20250312143840`, 34 unrecorded. 28 of
those the snapshot already had. Seven had never run:

| Migration | What was missing |
| --- | --- |
| `20260603000001` | `update_updated_at_column()`; `handle_updated_at` on `records` still ran `extensions.moddatetime` |
| `20260605120000` | `organization_admin_sync_selections` |
| `20260617000000` | all four `records`/`record_changes` → `inventory_archive` foreign keys |
| `20260618000000` | function present, still carrying the `OFFSET total_processed` bug |
| `20260625000000` | `guard_records_properties_admin` function and trigger |
| `20260702000000` | 12 of the 13 `v_stats_*` views; the 13th had an older shape |
| `20260706120000` | `handle_updated_at` on `schemas` |

`20260224000000` had applied only its four `inventory_archive` constraints — the
other four are exactly the ones `20260617000000` replaces with `ON DELETE
RESTRICT`, so baselining it and applying `20260617000000` reached the right end
state. Those four went in `NOT VALID`: one `records` row and 289
`record_changes` rows referenced plots and clusters the dump had not brought
along. `v_stats_troop_completed_latest` had to be dropped before
`20260702000000` could rebuild it.

Nothing was reloaded and no data was touched — 122,321 records and 17,316
messages before and after.

## Sync Service

### Start Powersync

```bash
docker compose --env-file .env.local -f docker-compose.local.yaml up -d
```

### Stop Powersync

```bash
docker compose --env-file .env.local -f docker-compose.local.yaml down
```

## Remote Server

```bash
docker compose start
```
