alter table "external_data"."lookup_biogeographische_region" add column "abbreviation" text not null;

alter table "external_data"."lookup_biosphaere" add column "abbreviation" text not null;

alter table "external_data"."lookup_ffh" add column "abbreviation" text not null;

alter table "external_data"."lookup_national_park" add column "abbreviation" text not null;

alter table "external_data"."lookup_natur_park" add column "abbreviation" text not null;

alter table "external_data"."lookup_natur_schutzgebiet" add column "abbreviation" text not null;

alter table "external_data"."lookup_vogelschutzgebiete" add column "abbreviation" text not null;

CREATE UNIQUE INDEX lookup_biogeographische_region_abbreviation_key ON external_data.lookup_biogeographische_region USING btree (abbreviation);

CREATE UNIQUE INDEX lookup_biosphaere_abbreviation_key ON external_data.lookup_biosphaere USING btree (abbreviation);

CREATE UNIQUE INDEX lookup_ffh_abbreviation_key ON external_data.lookup_ffh USING btree (abbreviation);

CREATE UNIQUE INDEX lookup_national_park_abbreviation_key ON external_data.lookup_national_park USING btree (abbreviation);

CREATE UNIQUE INDEX lookup_natur_park_abbreviation_key ON external_data.lookup_natur_park USING btree (abbreviation);

CREATE UNIQUE INDEX lookup_natur_schutzgebiet_abbreviation_key ON external_data.lookup_natur_schutzgebiet USING btree (abbreviation);

CREATE UNIQUE INDEX lookup_vogelschutzgebiete_abbreviation_key ON external_data.lookup_vogelschutzgebiete USING btree (abbreviation);

alter table "external_data"."lookup_biogeographische_region" add constraint "lookup_biogeographische_region_abbreviation_key" UNIQUE using index "lookup_biogeographische_region_abbreviation_key";

alter table "external_data"."lookup_biosphaere" add constraint "lookup_biosphaere_abbreviation_key" UNIQUE using index "lookup_biosphaere_abbreviation_key";

alter table "external_data"."lookup_ffh" add constraint "lookup_ffh_abbreviation_key" UNIQUE using index "lookup_ffh_abbreviation_key";

alter table "external_data"."lookup_national_park" add constraint "lookup_national_park_abbreviation_key" UNIQUE using index "lookup_national_park_abbreviation_key";

alter table "external_data"."lookup_natur_park" add constraint "lookup_natur_park_abbreviation_key" UNIQUE using index "lookup_natur_park_abbreviation_key";

alter table "external_data"."lookup_natur_schutzgebiet" add constraint "lookup_natur_schutzgebiet_abbreviation_key" UNIQUE using index "lookup_natur_schutzgebiet_abbreviation_key";

alter table "external_data"."lookup_vogelschutzgebiete" add constraint "lookup_vogelschutzgebiete_abbreviation_key" UNIQUE using index "lookup_vogelschutzgebiete_abbreviation_key";


alter table "private_ci2027_001"."cluster" drop column "irgendwas";


