-- ============================================================================
-- ADD updated_at COLUMN + AUTO-UPDATE TRIGGER TO schemas TABLE
-- ============================================================================
-- The schemas table only had created_at, so updates (e.g. from the validation
-- deployment script that re-uploads schema/style/plausibility content) never
-- recorded when a row last changed. This mirrors the setup already used on the
-- records table: a nullable updated_at column plus a BEFORE UPDATE moddatetime
-- trigger that stamps it automatically on every update.
-- ============================================================================
ALTER TABLE "public"."schemas"
ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone NULL;
COMMENT ON COLUMN "public"."schemas"."updated_at" IS 'Timestamp of last update. Maintained automatically by the handle_updated_at trigger.';

-- Backfill existing rows so updated_at is not NULL for previously created schemas.
UPDATE "public"."schemas"
SET "updated_at" = "created_at"
WHERE "updated_at" IS NULL;

-- Auto-update updated_at timestamp on every UPDATE.
DROP TRIGGER IF EXISTS handle_updated_at ON "public"."schemas";
CREATE TRIGGER handle_updated_at BEFORE
UPDATE ON "public"."schemas" FOR EACH ROW
EXECUTE PROCEDURE extensions.moddatetime (updated_at);
