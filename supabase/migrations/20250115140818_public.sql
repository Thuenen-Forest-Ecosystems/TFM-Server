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
INSERT INTO "public"."schemas" 
("interval_name", "title", "description", "is_visible", "bucket_schema_file_name", "bucket_plausability_file_name") 
VALUES ('ci2027', 'CI 2027', 'CI 2027', true, 'ci2027_schema_0.0.1.json', 'ci2027_plausability_0.0.1.js');

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
    type text NOT NULL DEFAULT 'organization'::text, -- 'root', 'state', 'provider', 'organization'
    is_root boolean NOT NULL DEFAULT false,
    deleted boolean NOT NULL DEFAULT false,
    can_admin_troop boolean NOT NULL DEFAULT false,
    can_admin_organization boolean NOT NULL DEFAULT false
);

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- POLICIES: organizations
-- ============================================================================
-- Users can access organizations they are members of or parent organizations
-- ============================================================================

-- SELECT: View organizations user has access to
CREATE POLICY "Enable all access for authenticated users with same parent_organization_id"
ON organizations
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.users_permissions up
        WHERE up.user_id = auth.uid()
          AND (up.organization_id = organizations.id 
               OR up.organization_id = organizations.parent_organization_id)
    )
);

-- ALL: Modify organizations user has access to
CREATE POLICY "Enable all access for authenticated users with same organization_id or parent_organization_id"
ON organizations
AS PERMISSIVE
FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.users_permissions up
        WHERE up.user_id = auth.uid()
          AND (up.organization_id = organizations.id 
               OR up.organization_id = organizations.parent_organization_id)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM public.users_permissions up
        WHERE up.user_id = auth.uid()
          AND (up.organization_id = organizations.id 
               OR up.organization_id = organizations.parent_organization_id)
    )
);

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

CREATE POLICY "Enable all access for authenticated users with same organization_id"
ON public.users_profile
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (true);

-- ============================================================================
-- FUNCTION: handle_new_user_profile (TRIGGER FUNCTION)
-- ============================================================================
-- Automatically creates user profile when email is confirmed
-- Extracts organization_id and name from raw_user_meta_data
-- ============================================================================

DROP FUNCTION IF EXISTS public.handle_new_user_profile();
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  domain_part text;
  org_id uuid;
  user_full_name text;
BEGIN
  -- Get the organization_id and name from auth.users.raw_user_meta_data
  IF new.raw_user_meta_data IS NOT NULL THEN
    SELECT (new.raw_user_meta_data::jsonb ->> 'organization_id')::uuid, 
           (new.raw_user_meta_data::jsonb ->> 'name') 
    INTO org_id, user_full_name;

    -- Validate organization_id
    IF org_id IS NOT NULL THEN
      PERFORM 1 FROM public.organizations WHERE id = org_id;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid organization_id: %', org_id;
      END IF;
    END IF;
  ELSE
    org_id := NULL;
    user_full_name := NULL;
  END IF;

  -- Insert or update the user's profile
  INSERT INTO public.users_profile (id, email, organization_id, name) 
  VALUES (new.id, new.email, org_id, user_full_name)
  ON CONFLICT (id) DO UPDATE 
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
AFTER UPDATE OF email_confirmed_at ON auth.users
FOR EACH ROW
WHEN (old.email_confirmed_at IS NULL AND new.email_confirmed_at IS NOT NULL)
EXECUTE PROCEDURE public.handle_new_user_profile();

-- ============================================================================
-- TABLE: troop
-- ============================================================================
-- Field teams assigned to collect data from plots
-- Each troop belongs to an organization and can have multiple users
-- ============================================================================

CREATE TABLE IF NOT EXISTS troop (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    name text NOT NULL,
    organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_ids uuid[] NOT NULL DEFAULT '{}',
    is_control_troop boolean NOT NULL DEFAULT false,
    deleted boolean NOT NULL DEFAULT false
);

ALTER TABLE troop ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- POLICIES: troop
-- ============================================================================
-- Users can access troops within their organizations
-- ============================================================================

DROP POLICY IF EXISTS "Enable all access for authenticated users of same organization_id" ON troop;
CREATE POLICY "Enable all access for authenticated users of same organization_id"
ON troop
AS PERMISSIVE
FOR ALL
TO authenticated
USING (
    organization_id IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    )
)
WITH CHECK (
    organization_id IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    )
);

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
    record_ids uuid[] NOT NULL DEFAULT '{}',
    cluster_ids uuid[] NOT NULL DEFAULT '{}'
);

ALTER TABLE organizations_lose ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- POLICIES: organizations_lose
-- ============================================================================
-- Users can access lose within their organizations
-- ============================================================================

