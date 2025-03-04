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

create table "plot" (
    "id" uuid primary key default gen_random_uuid(),
    "created_at" timestamp with time zone not null default now(),
    "data" json not null,
    "schema" uuid not null
);

COMMENT ON TABLE "plot" IS 'Plots';

alter table "plot" enable row level security;

ALTER TABLE plot ADD CONSTRAINT FK_Plot_Schema FOREIGN KEY (schema) REFERENCES public.schemas(id) ON DELETE CASCADE;


create table "plot_changes" (
    "id" uuid primary key default gen_random_uuid(),
    "created_at" timestamp with time zone not null default now(),
    "data" json not null,
    "schema" uuid not null
);

COMMENT ON TABLE "plot_changes" IS 'Änderungen an Plots';


alter table "plot_changes" enable row level security;

ALTER TABLE plot_changes ADD CONSTRAINT FK_PlotChanges_Schema FOREIGN KEY (schema) REFERENCES public.schemas(id) ON DELETE CASCADE;


--- Backout plot to backup_changes every time plot updates
CREATE OR REPLACE FUNCTION inventory.handle_plot_changes()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into inventory.plot_changes (data, schema) values (old.data, old.schema);
  return new;
end;
$$;

-- trigger the function every time a plot is updated
DROP TRIGGER IF EXISTS on_plot_updated ON inventory.plot;
create trigger on_plot_updated
  after update on inventory.plot
  for each row execute procedure inventory.handle_plot_changes();


