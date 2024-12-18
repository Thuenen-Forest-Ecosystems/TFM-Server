drop trigger if exists "check_supervisor_update_trigger" on "private_ci2027_001"."cluster";

drop function if exists "private_ci2027_001"."check_supervisor_update"();

alter table "private_ci2027_001"."cluster" drop column "supervisor";

alter table "private_ci2027_001"."cluster" add column "company_responsible" uuid not null default 'fe0d60ff-b536-40c8-b73d-1f87a44e2f55'::uuid;

alter table "private_ci2027_001"."cluster" add column "is_demo" boolean not null default false;

alter table "private_ci2027_001"."cluster" alter column "state_responsible" drop not null;

alter table "private_ci2027_001"."plot" add column "select_access_by" text[];


alter table "public"."users_profile" drop constraint "users_profile_id_fkey";

alter table "public"."users_profile" drop constraint "users_profile_supervisor_id_fkey";

create table "public"."schemas" (
    "created_at" timestamp with time zone not null default now(),
    "interval_name" text not null default ''::text,
    "is_visible" boolean not null default false,
    "description" text,
    "title" text not null,
    "id" uuid not null default gen_random_uuid(),
    "preview_interval_name" text
);


alter table "public"."schemas" enable row level security;

alter table "public"."users_access" add column "user_id" uuid;

alter table "public"."users_profile" add column "email" text;

alter table "public"."users_profile" add column "is_admin" boolean not null default false;

alter table "public"."users_profile" add column "phone" text;

alter table "public"."users_profile" add column "user_id" uuid default auth.uid();

alter table "public"."users_profile" alter column "id" set default gen_random_uuid();

CREATE UNIQUE INDEX schemas_interval_name_key ON public.schemas USING btree (interval_name);

CREATE UNIQUE INDEX schemas_pkey ON public.schemas USING btree (id);

alter table "public"."schemas" add constraint "schemas_pkey" PRIMARY KEY using index "schemas_pkey";

alter table "public"."schemas" add constraint "schemas_interval_name_key" UNIQUE using index "schemas_interval_name_key";

alter table "public"."users_access" add constraint "users_access_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."users_access" validate constraint "users_access_user_id_fkey";

alter table "public"."users_profile" add constraint "users_profile_supervisor_id_fkey1" FOREIGN KEY (supervisor_id) REFERENCES users_profile(id) not valid;

alter table "public"."users_profile" validate constraint "users_profile_supervisor_id_fkey1";

alter table "public"."users_profile" add constraint "users_profile_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;

alter table "public"."users_profile" validate constraint "users_profile_user_id_fkey";

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

create policy "Enable SELECT for authenticated users only"
on "public"."schemas"
as permissive
for select
to authenticated
using (true);



