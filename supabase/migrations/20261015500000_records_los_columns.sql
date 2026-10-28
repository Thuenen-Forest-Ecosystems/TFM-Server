-- records.*_los / record_changes.*_los: Spalten, die bisher nur in der Datenbank existierten.
-- 20261016000000_prod_only_objects legt Trigger auf records.administration_los, state_los,
-- provider_los und troop_los an, aber keine Migration legt die Spalten an -- eine neu aufgesetzte
-- Datenbank brach dort ab (column "administration_los" of relation "records" does not exist).
-- Definitionen 1:1 aus Prod (backups/db_20260930_174251.dump): uuid, auf records mit FK auf
-- organizations_lose ON DELETE SET NULL; record_changes traegt die Spalten ohne FK.
-- Auf Prod und einem Prod-Abzug ein No-op, mehrfach ausfuehrbar.

ALTER TABLE public.records
    ADD COLUMN IF NOT EXISTS administration_los uuid,
    ADD COLUMN IF NOT EXISTS state_los uuid,
    ADD COLUMN IF NOT EXISTS provider_los uuid,
    ADD COLUMN IF NOT EXISTS troop_los uuid;

ALTER TABLE public.record_changes
    ADD COLUMN IF NOT EXISTS administration_los uuid,
    ADD COLUMN IF NOT EXISTS state_los uuid,
    ADD COLUMN IF NOT EXISTS provider_los uuid,
    ADD COLUMN IF NOT EXISTS troop_los uuid;

DO $$
DECLARE
    col text;
BEGIN
    FOREACH col IN ARRAY ARRAY['administration_los', 'state_los', 'provider_los', 'troop_los'] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conrelid = 'public.records'::regclass AND conname = 'records_' || col || '_fkey'
        ) THEN
            EXECUTE format(
                'ALTER TABLE public.records ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES public.organizations_lose(id) ON DELETE SET NULL',
                'records_' || col || '_fkey', col);
        END IF;
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