DROP POLICY IF EXISTS "Lose Enable all access for authenticated users of same organization_id" ON organizations_lose;
CREATE POLICY "Lose Enable all access for authenticated users of same organization_id"
ON organizations_lose
AS PERMISSIVE
FOR ALL
TO authenticated
USING (
    organization_id IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    )
)
WITH CHECK (
    organization_id IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    )
);

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
-- POLICIES: users_permissions
-- ============================================================================
-- All authenticated users can view permissions (for collaboration)
-- ============================================================================

DROP POLICY IF EXISTS "Enable users with own role equals organization_admin and same organization_id" ON "public"."users_permissions";
CREATE POLICY "Enable users with own role equals organization_admin and same organization_id"
ON "public"."users_permissions"
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (true);

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
    "responsible_administration" uuid REFERENCES organizations(id) ON DELETE SET NULL,
    "responsible_state" uuid REFERENCES organizations(id) ON DELETE SET NULL,
    "responsible_provider" uuid REFERENCES organizations(id) ON DELETE SET NULL,
    "responsible_troop" uuid REFERENCES troop(id) ON DELETE SET NULL,
    
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

-- Auto-update updated_at timestamp
CREATE TRIGGER handle_updated_at BEFORE UPDATE ON records
FOR EACH ROW EXECUTE PROCEDURE extensions.moddatetime (updated_at);

COMMENT ON TABLE "records" IS 'Forest inventory plot data collection records';

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
-- POLICIES: records
-- ============================================================================
-- Users can access records assigned to their organizations or troops
-- Root organization users can access all records
-- ============================================================================

-- SELECT: View records user has access to
CREATE POLICY "Enable SELECT access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop"
ON "records"
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
    -- Root organization users can see all records
    EXISTS (
        SELECT 1
        FROM public.organizations org
        JOIN public.users_permissions up ON org.id = up.organization_id
        WHERE up.user_id = auth.uid() AND org.type = 'root'
    ) 
    OR
    -- Users can see records assigned to their organizations
    responsible_state IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_provider IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_troop IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
);

-- UPDATE: Modify records user has access to
CREATE POLICY "Enable UPDATE access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop"
ON "records"
AS PERMISSIVE
FOR UPDATE
TO authenticated
USING (
    -- Root organization or admin users
    EXISTS (
        SELECT 1
        FROM public.organizations org
        JOIN public.users_permissions up ON org.id = up.organization_id
        WHERE up.user_id = auth.uid() AND org.type = 'root'
    )
    OR EXISTS (
        SELECT 1 FROM public.users_profile prof
        WHERE prof.id = auth.uid() AND prof.is_admin = true
    )
    OR
    -- Users with organizational access
    responsible_state IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_provider IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_troop IN (
        SELECT t.id FROM public.troop t
        JOIN public.users_permissions up ON t.organization_id = up.organization_id
        WHERE up.user_id = auth.uid()
    )
)
WITH CHECK (
    -- Same constraints for updates
    EXISTS (
        SELECT 1
        FROM public.organizations org
        JOIN public.users_permissions up ON org.id = up.organization_id
        WHERE up.user_id = auth.uid() AND org.type = 'root'
    )
    OR EXISTS (
        SELECT 1 FROM public.users_profile prof
        WHERE prof.id = auth.uid() AND prof.is_admin = true
    )
    OR
    responsible_state IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_provider IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_troop IN (
        SELECT t.id FROM public.troop t
        JOIN public.users_permissions up ON t.organization_id = up.organization_id
        WHERE up.user_id = auth.uid()
    )
);

-- ============================================================================
-- TABLE: record_changes
-- ============================================================================
-- Audit trail for records - stores history of all changes
-- Automatically populated by trigger when records are updated
-- ============================================================================

CREATE TABLE public.record_changes (LIKE public.records INCLUDING ALL);

-- Add reference to original record
ALTER TABLE public.record_changes ADD COLUMN record_id UUID;
ALTER TABLE public.record_changes ADD CONSTRAINT record_changes_id UNIQUE (id);
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

-- ============================================================================
-- POLICIES: record_changes
-- ============================================================================
-- Same access rules as records table for viewing audit history
-- ============================================================================

CREATE POLICY "record_changes: Enable SELECT access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop"
ON "record_changes"
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
    -- Root organization users can see all changes
    EXISTS (
        SELECT 1
        FROM public.organizations org
        JOIN public.users_permissions up ON org.id = up.organization_id
        WHERE up.user_id = auth.uid() AND org.type = 'root'
    )
    OR
    -- Users can see changes for records assigned to their organizations
    responsible_state IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_provider IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
    OR responsible_troop IN (SELECT organization_id FROM public.users_permissions WHERE user_id = auth.uid())
);

-- Link records to their change history
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "record_changes_id" uuid NULL REFERENCES public.record_changes(id) ON DELETE SET NULL;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
