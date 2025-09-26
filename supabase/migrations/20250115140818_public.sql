SET search_path TO public;

create table IF NOT EXISTS "public"."schemas" (
    "created_at" timestamp with time zone not null default now(),
    "interval_name" text default 'ci2027' not null references "lookup"."lookup_interval" (code) on delete restrict on update restrict,
    "title" text not null,
    "description" text,
    "is_visible" boolean not null default false,
    "bucket_schema_file_name" text,
    "bucket_plausability_file_name" text,
    "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL,
    "schema" json,
    "version" integer,
    "directory" text
);


alter table "public"."schemas" enable row level security;

-- add first schema
insert into "public"."schemas" 
("interval_name", "title", "description", "is_visible", "bucket_schema_file_name", "bucket_plausability_file_name") values ('ci2027', 'CI 2027', 'CI 2027', true, 'ci2027_schema_0.0.1.json', 'ci2027_plausability_0.0.1.js');



--- Add Organizations table that are allowed to create auth.users
CREATE TABLE IF NOT EXISTS organizations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    apex_domain text NULL,
    created_by uuid DEFAULT auth.uid() REFERENCES auth.users(id),
    state_responsible smallint NULL REFERENCES lookup.lookup_state (code),
    parent_organization_id uuid NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name text NULL,
    can_admin_troop boolean NOT NULL DEFAULT false,
    can_admin_organization boolean NOT NULL DEFAULT false
);

ALTER TABLE organizations ADD COLUMN IF NOT EXISTS "deleted" boolean NOT NULL DEFAULT false;

alter table "public"."organizations" add column IF NOT EXISTS "entityName" text;

alter table "public"."organizations" add column IF NOT EXISTS "is_root" boolean not null default false;

alter table "public"."organizations" add column IF NOT EXISTS "type" text not null default 'organization'::text;

-- INSERT INTO organizations (apex_domain, name) VALUES ('@thuenen.de', 'Thünen-Institut');

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;


create table if not exists "public"."users_permissions" (
    "id" uuid not null default gen_random_uuid(),
    "created_at" timestamp with time zone not null default now(),
    "user_id" uuid not null,
    "organization_id" uuid not null,
    "write_access" boolean not null default false,
    "created_by" uuid default auth.uid(),
    "role" text
);

ALTER TABLE public.users_permissions ADD CONSTRAINT unique_user_organization UNIQUE (user_id, organization_id);

alter table "public"."users_permissions" enable row level security;

-- Create a policy to allow authenticated users to access users_permissions
DROP POLICY IF EXISTS "Enable users with own role equals organization_admin and same organization_id" ON "public"."users_permissions";
CREATE POLICY "Enable users with own role equals organization_admin and same organization_id"
ON "public"."users_permissions"
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
    true
);

DROP POLICY IF EXISTS "Enable all access for authenticated users with same parent_organization_id" ON organizations;
CREATE POLICY "Enable all access for authenticated users with same parent_organization_id"
ON organizations
AS PERMISSIVE
FOR Select
TO authenticated
USING (
    -- Allow users to access organizations where they are a member
    EXISTS (
        SELECT 1
        FROM public.users_permissions up
        WHERE up.user_id = auth.uid()
          AND up.organization_id = organizations.id
    ) OR
    -- Allow users to access organizations where they are a member of the parent organization
    EXISTS (
        SELECT 1
        FROM public.users_permissions up
        WHERE up.user_id = auth.uid()
          AND up.organization_id = organizations.parent_organization_id
    )
);
-- Create a policy to allow authenticated users to insert update and delete organizations where organization_id is the same as their own organization_id or parent_organization_id
DROP POLICY IF EXISTS "Enable all access for authenticated users with same organization_id or parent_organization_id" ON organizations;
CREATE POLICY "Enable all access for authenticated users with same organization_id or parent_organization_id"
ON organizations
AS PERMISSIVE
FOR ALL
TO authenticated
USING (
    -- Allow users to access organizations where they are a member
    EXISTS (
        SELECT 1
        FROM public.users_permissions up
        WHERE up.user_id = auth.uid()
          AND up.organization_id = organizations.id
    ) OR
    -- Allow users to access organizations where they are a member of the parent organization
    EXISTS (
        SELECT 1
        FROM public.users_permissions up
        WHERE up.user_id = auth.uid()
          AND up.organization_id = organizations.parent_organization_id
    )
)
WITH CHECK (
    -- Allow users to insert, update or delete organizations where they are a member
    EXISTS (
        SELECT 1
        FROM public.users_permissions up
        WHERE up.user_id = auth.uid()
          AND up.organization_id = organizations.id
    ) OR
    -- Allow users to insert, update or delete organizations where they are a member of the parent
    EXISTS (
        SELECT 1
        FROM public.users_permissions up
        WHERE up.user_id = auth.uid()
          AND up.organization_id = organizations.parent_organization_id
    )
);


