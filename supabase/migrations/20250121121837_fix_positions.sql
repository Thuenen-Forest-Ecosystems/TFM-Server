drop policy "default_policy" on "private_ci2027_001"."plot";

alter type "private_ci2027_001"."enum_gnss_quality" rename to "enum_gnss_quality__old_version_to_be_dropped";

create type "private_ci2027_001"."enum_gnss_quality" as enum ('1', '2', '4', '9', '5', '91', '92', '93');

alter table "private_ci2027_001"."lookup_gnss_quality" alter column abbreviation type "private_ci2027_001"."enum_gnss_quality" using abbreviation::text::"private_ci2027_001"."enum_gnss_quality";

alter table "private_ci2027_001"."position" alter column quality type "private_ci2027_001"."enum_gnss_quality" using quality::text::"private_ci2027_001"."enum_gnss_quality";

drop type "private_ci2027_001"."enum_gnss_quality__old_version_to_be_dropped";

alter table "private_ci2027_001"."cluster" alter column "modified_by" drop not null;

alter table "private_ci2027_001"."deadwood" alter column "modified_by" drop not null;

alter table "private_ci2027_001"."edges" alter column "modified_by" drop not null;

alter table "private_ci2027_001"."plot" alter column "modified_by" drop not null;

alter table "private_ci2027_001"."position" alter column "hdop_mean" drop not null;

alter table "private_ci2027_001"."position" alter column "measurement_count" drop not null;

alter table "private_ci2027_001"."position" alter column "modified_by" drop not null;

alter table "private_ci2027_001"."position" alter column "pdop_mean" drop not null;

alter table "private_ci2027_001"."position" alter column "position_median" drop not null;

alter table "private_ci2027_001"."position" alter column "satellites_count_mean" drop not null;

alter table "private_ci2027_001"."position" alter column "start_measurement" drop not null;

alter table "private_ci2027_001"."position" alter column "stop_measurement" drop not null;

alter table "private_ci2027_001"."regeneration" alter column "modified_by" drop not null;

alter table "private_ci2027_001"."structure_lt4m" alter column "modified_by" drop not null;

alter table "private_ci2027_001"."tree" alter column "modified_by" drop not null;

create policy "default_policy"
on "private_ci2027_001"."plot"
as permissive
for select
to anon
using (true);



