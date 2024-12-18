drop trigger if exists "check_supervisor_update_trigger" on "private_ci2027_001"."cluster";

drop policy "cluster_insert" on "private_ci2027_001"."cluster";

drop function if exists "private_ci2027_001"."check_supervisor_update"();

alter table "private_ci2027_001"."cluster" drop column "supervisor";

alter table "private_ci2027_001"."cluster" add column "company_responsible" uuid not null default 'fe0d60ff-b536-40c8-b73d-1f87a44e2f55'::uuid;

alter table "private_ci2027_001"."cluster" add column "is_demo" boolean not null default false;

alter table "private_ci2027_001"."cluster" alter column "state_responsible" drop not null;

alter table "private_ci2027_001"."plot" add column "select_access_by" text[];

alter table "private_ci2027_001"."plot" alter column "federal_state" drop not null;

alter table "private_ci2027_001"."tree" add column "select_access_by" text[];

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION private_ci2027_001.copy_select_access_by_to_plot()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$BEGIN
    -- Update the select_access_by value in the plot table
    UPDATE private_ci2027_001.plot
    SET select_access_by = NEW.select_access_by
    WHERE cluster_id = NEW.cluster_name::int4;

    UPDATE private_ci2027_001.tree
    SET select_access_by = NEW.select_access_by
    WHERE plot_id IN (
        SELECT id FROM private_ci2027_001.plot WHERE cluster_id = NEW.cluster_name::int4
    );

    RETURN NEW;
END;$function$
;

create policy "Enable insert for authenticated users only"
on "private_ci2027_001"."cluster"
as permissive
for insert
to authenticated
with check (true);


create policy "Enable insert for authenticated users only"
on "private_ci2027_001"."deadwood"
as permissive
for insert
to authenticated
with check (true);


create policy "Enable insert for authenticated users only"
on "private_ci2027_001"."edges"
as permissive
for insert
to authenticated
with check (true);


create policy "Enable insert for authenticated users only"
on "private_ci2027_001"."plot"
as permissive
for insert
to authenticated
with check (true);


create policy "Enable insert for authenticated users only"
on "private_ci2027_001"."position"
as permissive
for insert
to authenticated
with check (true);


create policy "Enable insert for authenticated users only"
on "private_ci2027_001"."regeneration"
as permissive
for insert
to authenticated
with check (true);


create policy "Enable insert for authenticated users only"
on "private_ci2027_001"."structure_lt4m"
as permissive
for insert
to authenticated
with check (true);


create policy "Enable insert for authenticated users only"
on "private_ci2027_001"."tree"
as permissive
for insert
to authenticated
with check (true);



alter table "public"."users_profile" drop constraint "users_profile_id_fkey";

alter table "public"."users_profile" drop constraint "users_profile_supervisor_id_fkey";

create table "public"."companies_access" (
    "id" uuid not null default gen_random_uuid(),
    "company_name" text not null,
    "company_email_domain" text not null,
    "created_at" timestamp without time zone not null default CURRENT_TIMESTAMP,
    "modified_at" timestamp without time zone,
    "modified_by" uuid default auth.uid()
);


alter table "public"."companies_access" enable row level security;

create table "public"."schemas" (
    "created_at" timestamp with time zone not null default now(),
    "interval_name" text not null default ''::text,
    "is_visible" boolean not null default false,
    "description" text,
    "title" text not null,
    "id" uuid not null default gen_random_uuid(),
    "preview_interval_name" text,
    "file_bundle" uuid not null
);


alter table "public"."schemas" enable row level security;

alter table "public"."users_access" add column "user_id" uuid;

alter table "public"."users_profile" drop column "users_company";

alter table "public"."users_profile" add column "company" uuid;

alter table "public"."users_profile" add column "email" text;

alter table "public"."users_profile" add column "is_admin" boolean not null default false;

alter table "public"."users_profile" add column "phone" text;

alter table "public"."users_profile" add column "user_id" uuid default auth.uid();

alter table "public"."users_profile" alter column "id" set default gen_random_uuid();

CREATE UNIQUE INDEX companies_access_pkey ON public.companies_access USING btree (id);

CREATE UNIQUE INDEX schemas_interval_name_key ON public.schemas USING btree (interval_name);

CREATE UNIQUE INDEX schemas_pkey ON public.schemas USING btree (id);

alter table "public"."companies_access" add constraint "companies_access_pkey" PRIMARY KEY using index "companies_access_pkey";

