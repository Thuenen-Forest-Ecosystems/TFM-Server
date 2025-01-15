alter table "external_data"."lookup_biogeographische_region" enable row level security;

alter table "external_data"."lookup_biosphaere" enable row level security;

alter table "external_data"."lookup_ffh" enable row level security;

alter table "external_data"."lookup_national_park" enable row level security;

alter table "external_data"."lookup_natur_park" enable row level security;

alter table "external_data"."lookup_natur_schutzgebiet" enable row level security;

alter table "external_data"."lookup_vogelschutzgebiete" enable row level security;

create policy "Enable read access for all users"
on "external_data"."lookup_biogeographische_region"
as permissive
for select
to anon
using (true);


create policy "Enable read access for all users"
on "external_data"."lookup_biosphaere"
as permissive
for select
to anon
using (true);


create policy "Enable read access for all users"
on "external_data"."lookup_ffh"
as permissive
for select
to anon
using (true);


create policy "Enable read access for all users"
on "external_data"."lookup_national_park"
as permissive
for select
to anon
using (true);


create policy "Enable read access for all users"
on "external_data"."lookup_natur_park"
as permissive
for select
to anon
using (true);


create policy "Enable read access for all users"
on "external_data"."lookup_natur_schutzgebiet"
as permissive
for select
to anon
using (true);


create policy "Enable read access for all users"
on "external_data"."lookup_vogelschutzgebiete"
as permissive
for select
to anon
using (true);



