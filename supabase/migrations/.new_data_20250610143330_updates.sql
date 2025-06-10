alter table "inventory_archive"."plot" alter column "interval_name" drop default;

alter table "inventory_archive"."structure_gt4m" alter column "is_mirrored" set not null;

alter table "inventory_archive"."tree" drop column "deadwood_used";

alter table "inventory_archive"."tree" alter column "distance" set not null;

alter table "inventory_archive"."tree" alter column "tree_marked" set not null;

create policy "Enable insert for authenticated users only"
on "inventory_archive"."position"
as permissive
for insert
to authenticated
with check (true);



drop policy "default_select_anon_and_ti_read_and_authenticated" on "lookup"."lookup_id_stand_differences_rows";

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

grant delete on table "lookup"."lookup_boundary_type_rows" to "anon";

grant insert on table "lookup"."lookup_boundary_type_rows" to "anon";

grant references on table "lookup"."lookup_boundary_type_rows" to "anon";

grant select on table "lookup"."lookup_boundary_type_rows" to "anon";

grant trigger on table "lookup"."lookup_boundary_type_rows" to "anon";

grant truncate on table "lookup"."lookup_boundary_type_rows" to "anon";

grant update on table "lookup"."lookup_boundary_type_rows" to "anon";

grant delete on table "lookup"."lookup_boundary_type_rows" to "authenticated";

grant insert on table "lookup"."lookup_boundary_type_rows" to "authenticated";

grant references on table "lookup"."lookup_boundary_type_rows" to "authenticated";

grant select on table "lookup"."lookup_boundary_type_rows" to "authenticated";

grant trigger on table "lookup"."lookup_boundary_type_rows" to "authenticated";

grant truncate on table "lookup"."lookup_boundary_type_rows" to "authenticated";

grant update on table "lookup"."lookup_boundary_type_rows" to "authenticated";

grant delete on table "lookup"."lookup_boundary_type_rows" to "service_role";

grant insert on table "lookup"."lookup_boundary_type_rows" to "service_role";

grant references on table "lookup"."lookup_boundary_type_rows" to "service_role";

grant select on table "lookup"."lookup_boundary_type_rows" to "service_role";

grant trigger on table "lookup"."lookup_boundary_type_rows" to "service_role";

grant truncate on table "lookup"."lookup_boundary_type_rows" to "service_role";

grant update on table "lookup"."lookup_boundary_type_rows" to "service_role";

create policy "replace_with_policy_name"
on "lookup"."lookup_boundary_type_rows"
as permissive
for select
to anon, authenticated, ti_read
using (true);


create policy "replace_with_policy_name"
on "lookup"."lookup_id_stand_differences_rows"
as permissive
for select
to anon, authenticated, ti_read
using (true);



drop policy "Enable all access for authenticated users" on "public"."invitations";

drop policy "troop_supervisor_all_policy" on "public"."troop";

drop policy "Enable read access for all users" on "public"."organizations";

drop policy "select_same_organization_policy" on "public"."users_profile";

alter table "public"."organizations" drop constraint "organizations_created_by_fkey";

alter table "public"."schemas" drop constraint "schemas_interval_name_fkey";

alter table "public"."troop" drop constraint "troop_supervisor_id_fkey";

drop view if exists "public"."plot_nested_json";

create table "public"."cluster_permissions" (
    "id" uuid not null default gen_random_uuid(),
    "created_at" timestamp with time zone not null default now(),
    "cluster_id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "created_by" uuid default auth.uid(),
    "troop_id" uuid
);


alter table "public"."cluster_permissions" enable row level security;

create table "public"."users_permissions" (
    "id" uuid not null default gen_random_uuid(),
    "created_at" timestamp with time zone not null default now(),
    "user_id" uuid not null,
    "organization_id" uuid not null,
    "write_access" boolean not null default false,
    "created_by" uuid default auth.uid(),
    "role" text,
    "troop_id" uuid
);


alter table "public"."users_permissions" enable row level security;

alter table "public"."organizations" add column "entityName" text;

alter table "public"."organizations" add column "is_root" boolean not null default false;

alter table "public"."organizations" add column "plots" integer[] not null default '{}'::integer[];

alter table "public"."organizations" add column "type" text not null default 'organization'::text;

alter table "public"."schemas" alter column "interval_name" drop not null;

alter table "public"."troop" drop column "plot_ids";

alter table "public"."troop" drop column "supervisor_id";

CREATE UNIQUE INDEX cluster_permissions_pkey ON public.cluster_permissions USING btree (id);

CREATE UNIQUE INDEX users_permissions_pkey ON public.users_permissions USING btree (id);

alter table "public"."cluster_permissions" add constraint "cluster_permissions_pkey" PRIMARY KEY using index "cluster_permissions_pkey";

alter table "public"."users_permissions" add constraint "users_permissions_pkey" PRIMARY KEY using index "users_permissions_pkey";

alter table "public"."cluster_permissions" add constraint "cluster_permissions_cluster_id_fkey" FOREIGN KEY (cluster_id) REFERENCES inventory_archive.cluster(id) ON DELETE CASCADE not valid;

