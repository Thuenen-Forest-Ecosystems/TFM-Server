create table "public"."schemas" (
    "created_at" timestamp with time zone not null default now(),
    "interval_name" text not null,
    "title" text not null,
    "description" text,
    "is_visible" boolean not null default false,
    "schema_url" text,
    "id" uuid not null default gen_random_uuid()
);


alter table "public"."schemas" enable row level security;

CREATE UNIQUE INDEX schemas_pkey ON public.schemas USING btree (id);

alter table "public"."schemas" add constraint "schemas_pkey" PRIMARY KEY using index "schemas_pkey";

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


-- add first schema
insert into "public"."schemas" 
("interval_name", "title", "description", "is_visible", "schema_url") values 
('ci2027', 'CI 2027', 'CI 2027', true, '');