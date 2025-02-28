create table "public"."schemas" (
    "created_at" timestamp with time zone not null default now(),
    "interval_name" text not null,
    "title" text not null,
    "description" text,
    "is_visible" boolean not null default false,
    "bucket_schema_file_name" text,
    "bucket_plausability_file_name" text,
    "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL
);


alter table "public"."schemas" enable row level security;

-- add first schema
insert into "public"."schemas" 
("interval_name", "title", "description", "is_visible", "bucket_schema_file_name", "bucket_plausability_file_name") values 
('ci2027', 'CI 2027', 'CI 2027', true, 'ci2027_schema_0.0.1.json', 'ci2027_plausability_0.0.1.js');


-- Path: supabase/migrations/20241202134806_public.sql
CREATE TABLE public.users_profiles (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL,
    user_id uuid NOT NULL,
    is_admin boolean NOT NULL DEFAULT false,
    states_admin text[] NOT NULL DEFAULT '{}'
);

ALTER TABLE public.users_profiles  ADD CONSTRAINT fk_user_id FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.users_profiles ENABLE ROW LEVEL SECURITY;

-- Function to create a new user profile when a new user is created in auth.users
CREATE OR REPLACE FUNCTION create_user_profile()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users_profiles (user_id)
    VALUES (NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to create a new user profile when a new user is created in auth.users
CREATE TRIGGER create_user_profile
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION create_user_profile();