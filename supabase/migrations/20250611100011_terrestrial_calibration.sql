alter table "derived"."derived_deadwood" add constraint "derived_deadwood_deadwood_id_fkey" FOREIGN KEY (deadwood_id) REFERENCES inventory_archive.deadwood(id) not valid;

alter table "derived"."derived_deadwood" validate constraint "derived_deadwood_deadwood_id_fkey";

alter table "derived"."derived_deadwood" add constraint "derived_deadwood_plot_id_fkey" FOREIGN KEY (plot_id) REFERENCES inventory_archive.plot(id) not valid;

alter table "derived"."derived_deadwood" validate constraint "derived_deadwood_plot_id_fkey";


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

alter table "inventory_archive"."plot" alter column "interval_name" set not null;

alter table "inventory_archive"."structure_gt4m" alter column "is_mirrored" drop not null;

alter table "inventory_archive"."tree" add column "deadwood_used" boolean default false;

alter table "inventory_archive"."tree" alter column "distance" drop not null;

alter table "inventory_archive"."tree" alter column "tree_marked" drop not null;

alter table "inventory_archive"."plot" add constraint "plot_interval_name_fkey" FOREIGN KEY (interval_name) REFERENCES lookup.lookup_interval(code) not valid;

alter table "inventory_archive"."plot" validate constraint "plot_interval_name_fkey";

create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."cluster"
as permissive
for select
to anon, ti_read, authenticated
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."deadwood"
as permissive
for select
to anon, ti_read, authenticated
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."edges"
as permissive
for select
to anon, ti_read, authenticated
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."plot"
as permissive
for select
to anon, ti_read, authenticated
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."plot_coordinates"
as permissive
for select
to anon, ti_read, authenticated
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."plot_landmark"
as permissive
for select
to anon, ti_read, authenticated
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."position"
as permissive
for select
to anon, ti_read, authenticated
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."regeneration"
as permissive
for select
to anon, ti_read, authenticated
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."structure_gt4m"
as permissive
for select
to anon, ti_read, authenticated
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."structure_lt4m"
as permissive
for select
to anon, ti_read, authenticated
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."subplots_relative_position"
as permissive
for select
to anon, ti_read, authenticated
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."table_template"
as permissive
for select
to anon, ti_read, authenticated
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."tree"
as permissive
for select
to anon, ti_read, authenticated
using (true);


create policy "default_select_anon_and_ti_read_and_authenticated"
on "inventory_archive"."tree_coordinates"
as permissive
for select
to anon, ti_read, authenticated
using (true);



drop policy "select" on "lookup"."lookup_boundary_type_rows";

drop policy "select" on "lookup"."lookup_id_stand_differences_rows";

revoke delete on table "lookup"."lookup_boundary_type_rows" from "anon";

revoke insert on table "lookup"."lookup_boundary_type_rows" from "anon";

revoke references on table "lookup"."lookup_boundary_type_rows" from "anon";

revoke select on table "lookup"."lookup_boundary_type_rows" from "anon";

revoke trigger on table "lookup"."lookup_boundary_type_rows" from "anon";

revoke truncate on table "lookup"."lookup_boundary_type_rows" from "anon";

revoke update on table "lookup"."lookup_boundary_type_rows" from "anon";

revoke delete on table "lookup"."lookup_boundary_type_rows" from "authenticated";

revoke insert on table "lookup"."lookup_boundary_type_rows" from "authenticated";

revoke references on table "lookup"."lookup_boundary_type_rows" from "authenticated";

revoke select on table "lookup"."lookup_boundary_type_rows" from "authenticated";

revoke trigger on table "lookup"."lookup_boundary_type_rows" from "authenticated";

revoke truncate on table "lookup"."lookup_boundary_type_rows" from "authenticated";

revoke update on table "lookup"."lookup_boundary_type_rows" from "authenticated";

revoke delete on table "lookup"."lookup_boundary_type_rows" from "service_role";

