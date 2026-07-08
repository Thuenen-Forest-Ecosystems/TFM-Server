-- ============================================================================
-- ADD local_updated_at COLUMN TO records TABLE
-- ============================================================================
-- This column tracks when a record was last modified on the local device
-- before being synced to the server. Used to determine sync status in the app.
-- 
-- Sync Logic:
-- - local_updated_at IS NULL: Never modified locally (synced)
-- - local_updated_at <= updated_at: Changes synced to server
-- - local_updated_at > updated_at: Local changes pending upload
-- ============================================================================
ALTER TABLE "public"."records"
ADD COLUMN IF NOT EXISTS "local_updated_at" timestamp with time zone NULL;
COMMENT ON COLUMN "public"."records"."local_updated_at" IS 'Timestamp of last local modification before sync. NULL means no pending changes. Used to determine if record has unsynced local changes.';
-- Create index for efficient sync status queries
CREATE INDEX IF NOT EXISTS idx_records_local_updated_at ON records(local_updated_at);
-- Note: This column should be updated by the client app (PowerSync) when making local changes
-- The app should:
-- 1. Set local_updated_at = NOW() when making local changes
-- 2. Clear local_updated_at = NULL after successful sync
-- 3. Compare local_updated_at with updated_at to determine sync status