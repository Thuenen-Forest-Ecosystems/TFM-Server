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
    apex_domain text NOT NULL,
    created_by uuid DEFAULT auth.uid() REFERENCES auth.users(id),
    state_responsible smallint NULL REFERENCES lookup.lookup_state (code),
    parent_organization_id uuid NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name text NULL
);

INSERT INTO organizations (apex_domain) VALUES ('@thuenen.de');

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;

-- Path: supabase/migrations/20241202134806_public.sql
CREATE TABLE IF NOT EXISTS public.users_profile (
    id uuid not null references auth.users on delete cascade primary key,
    is_admin boolean NOT NULL DEFAULT false,
    state_responsible smallint NULL,
    organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
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
  domain_part := '@' || split_part(new.email, '@', 2);
  
  -- Look up the organization_id based on the domain
  SELECT id INTO org_id
  FROM public.organizations
  WHERE apex_domain like domain_part;

  -- If no organization found, raise an exception
  IF org_id IS NULL THEN
    RAISE EXCEPTION 'No organization found for domain %', domain_part;
  END IF;

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
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user_profile();

 
-- CREATE troop table
-- https://supabase.com/docs/guides/database/postgres/custom-claims-and-role-based-access-control-rbac?queryGroups=language&language=plpgsql
-- https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook
CREATE TABLE IF NOT EXISTS troop (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    name text NULL,
    supervisor_id uuid NOT NULL REFERENCES auth.users(id),
    user_ids uuid[] NOT NULL DEFAULT '{}',
    plot_ids uuid[] NOT NULL DEFAULT '{}',
    organzation_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE
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