revoke insert on table "lookup"."lookup_boundary_type_rows" from "service_role";

revoke references on table "lookup"."lookup_boundary_type_rows" from "service_role";

revoke select on table "lookup"."lookup_boundary_type_rows" from "service_role";

revoke trigger on table "lookup"."lookup_boundary_type_rows" from "service_role";

revoke truncate on table "lookup"."lookup_boundary_type_rows" from "service_role";

revoke update on table "lookup"."lookup_boundary_type_rows" from "service_role";

alter table "lookup"."lookup_boundary_type_rows" drop constraint "lookup_boundary_type_rows_code_key";

alter table "lookup"."lookup_boundary_type_rows" drop constraint "lookup_boundary_type_rows_pkey";

drop index if exists "lookup"."lookup_boundary_type_rows_code_key";

drop index if exists "lookup"."lookup_boundary_type_rows_pkey";

drop table "lookup"."lookup_boundary_type_rows";

grant delete on table "lookup"."lookup_id_stand_differences_rows" to "anon";

grant insert on table "lookup"."lookup_id_stand_differences_rows" to "anon";

grant references on table "lookup"."lookup_id_stand_differences_rows" to "anon";

grant select on table "lookup"."lookup_id_stand_differences_rows" to "anon";

grant trigger on table "lookup"."lookup_id_stand_differences_rows" to "anon";

grant truncate on table "lookup"."lookup_id_stand_differences_rows" to "anon";

grant update on table "lookup"."lookup_id_stand_differences_rows" to "anon";

grant delete on table "lookup"."lookup_id_stand_differences_rows" to "authenticated";

grant insert on table "lookup"."lookup_id_stand_differences_rows" to "authenticated";

grant references on table "lookup"."lookup_id_stand_differences_rows" to "authenticated";

grant select on table "lookup"."lookup_id_stand_differences_rows" to "authenticated";

grant trigger on table "lookup"."lookup_id_stand_differences_rows" to "authenticated";

grant truncate on table "lookup"."lookup_id_stand_differences_rows" to "authenticated";

grant update on table "lookup"."lookup_id_stand_differences_rows" to "authenticated";

grant delete on table "lookup"."lookup_id_stand_differences_rows" to "service_role";

grant insert on table "lookup"."lookup_id_stand_differences_rows" to "service_role";

grant references on table "lookup"."lookup_id_stand_differences_rows" to "service_role";

grant select on table "lookup"."lookup_id_stand_differences_rows" to "service_role";

grant trigger on table "lookup"."lookup_id_stand_differences_rows" to "service_role";

grant truncate on table "lookup"."lookup_id_stand_differences_rows" to "service_role";

grant update on table "lookup"."lookup_id_stand_differences_rows" to "service_role";

grant select on table "lookup"."lookup_id_stand_differences_rows" to "ti_read";

create policy "default_select_anon_and_ti_read_and_authenticated"
on "lookup"."lookup_id_stand_differences_rows"
as permissive
for select
to anon, ti_read, authenticated
using (true);



drop policy "Policy with security definer functions" on "public"."records";

drop policy "Enable read access for all users" on "public"."schemas";

alter table "public"."schemas" drop constraint "schemas_interval_name_key";

drop index if exists "public"."schemas_interval_name_key";

alter table "public"."records" alter column "organization_id" set not null;

alter table "public"."schemas" alter column "interval_name" set default 'ci2027'::text;

alter table "public"."record_changes" add constraint "record_changes_plot_id_fkey" FOREIGN KEY (plot_id) REFERENCES inventory_archive.plot(id) not valid;

alter table "public"."record_changes" validate constraint "record_changes_plot_id_fkey";

alter table "public"."records" add constraint "records_plot_id_fkey" FOREIGN KEY (plot_id) REFERENCES inventory_archive.plot(id) not valid;

alter table "public"."records" validate constraint "records_plot_id_fkey";

