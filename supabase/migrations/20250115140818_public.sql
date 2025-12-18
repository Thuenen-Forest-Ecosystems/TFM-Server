-- ============================================================================
-- PUBLIC SCHEMA MIGRATION
-- ============================================================================
-- Creates tables and policies for the public schema
-- Includes: schemas, organizations, users, permissions, troops, and records
-- ============================================================================
SET search_path TO public;
-- ============================================================================
-- TABLE: schemas
-- ============================================================================
-- Stores validation schemas for different inventory intervals
-- Each schema defines the structure and rules for data validation
-- ============================================================================
CREATE TABLE IF NOT EXISTS "public"."schemas" (
  "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL,
  "created_at" timestamp with time zone not null default now(),
  "interval_name" text default 'ci2027' not null references "lookup"."lookup_interval" (code) on delete restrict on update restrict,
  "title" text not null,
  "description" text,
  "is_visible" boolean not null default false,
  "bucket_schema_file_name" text,
  "bucket_plausability_file_name" text,
  "schema" json,
  "version" integer,
  "directory" text
);
ALTER TABLE "public"."schemas" ENABLE ROW LEVEL SECURITY;
-- Insert default CI 2027 schema
INSERT INTO "public"."schemas" (
    "interval_name",
    "title",
    "description",
    "is_visible",
    "bucket_schema_file_name",
    "bucket_plausability_file_name"
  )
VALUES (
    'ci2027',
    'CI 2027',
    'CI 2027',
    true,
    'ci2027_schema_0.0.1.json',
    'ci2027_plausability_0.0.1.js'
  );
-- ============================================================================
-- TABLE: organizations
-- ============================================================================
-- Hierarchical organization structure (root -> state -> provider -> troop)
-- Supports federal states, forest offices, and other organizational units
-- ============================================================================
CREATE TABLE IF NOT EXISTS organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid DEFAULT auth.uid() REFERENCES auth.users(id),
  parent_organization_id uuid NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name text NULL,
  entityName text NULL,
  description text NULL,
  type text NOT NULL DEFAULT 'organization'::text,
  -- 'root', 'state', 'provider', 'organization'
  is_root boolean NOT NULL DEFAULT false,
  deleted boolean NOT NULL DEFAULT false,
  can_admin_troop boolean NOT NULL DEFAULT false,
  can_admin_organization boolean NOT NULL DEFAULT false
);
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
-- ============================================================================
-- TABLE: users_profile
-- ============================================================================
-- Extended user profile information linked to auth.users
-- Stores admin status, organization membership, and user details
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.users_profile (
  id uuid PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  email text NOT NULL,
  name text NULL,
  state_responsible smallint NULL,
  organization_id uuid NULL REFERENCES organizations(id),
  is_admin boolean NOT NULL DEFAULT false,
  is_database_admin boolean NOT NULL DEFAULT false,
  is_organization_admin boolean NOT NULL DEFAULT false
);
ALTER TABLE public.users_profile ENABLE ROW LEVEL SECURITY;
-- ============================================================================
-- POLICIES: users_profile
-- ============================================================================
-- Users can view all profiles (for collaboration purposes)
-- ============================================================================
CREATE POLICY "Enable all access for authenticated users with same organization_id" ON public.users_profile AS PERMISSIVE FOR
SELECT TO authenticated USING (true);
-- ============================================================================
-- FUNCTION: handle_new_user_profile (TRIGGER FUNCTION)
-- ============================================================================
-- Automatically creates user profile when email is confirmed
-- Extracts organization_id and name from raw_user_meta_data
-- ============================================================================
DROP FUNCTION IF EXISTS public.handle_new_user_profile();
CREATE OR REPLACE FUNCTION public.handle_new_user_profile() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE domain_part text;
org_id uuid;
user_full_name text;
BEGIN -- Get the organization_id and name from auth.users.raw_user_meta_data
IF new.raw_user_meta_data IS NOT NULL THEN
SELECT (
    new.raw_user_meta_data::jsonb->>'organization_id'
  )::uuid,
  (new.raw_user_meta_data::jsonb->>'name') INTO org_id,
  user_full_name;
