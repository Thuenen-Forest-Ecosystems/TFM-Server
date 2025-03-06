-- SCHEMA inventory
CREATE SCHEMA inventory;
ALTER SCHEMA inventory OWNER TO postgres;
COMMENT ON SCHEMA inventory IS 'aktuelle Invenur';
GRANT USAGE ON SCHEMA inventory TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA inventory TO anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA inventory TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA inventory TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA inventory GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA inventory GRANT ALL ON ROUTINES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA inventory GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

SET search_path TO inventory;

create table "records" (
    "id" uuid primary key default gen_random_uuid(),
    "created_at" timestamp with time zone not null default now(),
    "data" json not null,
    "schema" uuid not null
);

COMMENT ON TABLE "records" IS 'Plots';

alter table "records" enable row level security;

ALTER TABLE records ADD CONSTRAINT FK_Records_Schema FOREIGN KEY (schema) REFERENCES public.schemas(id) ON DELETE CASCADE;


create table "record_changes" (
    "id" uuid primary key default gen_random_uuid(),
    "created_at" timestamp with time zone not null default now(),
    "data" json not null,
    "schema" uuid not null
);

COMMENT ON TABLE "record_changes" IS 'Änderungen an Plots';


alter table "record_changes" enable row level security;

ALTER TABLE record_changes ADD CONSTRAINT FK_RecordChanges_Schema FOREIGN KEY (schema) REFERENCES public.schemas(id) ON DELETE CASCADE;


--- Backout plot to backup_changes every time plot updates
CREATE OR REPLACE FUNCTION inventory.handle_record_changes()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into inventory.record_changes (data, schema) values (old.data, old.schema);
  return new;
end;
$$;

-- trigger the function every time a plot is updated
DROP TRIGGER IF EXISTS on_record_updated ON inventory.records;

create trigger on_record_updated
  after update on inventory.records
  for each row execute procedure inventory.handle_record_changes();