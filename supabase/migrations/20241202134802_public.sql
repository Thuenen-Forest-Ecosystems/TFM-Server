create table "public"."schemas" (
    "created_at" timestamp with time zone not null default now(),
    "interval_name" text not null,
    "title" text not null,
    "description" text,
    "is_visible" boolean not null default false,
    "schema_url" text,
    "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL
);


alter table "public"."schemas" enable row level security;



-- add first schema
insert into "public"."schemas" 
("interval_name", "title", "description", "is_visible", "schema_url") values 
('ci2027', 'CI 2027', 'CI 2027', true, '');