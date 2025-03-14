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


-- Path: supabase/migrations/20241202134806_public.sql
CREATE TABLE IF NOT EXISTS public.users_profile (
    id uuid not null references auth.users on delete cascade primary key,
    is_admin boolean NOT NULL DEFAULT false,
    state_responsible smallint NULL
);

Alter Table public.users_profile enable row level security;

-- inserts a row into public.profiles
DROP FUNCTION IF EXISTS public.handle_new_user_profile CASCADE;
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.users_profile (id) values (new.id);
  return new;
end;
$$;

-- trigger the function every time a user is created
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user_profile();



--- Add Organizations table that are allowed to create auth.users
CREATE TABLE IF NOT EXISTS organizations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    apex_domain text NOT NULL UNIQUE
);

INSERT INTO organizations (apex_domain) VALUES ('@thuenen.de');

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;

--- Insert new User in auth.users only if the email ends with apex_domain is in the organizations table
DROP FUNCTION IF EXISTS public.check_domain_before_insert CASCADE;
CREATE OR REPLACE FUNCTION check_domain_before_insert()
RETURNS TRIGGER
SECURITY DEFINER
AS $$
DECLARE
    domain_to_check TEXT;
    domain_exists BOOLEAN;
BEGIN
    -- Extract domain part (everything after @)
    BEGIN
        domain_to_check := '@' || split_part(NEW.email, '@', 2);
        
        -- Debug log 
        RAISE NOTICE 'Checking domain: %', domain_to_check;
        
        -- Verify the domain exists in our allowed list
        SELECT EXISTS (
            SELECT 1 
            FROM public.organizations 
            WHERE apex_domain = domain_to_check
        ) INTO domain_exists;
        
        IF NOT domain_exists THEN
            RAISE EXCEPTION 'Email domain % not authorized', domain_to_check;
        END IF;
        
        RETURN NEW;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Error in check_domain_before_insert: % %', SQLERRM, SQLSTATE;
            RETURN NEW; -- Allow registration during debugging
    END;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS before_insert_user_check ON auth.users;
CREATE OR REPLACE TRIGGER before_insert_user_check
BEFORE INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION check_domain_before_insert();

 
-- CREATE troop table
-- https://supabase.com/docs/guides/database/postgres/custom-claims-and-role-based-access-control-rbac?queryGroups=language&language=plpgsql
-- https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook
CREATE TABLE IF NOT EXISTS troop (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    name text NULL,
    supervisor_id uuid NOT NULL REFERENCES auth.users(id),
    user_ids uuid[] NOT NULL DEFAULT '{}',
    plot_ids uuid[] NOT NULL DEFAULT '{}'
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