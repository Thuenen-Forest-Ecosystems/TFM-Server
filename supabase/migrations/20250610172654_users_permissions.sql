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