alter table "public"."schemas" add constraint "schemas_pkey" PRIMARY KEY using index "schemas_pkey";

alter table "public"."schemas" add constraint "schemas_file_bundle_fkey" FOREIGN KEY (file_bundle) REFERENCES storage.objects(id) not valid;

alter table "public"."schemas" validate constraint "schemas_file_bundle_fkey";

alter table "public"."schemas" add constraint "schemas_interval_name_key" UNIQUE using index "schemas_interval_name_key";

alter table "public"."users_access" add constraint "users_access_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."users_access" validate constraint "users_access_user_id_fkey";

alter table "public"."users_profile" add constraint "users_profile_company_fkey" FOREIGN KEY (company) REFERENCES companies_access(id) not valid;

alter table "public"."users_profile" validate constraint "users_profile_company_fkey";

alter table "public"."users_profile" add constraint "users_profile_supervisor_id_fkey1" FOREIGN KEY (supervisor_id) REFERENCES users_profile(id) not valid;

alter table "public"."users_profile" validate constraint "users_profile_supervisor_id_fkey1";

alter table "public"."users_profile" add constraint "users_profile_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;

alter table "public"."users_profile" validate constraint "users_profile_user_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.check_user_domain()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    user_domain TEXT;
BEGIN

    -- Extract the domain part of the user's email
    user_domain := substring(NEW.email FROM '@(.+)$');

    -- Check if the extracted domain exists in the public.companies_access table
    IF EXISTS (SELECT 1 FROM public.companies_access WHERE company_email_domain = user_domain) THEN
        RETURN NEW;
    ELSE
        raise exception 'INCORRECT_DOMAIN';
    END IF;

    ---IF NEW.email NOT LIKE '%@thuenen.de' THEN
    ---    raise exception 'INCORRECT_DOMAIN';
    ---END IF;
---
    ---RETURN NEW;
END;
$function$
;

grant delete on table "public"."companies_access" to "anon";

grant insert on table "public"."companies_access" to "anon";

grant references on table "public"."companies_access" to "anon";

grant select on table "public"."companies_access" to "anon";

grant trigger on table "public"."companies_access" to "anon";

grant truncate on table "public"."companies_access" to "anon";

grant update on table "public"."companies_access" to "anon";

grant delete on table "public"."companies_access" to "authenticated";

grant insert on table "public"."companies_access" to "authenticated";

grant references on table "public"."companies_access" to "authenticated";

grant select on table "public"."companies_access" to "authenticated";

grant trigger on table "public"."companies_access" to "authenticated";

grant truncate on table "public"."companies_access" to "authenticated";

grant update on table "public"."companies_access" to "authenticated";

grant delete on table "public"."companies_access" to "service_role";

grant insert on table "public"."companies_access" to "service_role";

grant references on table "public"."companies_access" to "service_role";

grant select on table "public"."companies_access" to "service_role";

grant trigger on table "public"."companies_access" to "service_role";

grant truncate on table "public"."companies_access" to "service_role";

grant update on table "public"."companies_access" to "service_role";

grant delete on table "public"."schemas" to "anon";

grant insert on table "public"."schemas" to "anon";

grant references on table "public"."schemas" to "anon";

grant select on table "public"."schemas" to "anon";

grant trigger on table "public"."schemas" to "anon";

grant truncate on table "public"."schemas" to "anon";

grant update on table "public"."schemas" to "anon";

grant delete on table "public"."schemas" to "authenticated";

grant insert on table "public"."schemas" to "authenticated";

grant references on table "public"."schemas" to "authenticated";

grant select on table "public"."schemas" to "authenticated";

grant trigger on table "public"."schemas" to "authenticated";

grant truncate on table "public"."schemas" to "authenticated";

grant update on table "public"."schemas" to "authenticated";

grant delete on table "public"."schemas" to "service_role";

grant insert on table "public"."schemas" to "service_role";

grant references on table "public"."schemas" to "service_role";

grant select on table "public"."schemas" to "service_role";

grant trigger on table "public"."schemas" to "service_role";

grant truncate on table "public"."schemas" to "service_role";

grant update on table "public"."schemas" to "service_role";

create policy "Enable read access for all users"
on "public"."companies_access"
as permissive
for select
to authenticated
using (true);


create policy "Enable SELECT for authenticated users only"
on "public"."schemas"
as permissive
for select
to authenticated
using (true);



