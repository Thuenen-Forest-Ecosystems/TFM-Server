

CREATE TABLE external_data.lookup_gemeinde AS TABLE private_ci2027_001.lookup_TEMPLATE WITH NO DATA;
ALTER TABLE external_data.lookup_gemeinde ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;
ALTER TABLE external_data.lookup_gemeinde ADD COLUMN abbreviation text UNIQUE NOT NULL;

alter table "external_data"."lookup_gemeinde" enable row level security;

create policy "Enable read access for all users"
on "external_data"."lookup_gemeinde"
as permissive
for select
to anon
using (true);


CREATE TABLE external_data.lookup_forestry_office AS TABLE private_ci2027_001.lookup_TEMPLATE WITH NO DATA;
ALTER TABLE external_data.lookup_forestry_office ADD COLUMN id uuid DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL;
ALTER TABLE external_data.lookup_forestry_office ADD COLUMN abbreviation text UNIQUE NOT NULL;

alter table "external_data"."lookup_forestry_office" enable row level security;

create policy "Enable read access for all users"
on "external_data"."lookup_forestry_office"
as permissive
for select
to anon
using (true);