-- Path: supabase/migrations/20241202134806_public.sql
CREATE TABLE IF NOT EXISTS public.users_profile (
    id uuid primary key references auth.users on delete cascade,
    is_admin boolean NOT NULL DEFAULT false,
    state_responsible smallint NULL,
    is_organization_admin boolean NOT NULL DEFAULT false,
    organization_id uuid NULL REFERENCES organizations(id),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    email text NOT NULL
);
ALTER TABLE public.users_profile ADD COLUMN IF NOT EXISTS "is_database_admin" boolean NOT NULL DEFAULT false;

Alter Table public.users_profile enable row level security;

-- Create a policy to allow authenticated users to access their own profile and user with same organization_id from users_permissions
DROP POLICY IF EXISTS "Enable all access for authenticated users with same organization_id" ON public.users_profile;
CREATE POLICY "Enable all access for authenticated users with same organization_id"
ON public.users_profile
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
    -- Allow users to access their own profile
    true
);

-- inserts a row into public.profiles
DROP FUNCTION IF EXISTS public.handle_new_user_profile CASCADE;
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
DECLARE
  domain_part text;
  org_id uuid;
begin

  -- Get the organization_id from auth.users.raw_user_meta_data
  if new.raw_user_meta_data is not null then
    select (new.raw_user_meta_data::jsonb ->> 'organization_id')::uuid into org_id;
  else
    -- If no organization found
    org_id := null;
  end if;

  insert into public.users_profile (id, email, organization_id) values (new.id, new.email, org_id)
  on conflict (id) do update set email = new.email;

  -- Check if the user is an admin - FIXED duplicate check
  if new.email like '%@thuenen.de' then
    update public.users_profile set is_admin = true where id = new.id;
  else
    update public.users_profile set is_admin = false where id = new.id;
  end if;
  -- Check if the user is a state responsible
  return new;
end;
$$;

-- trigger the function every time a user is created
-- trigger the function only when a user's email is confirmed
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after update of email_confirmed_at on auth.users
  for each row
  when (old.email_confirmed_at is null and new.email_confirmed_at is not null)
  execute procedure public.handle_new_user_profile();

 
-- CREATE troop table
-- https://supabase.com/docs/guides/database/postgres/custom-claims-and-role-based-access-control-rbac?queryGroups=language&language=plpgsql
-- https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook
CREATE TABLE IF NOT EXISTS troop (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    name text NOT NULL,
    --supervisor_id uuid not null DEFAULT auth.uid() REFERENCES auth.users(id),
    --user_ids uuid[] NOT NULL DEFAULT '{}',
    --plot_ids uuid[] NOT NULL DEFAULT '{}',
    organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    is_control_troop boolean NOT NULL DEFAULT false
);

-- add user_ids array
ALTER TABLE troop ADD COLUMN IF NOT EXISTS user_ids uuid[] NOT NULL DEFAULT '{}';


ALTER TABLE troop ENABLE ROW LEVEL SECURITY;

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