alter table "public"."schemas" add constraint "schemas_interval_name_fkey" FOREIGN KEY (interval_name) REFERENCES lookup.lookup_interval(code) ON UPDATE RESTRICT ON DELETE RESTRICT not valid;

alter table "public"."schemas" validate constraint "schemas_interval_name_fkey";

set check_function_bodies = off;

create or replace view "public"."plot_nested_json" as  SELECT plot.intkey,
    plot.id,
    plot.interval_name,
    plot.sampling_stratum,
    plot.federal_state,
    plot.growth_district,
    plot.forest_status,
    plot.accessibility,
    plot.forest_office,
    plot.elevation_level,
    plot.property_type,
    plot.property_size_class,
    plot.forest_community,
    plot.forest_community_field,
    plot.ffh_forest_type,
    plot.ffh_forest_type_field,
    plot.land_use_before,
    plot.land_use_after,
    plot.coast,
    plot.sandy,
    plot.protected_landscape,
    plot.histwald,
    plot.harvest_restriction,
    plot.marker_status,
    plot.marker_azimuth,
    plot.marker_distance,
    plot.marker_profile,
    plot.terrain_form,
    plot.terrain_slope,
    plot.terrain_exposure,
    plot.management_type,
    plot.harvesting_method,
    plot.biotope,
    plot.stand_structure,
    plot.stand_age,
    plot.stand_development_phase,
    plot.stand_layer_regeneration,
    plot.fence_regeneration,
    plot.trees_greater_4meter_mirrored,
    plot.trees_greater_4meter_basal_area_factor,
    plot.trees_less_4meter_coverage,
    plot.trees_less_4meter_layer,
    plot.biogeographische_region,
    plot.biosphaere,
    plot.ffh,
    plot.national_park,
    plot.natur_park,
    plot.vogel_schutzgebiet,
    plot.natur_schutzgebiet,
    plot.harvest_restriction_nature_reserve,
    plot.harvest_restriction_protection_forest,
    plot.harvest_restriction_recreational_forest,
    plot.harvest_restriction_scattered,
    plot.harvest_restriction_fragmented,
    plot.harvest_restriction_insufficient_access,
    plot.harvest_restriction_wetness,
    plot.harvest_restriction_low_yield,
    plot.harvest_restriction_private_conservation,
    plot.harvest_restriction_other_internalcause,
    plot.usage_type,
    plot.plot_name,
    plot.cluster_name,
    plot.cluster_id,
    COALESCE(( SELECT json_agg(row_to_json(plot_coordinates.*)) AS json_agg
           FROM inventory_archive.plot_coordinates
          WHERE (plot_coordinates.plot_id = plot.id)), '[]'::json) AS plot_coordinates,
    COALESCE(( SELECT json_agg(row_to_json(tree.*)) AS json_agg
           FROM inventory_archive.tree
          WHERE (tree.plot_id = plot.id)), '[]'::json) AS trees,
    COALESCE(( SELECT json_agg(row_to_json(deadwood.*)) AS json_agg
           FROM inventory_archive.deadwood
          WHERE (deadwood.plot_id = plot.id)), '[]'::json) AS deadwoods,
    COALESCE(( SELECT json_agg(row_to_json(regeneration.*)) AS json_agg
           FROM inventory_archive.regeneration
          WHERE (regeneration.plot_id = plot.id)), '[]'::json) AS regenerations,
    COALESCE(( SELECT json_agg(row_to_json(structure_lt4m.*)) AS json_agg
           FROM inventory_archive.structure_lt4m
          WHERE (structure_lt4m.plot_id = plot.id)), '[]'::json) AS structures_lt4m,
    COALESCE(( SELECT json_agg(row_to_json(edges.*)) AS json_agg
           FROM inventory_archive.edges
          WHERE (edges.plot_id = plot.id)), '[]'::json) AS edges
   FROM inventory_archive.plot;


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


