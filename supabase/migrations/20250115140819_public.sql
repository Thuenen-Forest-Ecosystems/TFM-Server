SET search_path TO public;

create table IF NOT EXISTS "public"."schemas" (
    "created_at" timestamp with time zone not null default now(),
    "interval_name" text not null UNIQUE,
    "title" text not null,
    "description" text,
    "is_visible" boolean not null default false,
    "bucket_schema_file_name" text,
    "bucket_plausability_file_name" text,
    "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL,
    "schema" json
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
    name text NULL
);

INSERT INTO organizations (apex_domain, name) VALUES ('@thuenen.de', 'Thünen-Institut');

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;

-- Path: supabase/migrations/20241202134806_public.sql
CREATE TABLE IF NOT EXISTS public.users_profile (
    id uuid not null references auth.users on delete cascade primary key,
    is_admin boolean NOT NULL DEFAULT false,
    state_responsible smallint NULL,
    organization_id uuid NULL REFERENCES organizations(id),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    email text NOT NULL
);

Alter Table public.users_profile enable row level security;

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
  -- GET organization_id from the email domain
  --domain_part := '@' || split_part(new.email, '@', 2);
  --
  ---- Look up the organization_id based on the domain
  --SELECT id INTO org_id
  --FROM public.organizations
  --WHERE apex_domain like domain_part;
--
  ---- If no organization found, raise an exception
  --IF org_id IS NULL THEN
  --  RAISE EXCEPTION 'No organization found for domain %', domain_part;
  --END IF;

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
    name text NULL,
    supervisor_id uuid not null DEFAULT auth.uid() REFERENCES auth.users(id),
    user_ids uuid[] NOT NULL DEFAULT '{}',
    plot_ids uuid[] NOT NULL DEFAULT '{}',
    organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE
);

ALTER TABLE troop ENABLE ROW LEVEL SECURITY;

--CREATE TABLE IF NOT EXISTS troop_permissions (
--    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
--    troop_id uuid NOT NULL REFERENCES troop(id) ON DELETE CASCADE,
--    plot_id uuid NOT NULL REFERENCES inventory_archive.plot(id) ON DELETE CASCADE,
--    cluster_id uuid NOT NULL REFERENCES inventory_archive.cluster(id) ON DELETE CASCADE
--);
--
--ALTER TABLE troop_permissions ENABLE ROW LEVEL SECURITY;



create table "records" (
    "id" uuid primary key default gen_random_uuid(),
    "created_at" timestamp with time zone not null default now(),
    "updated_by" uuid not null DEFAULT auth.uid() REFERENCES auth.users(id),
    "properties" jsonb not null default '{}'::jsonb,
    "previous_properties" jsonb not null default '{}'::jsonb,
    "previous_properties_updated_at" timestamp with time zone not null default now(),
    "is_valid" boolean not null default false,
    "supervisor_id" uuid not null DEFAULT auth.uid() REFERENCES auth.users(id),
    "plot_id" uuid NULL REFERENCES inventory_archive.plot(id) UNIQUE,
    "troop_id" uuid NULL REFERENCES troop(id),
    "schema_id" uuid NULL REFERENCES public.schemas(id),
    "schema_name" text NULL DEFAULT 'ci2027'
    
);

COMMENT ON TABLE "records" IS 'Plots';

alter table "records" enable row level security;

create table "record_changes" (
    "id" uuid primary key default gen_random_uuid(),
    "created_at" timestamp with time zone not null default now(),
    "updated_by" uuid not null DEFAULT auth.uid() REFERENCES auth.users(id),
    "properties" jsonb not null default '{}'::jsonb,
    "previous_properties" jsonb not null default '{}'::jsonb,
    "previous_properties_updated_at" timestamp with time zone not null default now(),
    "is_valid" boolean not null default false,
    "supervisor_id" uuid not null DEFAULT auth.uid() REFERENCES auth.users(id),
    "plot_id" uuid NULL REFERENCES inventory_archive.plot(id),
    "troop_id" uuid NULL REFERENCES troop(id),
    "schema_id" uuid NULL REFERENCES public.schemas(id),
    "schema_name" text NULL DEFAULT 'ci2027'
);