-- CREATE TAble Lose
CREATE TABLE IF NOT EXISTS public.organizations_lose (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    name text NOT NULL,
    description text,
    organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE
    --parent_organization_id uuid NULL REFERENCES organizations(id) ON DELETE CASCADE
);
ALTER TABLE public.organizations_lose ADD COLUMN IF NOT EXISTS responsible_organization_id uuid NULL REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.organizations_lose ADD COLUMN IF NOT EXISTS troop_id uuid NULL REFERENCES troop(id) ON DELETE CASCADE;
ALTER TABLE public.organizations_lose ADD COLUMN IF NOT EXISTS record_ids uuid[] NOT NULL DEFAULT '{}';
ALTER TABLE public.organizations_lose ADD COLUMN IF NOT EXISTS cluster_ids uuid[] NOT NULL DEFAULT '{}';
ALTER TABLE organizations_lose ENABLE ROW LEVEL SECURITY;

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
    --OR parent_organization_id IN (
    --    SELECT organization_id
    --    FROM public.users_permissions
    --    WHERE user_id = auth.uid()
    --)
)
WITH CHECK (
    organization_id IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    )
    --OR parent_organization_id IN (
    --    SELECT organization_id
    --    FROM public.users_permissions
    --    WHERE user_id = auth.uid()
    --)
);

--CREATE TABLE IF NOT EXISTS troop_permissions (
--    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
--    troop_id uuid NOT NULL REFERENCES troop(id) ON DELETE CASCADE,
--    plot_id uuid NOT NULL REFERENCES inventory_archive.plot(id) ON DELETE CASCADE,
--    cluster_id uuid NOT NULL REFERENCES inventory_archive.cluster(id) ON DELETE CASCADE
--);
--
--ALTER TABLE troop_permissions ENABLE ROW LEVEL SECURITY;

create table IF NOT EXISTS "records" (
    "id" uuid primary key default gen_random_uuid(),
    "created_at" timestamp with time zone not null default now(),
    "updated_by" uuid null DEFAULT auth.uid() REFERENCES auth.users(id),
    "properties" jsonb not null default '{}'::jsonb,
    "previous_properties" jsonb not null default '{}'::jsonb,
    "previous_properties_updated_at" timestamp with time zone not null default now(),
    "is_valid" boolean null default null,
    "plot_id" uuid not NULL REFERENCES inventory_archive.plot(id) UNIQUE,
    --"cluster_id" uuid NULL REFERENCES inventory_archive.cluster(id),
    --"troop_id" uuid NULL REFERENCES troop(id),
    "schema_id" uuid NULL REFERENCES public.schemas(id),
    "schema_name" text NULL DEFAULT 'ci2027'
    --"state_responsible" smallint not NULL REFERENCES lookup.lookup_state (code),
    --"organization_id" uuid not NULL REFERENCES organizations(id)
);
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "responsible_administration" uuid REFERENCES organizations(id) ON DELETE SET NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "responsible_state" uuid REFERENCES organizations(id) ON DELETE SET NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "responsible_provider" uuid REFERENCES organizations(id) ON DELETE SET NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "responsible_troop" uuid REFERENCES troop(id) ON DELETE SET NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "validated_at" timestamp with time zone NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "message" text NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "cluster_id" uuid NULL REFERENCES inventory_archive.cluster(id);
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "cluster_name" integer NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "plot_name" smallint NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "administration_los" uuid NULL REFERENCES organizations_lose(id) ON DELETE SET NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "state_los" uuid NULL REFERENCES organizations_lose(id) ON DELETE SET NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "provider_los" uuid NULL REFERENCES organizations_lose(id) ON DELETE SET NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "troop_los" uuid NULL REFERENCES organizations_lose(id) ON DELETE SET NULL;

ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "completed_at_troop" timestamp with time zone NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "completed_at_state" timestamp with time zone NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "completed_at_administration" timestamp with time zone NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "updated_at" timestamp with time zone NULL;

ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "validation_errors" jsonb NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "plausibility_errors" jsonb NULL;
ALTER TABLE "records" ADD COLUMN IF NOT EXISTS "validation_version" uuid NULL;


create trigger handle_updated_at before update on records
  for each row execute procedure extensions.moddatetime (updated_at);

