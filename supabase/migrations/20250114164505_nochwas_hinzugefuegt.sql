alter table "private_ci2027_001"."cluster" add column "nochwas" text;

alter table "private_ci2027_001"."cluster" add column "random" text;

create policy "Enable insert for authenticated users only"
on "private_ci2027_001"."lookup_browsing"
as permissive
for insert
to service_role
with check (true);


create policy "update by service"
on "private_ci2027_001"."lookup_browsing"
as permissive
for update
to service_role
using (true);