COMMENT ON TABLE "record_changes" IS 'Änderungen an Plots';

alter table "record_changes" enable row level security;


--- Backout plot to backup_changes every time plot updates
CREATE OR REPLACE FUNCTION public.handle_record_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- only if is_valid change
  if new.is_valid != old.is_valid then
    -- Check if the new properties are different from the old properties
    if new.properties IS DISTINCT FROM old.properties then
      -- Insert a record into the record_changes table
      INSERT INTO public.record_changes (updated_by, properties, schema_name, previous_properties, previous_properties_updated_at, is_valid, supervisor_id, plot_id, troop_id, schema_id)
      VALUES (NEW.updated_by, NEW.properties, NEW.schema_name, OLD.properties, OLD.previous_properties_updated_at, OLD.is_valid, OLD.supervisor_id, OLD.plot_id, OLD.troop_id, OLD.schema_id);
    end if;
  end if;
  return new;
end;
$$;

-- trigger the function every time a plot is updated
DROP TRIGGER IF EXISTS on_record_updated ON records;
create trigger on_record_updated
  after update on records
  for each row execute procedure handle_record_changes();





-- First, create a function to validate JSON against schema
CREATE OR REPLACE FUNCTION public.validate_json_properties_by_schema(schema_id uuid, properties jsonb)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    schema_def json; -- Changed to jsonb
BEGIN
    -- Get the schema definition
    SELECT schema INTO schema_def FROM public.schemas WHERE id = schema_id; -- Cast to jsonb
    -- Check if schema_def is null (schema not found) before calling jsonb_matches_schema
    IF schema_def IS NULL THEN
        RETURN FALSE; -- Or handle the error as needed (e.g., RAISE EXCEPTION)
    END IF;
    
    -- Check if properties is null or empty
    IF properties IS NULL OR properties = '{}'::jsonb THEN
        RETURN TRUE; -- Or FALSE, depending on your requirements
    END IF;

    return extensions.jsonb_matches_schema(schema := schema_def, instance := properties);

END;
$$;

-- Create trigger function to validate records and set is_valid flag
CREATE OR REPLACE FUNCTION validate_record_properties()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN

    -- Only validate if both schema_id and properties are present
    IF NEW.schema_name IS NOT NULL AND NEW.properties IS NOT NULL AND jsonb_typeof(NEW.properties) = 'object' THEN
        -- Get Schema ID from interval_name, selecting the latest
        SELECT id INTO NEW.schema_id 
        FROM public.schemas 
        WHERE interval_name = NEW.schema_name AND is_visible = true
        ORDER BY created_at DESC
        LIMIT 1;
        -- Check if the JSON data is valid against the schema
        NEW.is_valid := public.validate_json_properties_by_schema(NEW.schema_id, NEW.properties);
    ELSE
        -- If either schema_id or properties is missing, mark as invalid
        NEW.is_valid := FALSE;
    END IF;

    RETURN NEW;
END;
$$;

-- Create or replace the trigger
DROP TRIGGER IF EXISTS before_record_insert_update ON public.records;
CREATE TRIGGER before_record_insert_update
    AFTER INSERT OR UPDATE ON public.records
    FOR EACH ROW EXECUTE FUNCTION public.validate_record_properties();




-- Invitation table
CREATE TABLE public.invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inviter_id UUID REFERENCES auth.users(id),
    invitee_email VARCHAR NOT NULL,
    token VARCHAR NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ,
    accepted BOOLEAN DEFAULT FALSE,
    troop_id UUID REFERENCES public.troop(id),
    organization_id UUID REFERENCES public.organizations(id)
);
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;
-- Create a policy to allow only the inviter ALL
CREATE POLICY "Enable all access for authenticated users"
ON public.invitations
AS PERMISSIVE
FOR ALL
TO authenticated
USING (inviter_id = auth.uid() OR troop_id IN (
    SELECT id FROM public.troop WHERE supervisor_id = auth.uid()
))
WITH CHECK (inviter_id = auth.uid() OR troop_id IN (
    SELECT id FROM public.troop WHERE supervisor_id = auth.uid()
));