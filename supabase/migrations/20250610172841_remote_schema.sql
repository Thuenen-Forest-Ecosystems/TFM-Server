alter table "derived"."derived_deadwood" drop constraint "derived_deadwood_deadwood_id_fkey";

alter table "derived"."derived_deadwood" drop constraint "derived_deadwood_plot_id_fkey";


drop policy "default_select_anon_and_ti_read_and_authenticated" on "inventory_archive"."cluster";

drop policy "default_select_anon_and_ti_read_and_authenticated" on "inventory_archive"."deadwood";

drop policy "default_select_anon_and_ti_read_and_authenticated" on "inventory_archive"."edges";

drop policy "default_select_anon_and_ti_read_and_authenticated" on "inventory_archive"."plot";

drop policy "default_select_anon_and_ti_read_and_authenticated" on "inventory_archive"."plot_coordinates";

drop policy "default_select_anon_and_ti_read_and_authenticated" on "inventory_archive"."plot_landmark";

drop policy "default_select_anon_and_ti_read_and_authenticated" on "inventory_archive"."position";

drop policy "default_select_anon_and_ti_read_and_authenticated" on "inventory_archive"."regeneration";

drop policy "default_select_anon_and_ti_read_and_authenticated" on "inventory_archive"."structure_gt4m";

drop policy "default_select_anon_and_ti_read_and_authenticated" on "inventory_archive"."structure_lt4m";

drop policy "default_select_anon_and_ti_read_and_authenticated" on "inventory_archive"."subplots_relative_position";

drop policy "default_select_anon_and_ti_read_and_authenticated" on "inventory_archive"."table_template";

drop policy "default_select_anon_and_ti_read_and_authenticated" on "inventory_archive"."tree";

drop policy "default_select_anon_and_ti_read_and_authenticated" on "inventory_archive"."tree_coordinates";

alter table "inventory_archive"."plot" drop constraint "plot_interval_name_fkey";

alter table "inventory_archive"."plot" alter column "interval_name" set default 'ci2027';

alter table "inventory_archive"."plot" alter column "interval_name" drop not null;

alter table "inventory_archive"."structure_gt4m" alter column "is_mirrored" set not null;

alter table "inventory_archive"."tree" drop column "deadwood_used";

alter table "inventory_archive"."tree" alter column "distance" set not null;

alter table "inventory_archive"."tree" alter column "tree_marked" set not null;

create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."cluster"
as permissive
for select
to authenticated, anon, ti_read
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."deadwood"
as permissive
for select
to authenticated, anon, ti_read
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."edges"
as permissive
for select
to authenticated, anon, ti_read
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."plot"
as permissive
for select
to authenticated, anon, ti_read
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."plot_coordinates"
as permissive
for select
to authenticated, ti_read
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."plot_landmark"
as permissive
for select
to authenticated, ti_read
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."position"
as permissive
for select
to authenticated, ti_read
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."regeneration"
as permissive
for select
to authenticated, anon, ti_read
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."structure_gt4m"
as permissive
for select
to authenticated, anon, ti_read
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."structure_lt4m"
as permissive
for select
to authenticated, anon, ti_read
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."subplots_relative_position"
as permissive
for select
to authenticated, ti_read
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."table_template"
as permissive
for select
to authenticated, anon, ti_read
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."tree"
as permissive
for select
to authenticated, anon, ti_read
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."tree_coordinates"
as permissive
for select
to authenticated, ti_read
using (true);



drop policy "default_select_anon_and_ti_read_and_authenticated" on "lookup"."lookup_id_stand_differences_rows";

revoke delete on table "lookup"."lookup_id_stand_differences_rows" from "anon";

revoke insert on table "lookup"."lookup_id_stand_differences_rows" from "anon";

revoke references on table "lookup"."lookup_id_stand_differences_rows" from "anon";

revoke select on table "lookup"."lookup_id_stand_differences_rows" from "anon";

revoke trigger on table "lookup"."lookup_id_stand_differences_rows" from "anon";

