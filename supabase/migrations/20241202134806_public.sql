SET search_path TO public;

create table "public"."schemas" (
    "created_at" timestamp with time zone not null default now(),
    "interval_name" text not null,
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
("interval_name", "title", "description", "is_visible", "bucket_schema_file_name", "bucket_plausability_file_name") values 
('ci2027', 'CI 2027', 'CI 2027', true, 'ci2027_schema_0.0.1.json', 'ci2027_plausability_0.0.1.js');


-- Path: supabase/migrations/20241202134806_public.sql
CREATE TABLE IF NOT EXISTS public.users_profile (
    id uuid not null references auth.users on delete cascade primary key,
    is_admin boolean NOT NULL DEFAULT false,
    states_admin text[] NOT NULL DEFAULT '{}'
);

Alter Table public.users_profile enable row level security;

-- inserts a row into public.profiles
create function public.handle_new_user_profile()
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
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user_profile();



--- Add Organizations table that are allowed to create auth.users

CREATE TABLE IF NOT EXISTS organizations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    apex_domain text NOT NULL
);

INSERT INTO organizations (apex_domain) VALUES ('thuenen.de');

-- ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;

--- Insert new User in auth.users only if the email ends with apex_domain is in the organizations table
CREATE OR REPLACE FUNCTION check_domain_before_insert()
RETURNS TRIGGER
SECURITY DEFINER
AS $$
DECLARE
    domain_to_check TEXT;
    domain_exists BOOLEAN;
BEGIN
    -- Extract the domain from the new email
    domain_to_check := substring(NEW.email FROM '@(.*)');

    -- Check if the domain exists in the organizations table
    SELECT EXISTS (SELECT 1 FROM public.organizations WHERE apex_domain = domain_to_check) INTO domain_exists;

    -- If the domain does not exist, prevent the insert
    IF NOT domain_exists THEN
        RAISE EXCEPTION 'Domain % not found in organizations table', domain_to_check;
    END IF;

    RETURN NEW; -- Allow the insert to proceed
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS before_insert_user_check ON auth.users;

CREATE OR REPLACE TRIGGER before_insert_user_check
BEFORE INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION check_domain_before_insert();

 