alter table "public"."cluster_permissions" validate constraint "cluster_permissions_cluster_id_fkey";

alter table "public"."cluster_permissions" add constraint "cluster_permissions_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE not valid;

alter table "public"."cluster_permissions" validate constraint "cluster_permissions_organization_id_fkey";

alter table "public"."cluster_permissions" add constraint "cluster_permissions_troop_id_fkey" FOREIGN KEY (troop_id) REFERENCES troop(id) not valid;

alter table "public"."cluster_permissions" validate constraint "cluster_permissions_troop_id_fkey";

alter table "public"."users_permissions" add constraint "users_permissions_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) not valid;

alter table "public"."users_permissions" validate constraint "users_permissions_created_by_fkey";

alter table "public"."users_permissions" add constraint "users_permissions_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE not valid;

alter table "public"."users_permissions" validate constraint "users_permissions_organization_id_fkey";

alter table "public"."users_permissions" add constraint "users_permissions_troop_id_fkey" FOREIGN KEY (troop_id) REFERENCES organizations(id) ON DELETE CASCADE not valid;

alter table "public"."users_permissions" validate constraint "users_permissions_troop_id_fkey";

alter table "public"."users_permissions" add constraint "users_permissions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."users_permissions" validate constraint "users_permissions_user_id_fkey";

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


grant delete on table "public"."cluster_permissions" to "anon";

grant insert on table "public"."cluster_permissions" to "anon";

grant references on table "public"."cluster_permissions" to "anon";

grant select on table "public"."cluster_permissions" to "anon";

grant trigger on table "public"."cluster_permissions" to "anon";

grant truncate on table "public"."cluster_permissions" to "anon";

grant update on table "public"."cluster_permissions" to "anon";

grant delete on table "public"."cluster_permissions" to "authenticated";

grant insert on table "public"."cluster_permissions" to "authenticated";

grant references on table "public"."cluster_permissions" to "authenticated";

grant select on table "public"."cluster_permissions" to "authenticated";

grant trigger on table "public"."cluster_permissions" to "authenticated";

grant truncate on table "public"."cluster_permissions" to "authenticated";

grant update on table "public"."cluster_permissions" to "authenticated";

grant delete on table "public"."cluster_permissions" to "service_role";

grant insert on table "public"."cluster_permissions" to "service_role";

grant references on table "public"."cluster_permissions" to "service_role";

grant select on table "public"."cluster_permissions" to "service_role";

grant trigger on table "public"."cluster_permissions" to "service_role";

grant truncate on table "public"."cluster_permissions" to "service_role";

grant update on table "public"."cluster_permissions" to "service_role";

grant delete on table "public"."users_permissions" to "anon";

grant insert on table "public"."users_permissions" to "anon";

grant references on table "public"."users_permissions" to "anon";

grant select on table "public"."users_permissions" to "anon";

grant trigger on table "public"."users_permissions" to "anon";

grant truncate on table "public"."users_permissions" to "anon";

grant update on table "public"."users_permissions" to "anon";

grant delete on table "public"."users_permissions" to "authenticated";

grant insert on table "public"."users_permissions" to "authenticated";

grant references on table "public"."users_permissions" to "authenticated";

grant select on table "public"."users_permissions" to "authenticated";

grant trigger on table "public"."users_permissions" to "authenticated";

grant truncate on table "public"."users_permissions" to "authenticated";

grant update on table "public"."users_permissions" to "authenticated";

grant delete on table "public"."users_permissions" to "service_role";

grant insert on table "public"."users_permissions" to "service_role";

grant references on table "public"."users_permissions" to "service_role";

grant select on table "public"."users_permissions" to "service_role";

grant trigger on table "public"."users_permissions" to "service_role";

grant truncate on table "public"."users_permissions" to "service_role";

grant update on table "public"."users_permissions" to "service_role";

create policy "Enable delete for users based on user_id"
on "public"."cluster_permissions"
as permissive
for delete
to public
using ((( SELECT auth.uid() AS uid) = created_by));


create policy "Enable insert for authenticated users only"
on "public"."cluster_permissions"
as permissive
for insert
to authenticated
with check (true);


create policy "replace_with_policy_name"
on "public"."cluster_permissions"
as permissive
for select
to authenticated
using (true);


create policy "Enable delete for users based on user_id"
on "public"."organizations"
as permissive
for delete
to public
using ((( SELECT auth.uid() AS uid) = created_by));


create policy "Enable delete for users based on user_id"
on "public"."users_permissions"
as permissive
for delete
to public
using ((( SELECT auth.uid() AS uid) = created_by));


create policy "replace_with_policy_name"
on "public"."users_permissions"
as permissive
for select
to authenticated
using (true);


create policy "Enable read access for all users"
on "public"."organizations"
as permissive
for select
to authenticated
using (((auth.uid() = created_by) OR (EXISTS ( SELECT 1
   FROM users_permissions
  WHERE ((users_permissions.user_id = auth.uid()) AND (users_permissions.organization_id = organizations.id))))));


create policy "select_same_organization_policy"
on "public"."users_profile"
as permissive
for select
to authenticated
using (true);