revoke truncate on table "lookup"."lookup_id_stand_differences_rows" from "anon";

revoke update on table "lookup"."lookup_id_stand_differences_rows" from "anon";

revoke delete on table "lookup"."lookup_id_stand_differences_rows" from "authenticated";

revoke insert on table "lookup"."lookup_id_stand_differences_rows" from "authenticated";

revoke references on table "lookup"."lookup_id_stand_differences_rows" from "authenticated";

revoke select on table "lookup"."lookup_id_stand_differences_rows" from "authenticated";

revoke trigger on table "lookup"."lookup_id_stand_differences_rows" from "authenticated";

revoke truncate on table "lookup"."lookup_id_stand_differences_rows" from "authenticated";

revoke update on table "lookup"."lookup_id_stand_differences_rows" from "authenticated";

revoke delete on table "lookup"."lookup_id_stand_differences_rows" from "service_role";

revoke insert on table "lookup"."lookup_id_stand_differences_rows" from "service_role";

revoke references on table "lookup"."lookup_id_stand_differences_rows" from "service_role";

revoke select on table "lookup"."lookup_id_stand_differences_rows" from "service_role";

revoke trigger on table "lookup"."lookup_id_stand_differences_rows" from "service_role";

revoke truncate on table "lookup"."lookup_id_stand_differences_rows" from "service_role";

revoke update on table "lookup"."lookup_id_stand_differences_rows" from "service_role";

revoke select on table "lookup"."lookup_id_stand_differences_rows" from "ti_read";

create table "lookup"."lookup_boundary_type_rows" (
    "code" integer not null default nextval('lookup.lookup_template_code_seq'::regclass),
    "id" uuid not null default gen_random_uuid(),
    "name_de" text not null,
    "name_en" text,
    "interval" text[],
    "sort" integer
);


alter table "lookup"."lookup_boundary_type_rows" enable row level security;

CREATE UNIQUE INDEX lookup_boundary_type_rows_code_key ON lookup.lookup_boundary_type_rows USING btree (code);

CREATE UNIQUE INDEX lookup_boundary_type_rows_pkey ON lookup.lookup_boundary_type_rows USING btree (id);

alter table "lookup"."lookup_boundary_type_rows" add constraint "lookup_boundary_type_rows_pkey" PRIMARY KEY using index "lookup_boundary_type_rows_pkey";

alter table "lookup"."lookup_boundary_type_rows" add constraint "lookup_boundary_type_rows_code_key" UNIQUE using index "lookup_boundary_type_rows_code_key";

create policy "select"
on "lookup"."lookup_boundary_type_rows"
as permissive
for select
to anon, authenticated, ti_read
using (true);


create policy "select"
on "lookup"."lookup_id_stand_differences_rows"
as permissive
for select
to anon, authenticated, ti_read
using (true);



-- Remove PostGIS downgrade - extensions can only be upgraded, not downgraded
-- alter extension "postgis" update to '3.3.2';

alter table "public"."record_changes" drop constraint "record_changes_plot_id_fkey";

alter table "public"."records" drop constraint "records_plot_id_fkey";

alter table "public"."schemas" drop constraint "schemas_interval_name_fkey";

drop view if exists "public"."plot_nested_json";

alter table "public"."records" alter column "organization_id" drop not null;

alter table "public"."schemas" alter column "interval_name" drop default;

CREATE UNIQUE INDEX schemas_interval_name_key ON public.schemas USING btree (interval_name);

alter table "public"."schemas" add constraint "schemas_interval_name_key" UNIQUE using index "schemas_interval_name_key";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

create policy "Policy with security definer functions"
on "public"."records"
as permissive
for all
to authenticated
using (true);


create policy "Enable read access for all users"
on "public"."schemas"
as permissive
for select
to public
using (true);



-- Remove PostGIS topology downgrade - extensions can only be upgraded, not downgraded
-- alter extension "postgis_topology" update to '3.3.2';