-- Validate organization_id
IF org_id IS NOT NULL THEN PERFORM 1
FROM public.organizations
WHERE id = org_id;
IF NOT FOUND THEN RAISE EXCEPTION 'Invalid organization_id: %',
org_id;
END IF;
END IF;
ELSE org_id := NULL;
user_full_name := NULL;
END IF;
-- Insert or update the user's profile
INSERT INTO public.users_profile (id, email, organization_id, name)
VALUES (new.id, new.email, org_id, user_full_name) ON CONFLICT (id) DO
UPDATE
SET email = EXCLUDED.email,
  organization_id = EXCLUDED.organization_id,
  name = EXCLUDED.name;
RETURN new;
END;
$$;
-- ============================================================================
-- TRIGGER: on_auth_user_created
-- ============================================================================
-- Creates user profile when email is confirmed
-- ============================================================================
CREATE TRIGGER on_auth_user_created
AFTER
UPDATE OF email_confirmed_at ON auth.users FOR EACH ROW
  WHEN (
    old.email_confirmed_at IS NULL
    AND new.email_confirmed_at IS NOT NULL
  ) EXECUTE PROCEDURE public.handle_new_user_profile();
-- ============================================================================
-- TABLE: troop
-- ============================================================================
-- Field teams assigned to collect data from plots
-- Each troop belongs to an organization and can have multiple users
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.troop (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  name text NOT NULL,
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_ids uuid [] NOT NULL DEFAULT '{}',
  is_control_troop boolean NOT NULL DEFAULT false,
  deleted boolean NOT NULL DEFAULT false
);
ALTER TABLE troop ENABLE ROW LEVEL SECURITY;
-- ============================================================================
-- TABLE: organizations_lose
-- ============================================================================
-- Assignment units (German: "Lose") for organizing plot collections
-- Links organizations, troops, and records for work distribution
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.organizations_lose (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  name text NOT NULL,
  description text,
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  responsible_organization_id uuid NULL REFERENCES organizations(id) ON DELETE CASCADE,
  troop_id uuid NULL REFERENCES troop(id) ON DELETE CASCADE,
  record_ids uuid [] NOT NULL DEFAULT '{}',
  cluster_ids uuid [] NOT NULL DEFAULT '{}'
);
ALTER TABLE organizations_lose ENABLE ROW LEVEL SECURITY;
-- ============================================================================
-- TABLE: users_permissions
-- ============================================================================
-- Junction table linking users to organizations they can access
-- Defines user access rights across organizational hierarchy
-- ============================================================================
CREATE TABLE IF NOT EXISTS "public"."users_permissions" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "user_id" uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  "organization_id" uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  "created_by" uuid DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  "troop_id" uuid REFERENCES public.troop(id) ON DELETE CASCADE,
  "is_organization_admin" boolean NOT NULL DEFAULT false,
  CONSTRAINT unique_user_organization UNIQUE (user_id, organization_id),
  CONSTRAINT fk_users_permissions_users_profile FOREIGN KEY (user_id) REFERENCES public.users_profile(id) ON DELETE CASCADE
);
ALTER TABLE "public"."users_permissions" ENABLE ROW LEVEL SECURITY;
-- ============================================================================
-- TABLE: records
-- ============================================================================
-- Main data collection records for forest inventory plots
-- Links to plots, schemas, organizations, and troops for data management
-- ============================================================================
CREATE TABLE IF NOT EXISTS "records" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NULL,
  "updated_by" uuid NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  -- Plot reference
  "plot_id" uuid NOT NULL REFERENCES inventory_archive.plot(id) UNIQUE,
  "cluster_id" uuid NULL REFERENCES inventory_archive.cluster(id),
  "cluster_name" integer NULL,
  "plot_name" smallint NULL,
  -- Data and validation
  "properties" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "previous_properties" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "previous_properties_updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  "schema_id" uuid NULL REFERENCES public.schemas(id),
  "schema_name" text NULL DEFAULT 'ci2027',
  -- Validation results
  "is_valid" boolean NULL DEFAULT NULL,
  "is_plausible" boolean NULL DEFAULT NULL,
  "validation_errors" jsonb NULL,
  "plausibility_errors" jsonb NULL,
  "validated_at" timestamp with time zone NULL,
  -- Responsibility assignment
  "responsible_administration" uuid REFERENCES organizations(id) ON DELETE
  SET NULL,
    "responsible_state" uuid REFERENCES organizations(id) ON DELETE
  SET NULL,
    "responsible_provider" uuid REFERENCES organizations(id) ON DELETE
  SET NULL,
    "responsible_troop" uuid REFERENCES troop(id) ON DELETE
  SET NULL,
    -- "current_troop_members" uuid[] NULL DEFAULT '{}',
    -- Completion tracking
    "completed_at_troop" timestamp with time zone NULL,
    "completed_at_state" timestamp with time zone NULL,
    "completed_at_administration" timestamp with time zone NULL,
    -- Additional fields
    "message" text NULL,
    "note" text NULL,
    "record_changes_id" uuid NULL,
    CONSTRAINT unique_cluster_plot UNIQUE (cluster_name, plot_name)
);
ALTER TABLE "records"
ADD COLUMN IF NOT EXISTS "current_troop_members" uuid [] NULL DEFAULT '{}';
ALTER TABLE "records"
ADD COLUMN IF NOT EXISTS "previous_position_data" jsonb NULL DEFAULT '{}'::jsonb;
COMMENT ON COLUMN "records"."previous_position_data" IS 'Position data from previous inventory intervals stored by interval_name. Contains all fields from inventory_archive.position table.';
ALTER TABLE "records"
ADD COLUMN IF NOT EXISTS "local_updated_at" timestamp with time zone NULL;
COMMENT ON COLUMN "public"."records"."local_updated_at" IS 'Timestamp of last local modification before sync. NULL means no pending changes. Used to determine if record has unsynced local changes.';
ALTER TABLE "records"
ADD COLUMN IF NOT EXISTS "is_to_be_recorded_by_troop" boolean NOT NULL DEFAULT true;
--not nullable default true
COMMENT ON COLUMN "public"."records"."is_to_be_recorded_by_troop" IS 'Indicates if the plot is marked to be recorded in the current inventory interval. TRUE means it should be recorded. FALSE means it should not be recorded.';
-- ============================================================================
-- Auto-update updated_at timestampop_members contains only valid auth.users IDs
-- ALTER TABLE "records" ADD CONSTRAINT check_current_troop_members_valid_users
-- CHECK (
--     current_troop_members IS NULL OR
--     NOT EXISTS (
--         SELECT 1 FROM unnest(current_troop_members) AS member_id
--         WHERE NOT EXISTS (SELECT 1 FROM auth.users WHERE id = member_id)
--     )
-- );
-- Auto-update updated_at timestamp
CREATE TRIGGER handle_updated_at BEFORE
UPDATE ON records FOR EACH ROW EXECUTE PROCEDURE extensions.moddatetime (updated_at);
COMMENT ON TABLE "records" IS 'Forest inventory plot data collection records';
COMMENT ON COLUMN "records"."current_troop_members" IS 'Array of user IDs currently assigned to work on this record. All IDs must exist in auth.users table.';
-- ============================================================================
-- INDEXES: records
-- ============================================================================
-- Performance optimization for common query patterns
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_records_plot_id ON records(plot_id);
CREATE INDEX IF NOT EXISTS idx_records_schema_id ON records(schema_id);
CREATE INDEX IF NOT EXISTS idx_records_responsible_state ON records(responsible_state);
CREATE INDEX IF NOT EXISTS idx_records_responsible_provider ON records(responsible_provider);
CREATE INDEX IF NOT EXISTS idx_records_responsible_troop ON records(responsible_troop);
CREATE INDEX IF NOT EXISTS idx_records_cluster_id ON records(cluster_id);
CREATE INDEX IF NOT EXISTS idx_records_schema_name ON records(schema_name);
ALTER TABLE public.records ENABLE ROW LEVEL SECURITY;
-- ============================================================================
-- TABLE: record_changes
-- ============================================================================
-- Audit trail for records - stores history of all changes
-- Automatically populated by trigger when records are updated
-- ============================================================================
CREATE TABLE public.record_changes (LIKE public.records INCLUDING ALL);
-- Add reference to original record
ALTER TABLE public.record_changes
ADD COLUMN record_id UUID;
ALTER TABLE public.record_changes
ADD CONSTRAINT record_changes_id UNIQUE (id);
ALTER TABLE public.record_changes DROP CONSTRAINT IF EXISTS record_changes_plot_id_key;
COMMENT ON TABLE public.record_changes IS 'Audit trail for records table - stores historical changes';
-- ============================================================================
-- INDEXES: record_changes
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_record_changes_plot_id ON public.record_changes(plot_id);
CREATE INDEX IF NOT EXISTS idx_record_changes_schema_id ON public.record_changes(schema_id);
CREATE INDEX IF NOT EXISTS idx_record_changes_responsible_state ON public.record_changes(responsible_state);
CREATE INDEX IF NOT EXISTS idx_record_changes_responsible_provider ON public.record_changes(responsible_provider);
CREATE INDEX IF NOT EXISTS idx_record_changes_responsible_troop ON public.record_changes(responsible_troop);
CREATE INDEX IF NOT EXISTS idx_record_changes_cluster_id ON public.record_changes(cluster_id);
CREATE INDEX IF NOT EXISTS idx_record_changes_schema_name ON public.record_changes(schema_name);
CREATE INDEX IF NOT EXISTS idx_record_changes_record_id ON public.record_changes(record_id);
ALTER TABLE public.record_changes ENABLE ROW LEVEL SECURITY;
-- Link records to their change history
ALTER TABLE "records"
ADD COLUMN IF NOT EXISTS "record_changes_id" uuid NULL REFERENCES public.record_changes(id) ON DELETE
SET NULL;
-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
-- ============================================================================
-- TABLE: troop_members
-- ============================================================================
-- Junction table that mirrors troop.user_ids array
-- Automatically synced via triggers for PowerSync compatibility
-- ============================================================================
-- Drop the view first
DROP VIEW IF EXISTS public.troop_members;
-- Create the real table
CREATE TABLE IF NOT EXISTS public.troop_members (
  troop_id uuid NOT NULL REFERENCES public.troop(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  PRIMARY KEY (troop_id, user_id)
);
-- Create indexes
CREATE INDEX IF NOT EXISTS idx_troop_members_user ON public.troop_members(user_id);
CREATE INDEX IF NOT EXISTS idx_troop_members_troop ON public.troop_members(troop_id);
-- Enable RLS
ALTER TABLE public.troop_members ENABLE ROW LEVEL SECURITY;
-- Policy: Users can view all memberships (needed for collaboration)
CREATE POLICY "Users can view troop memberships" ON public.troop_members FOR
SELECT TO authenticated USING (true);
COMMENT ON TABLE public.troop_members IS 'Flattened troop memberships from troop.user_ids array - automatically synced via triggers';
-- ============================================================================
-- FUNCTION: sync_troop_members_from_array
-- ============================================================================
-- Syncs troop_members table when troop.user_ids changes
-- ============================================================================
CREATE OR REPLACE FUNCTION sync_troop_members_from_array() RETURNS TRIGGER AS $$ BEGIN IF TG_OP = 'DELETE' THEN -- Remove all members when troop is deleted
DELETE FROM public.troop_members
WHERE troop_id = OLD.id;
RETURN OLD;
ELSIF TG_OP = 'UPDATE'
OR TG_OP = 'INSERT' THEN -- Delete existing members
DELETE FROM public.troop_members
WHERE troop_id = NEW.id;
-- Insert new members from array
IF NEW.user_ids IS NOT NULL
AND array_length(NEW.user_ids, 1) > 0 THEN
INSERT INTO public.troop_members (troop_id, user_id)
SELECT NEW.id,
  unnest(NEW.user_ids) ON CONFLICT DO NOTHING;
END IF;
RETURN NEW;
END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- ============================================================================
-- TRIGGER: Keep troop_members in sync with troop.user_ids
-- ============================================================================
DROP TRIGGER IF EXISTS troop_members_sync ON public.troop;
CREATE TRIGGER troop_members_sync
AFTER
INSERT
  OR
UPDATE OF user_ids
  OR DELETE ON public.troop FOR EACH ROW EXECUTE FUNCTION sync_troop_members_from_array();
-- ============================================================================
-- POPULATE: Initial data from existing troops
-- ============================================================================
INSERT INTO public.troop_members (troop_id, user_id)
SELECT t.id,
  unnest(t.user_ids)
FROM public.troop t
WHERE t.user_ids IS NOT NULL
  AND array_length(t.user_ids, 1) > 0 ON CONFLICT DO NOTHING;