-- Add indexes to the records table for common query fields
CREATE INDEX IF NOT EXISTS idx_records_plot_id ON records(plot_id);
CREATE INDEX IF NOT EXISTS idx_records_schema_id ON records(schema_id);
CREATE INDEX IF NOT EXISTS idx_records_responsible_state ON records(responsible_state);
CREATE INDEX IF NOT EXISTS idx_records_responsible_provider ON records(responsible_provider);
CREATE INDEX IF NOT EXISTS idx_records_responsible_troop ON records(responsible_troop);
CREATE INDEX IF NOT EXISTS idx_records_cluster_id ON records(cluster_id);
CREATE INDEX IF NOT EXISTS idx_records_schema_name ON records(schema_name);

COMMENT ON TABLE "records" IS 'Plots';

alter table "records" enable row level security;

-- Create a policy to allow "update" and "select" only users_permissions with the same organization_id of responsible_state, responsible_provider or responsible_troop
DROP POLICY IF EXISTS "Enable SELECT access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON "records";
CREATE POLICY "Enable SELECT access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop"
ON "records"
AS PERMISSIVE
FOR select
TO authenticated
USING (
    -- check if one of the organizations in public.users_permissions user has access to is type organizations.type = 'root'
    EXISTS (
        SELECT 1
        FROM public.organizations org
        WHERE org.id IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
    AND org.type = 'root'
    ) OR

    responsible_state IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    ) OR
    responsible_provider IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    ) OR
    responsible_troop IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    )
);
-- Create a policy to allow "update" and "select" only users_permissions with the same organization_id of responsible_state, responsible_provider or responsible_troop
DROP POLICY IF EXISTS "Enable UPDATE access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON "records";
CREATE POLICY "Enable UPDATE access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop"
ON "records"
AS PERMISSIVE
FOR update
TO authenticated
USING (
    -- check if one of the organizations in public.users_permissions user has access to is type organizations.type = 'root'
    EXISTS (
        SELECT 1
        FROM public.organizations org
        WHERE org.id IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
    AND org.type = 'root'
    ) OR
    EXISTS (
        SELECT 1
        FROM public.users_profile prof
        WHERE prof.id = auth.uid()
          AND prof.is_admin = true
    ) OR
    responsible_state IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    ) OR
    responsible_provider IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    ) OR
    responsible_troop IN (
        SELECT t.id
        FROM public.troop t
        WHERE t.organization_id IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
    )
)
WITH CHECK (
    -- check if one of the organizations in public.users_permissions user has access to is type organizations.type = 'root'
    EXISTS (
        SELECT 1
        FROM public.organizations org
        WHERE org.id IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
    AND org.type = 'root'
    ) OR
    EXISTS (
        SELECT 1
        FROM public.users_profile prof
        WHERE prof.id = auth.uid()
          AND prof.is_admin = true
    ) OR
    responsible_state IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    ) OR
    responsible_provider IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    ) OR
    responsible_troop IN (
        SELECT t.id
        FROM public.troop t
        WHERE t.organization_id IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
    )
);           





-- Create a copy of the "records" table structure only, named "record_changes"
DROP TABLE IF EXISTS public.record_changes;
CREATE TABLE public.record_changes (LIKE public.records INCLUDING ALL);

-- Correctly define the foreign key reference for record_id
ALTER TABLE public.record_changes ADD COLUMN record_id UUID;

-- Add a comment to the new table
COMMENT ON TABLE public.record_changes IS 'Copy of the records table structure for tracking changes.';

-- Enable row-level security for the new table
ALTER TABLE public.record_changes ENABLE ROW LEVEL SECURITY;

-- Add indexes to the new table for common query fields
CREATE INDEX IF NOT EXISTS idx_record_changes_plot_id ON public.record_changes(plot_id);
CREATE INDEX IF NOT EXISTS idx_record_changes_schema_id ON public.record_changes(schema_id);
CREATE INDEX IF NOT EXISTS idx_record_changes_responsible_state ON public.record_changes(responsible_state);
CREATE INDEX IF NOT EXISTS idx_record_changes_responsible_provider ON public.record_changes(responsible_provider);
CREATE INDEX IF NOT EXISTS idx_record_changes_responsible_troop ON public.record_changes(responsible_troop);
CREATE INDEX IF NOT EXISTS idx_record_changes_cluster_id ON public.record_changes(cluster_id);
CREATE INDEX IF NOT EXISTS idx_record_changes_schema_name ON public.record_changes(schema_name);

