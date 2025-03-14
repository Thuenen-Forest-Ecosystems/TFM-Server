SET default_transaction_read_only = OFF;

-- SCHEMA derived
CREATE SCHEMA derived;
ALTER SCHEMA derived OWNER TO postgres;
COMMENT ON SCHEMA derived IS 'Kohlenstoffinventur 2027';
GRANT USAGE ON SCHEMA derived TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA derived TO anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA derived TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA derived TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA derived GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA derived GRANT ALL ON ROUTINES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA derived GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;


SET search_path TO derived;

CREATE TABLE IF NOT EXISTS table_TEMPLATE (
    id uuid UNIQUE DEFAULT gen_random_uuid() PRIMARY KEY NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid() NULL,
    updated_by uuid DEFAULT auth.uid() NULL
);


CREATE TABLE derived_deadwood (LIKE table_TEMPLATE INCLUDING ALL);
ALTER TABLE derived_deadwood
    ADD COLUMN deadwood_id uuid REFERENCES inventory_archive.deadwood(id) NOT NULL,
    ADD COLUMN plot_id uuid REFERENCES inventory_archive.plot(id) NOT NULL;

---RLS
ALTER TABLE derived_deadwood ENABLE ROW LEVEL SECURITY;