-- Add a comment to the new table
COMMENT ON TABLE public.record_changes IS 'Copy of the records table for tracking changes.';

-- Remove UNIQUE constraint on plot_id in record_changes table
ALTER TABLE public.record_changes DROP CONSTRAINT IF EXISTS record_changes_plot_id_key;

-- Create a policy to allow "update" and "select" only users_permissions with the same organization_id of responsible_state, responsible_provider or responsible_troop
DROP POLICY IF EXISTS "record_changes: Enable SELECT access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON "record_changes";
CREATE POLICY "record_changes: Enable SELECT access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop"
ON "record_changes"
AS PERMISSIVE
FOR select
TO authenticated
USING (
    -- check if one of the organizations in public.users_permissions user has access to is type organizations.type = 'root'
    EXISTS (
        SELECT 1
        FROM public.organizations org
        WHERE org.id IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
    AND org.type = 'root'
    ) OR

    responsible_state IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    ) OR
    responsible_provider IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    ) OR
    responsible_troop IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    )
);


-- Invitation table
--CREATE TABLE public.invitations (
--    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
--    inviter_id UUID REFERENCES auth.users(id),
--    invitee_email VARCHAR NOT NULL,
--    token VARCHAR NOT NULL,
--    created_at TIMESTAMPTZ DEFAULT now(),
--    expires_at TIMESTAMPTZ,
--    accepted BOOLEAN DEFAULT FALSE,
--    troop_id UUID REFERENCES public.troop(id),
--    organization_id UUID REFERENCES public.organizations(id)
--);
--ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;
-- Create a policy to allow only the inviter ALL
--CREATE POLICY "Enable all access for authenticated users"
--ON public.invitations
--AS PERMISSIVE
--FOR ALL
--TO authenticated
--USING (inviter_id = auth.uid() OR troop_id IN (
--    SELECT id FROM public.troop WHERE supervisor_id = auth.uid()
--))
--WITH CHECK (inviter_id = auth.uid() OR troop_id IN (
--    SELECT id FROM public.troop WHERE supervisor_id = auth.uid()
--));


-- user_permissions table
create table IF NOT EXISTS "public"."users_permissions" (
    "id" uuid not null default gen_random_uuid() primary key,
    "created_at" timestamp with time zone not null default now(),
    "user_id" uuid not null default auth.uid() references auth.users(id) on delete cascade,
    "organization_id" uuid not null references organizations(id) on delete cascade,
    "created_by" uuid default auth.uid() references auth.users(id) on delete cascade,
    "troop_id" uuid references public.troop(id) on delete cascade
    --"is_organization_admin" boolean not null default false
);
ALTER TABLE "public"."users_permissions" ADD COLUMN IF NOT EXISTS "is_database_admin" boolean not null default false;
ALTER TABLE "public"."users_permissions" ADD COLUMN IF NOT EXISTS "is_organization_admin" boolean not null default false;

alter table "public"."users_permissions" enable row level security;

-- Update the policy for users_permissions
DROP POLICY IF EXISTS "Enable users with own role equals organization_admin and same organization_id" ON "public"."users_permissions";
CREATE POLICY "Enable users with own role equals organization_admin and same organization_id"
ON "public"."users_permissions"
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
    -- Allow users to access their own permissions
    true
);

--DROP POLICY IF EXISTS "Select user permissions for authenticated users and user_id equals auth.uid()" ON "public"."users_permissions";
--CREATE POLICY "Select user permissions for authenticated users and user_id equals auth.uid()"
--ON "public"."users_permissions"
--AS PERMISSIVE
--FOR SELECT
--TO authenticated
--USING (user_id = auth.uid() OR troop_id IN (
--    SELECT id FROM public.troop WHERE supervisor_id = auth.uid()
--));
