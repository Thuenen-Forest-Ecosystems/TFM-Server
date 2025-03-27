CREATE OR REPLACE FUNCTION public.enable_rls_for_schema(schema_name TEXT, username TEXT DEFAULT 'anon') RETURNS VOID AS $$
DECLARE
    table_record RECORD;
BEGIN
    -- Loop through all tables in the specified schema
    FOR table_record IN
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = schema_name
        AND table_type = 'BASE TABLE'
    LOOP
        -- Enable RLS for each table
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', schema_name, table_record.table_name);
        EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', schema_name, table_record.table_name);
        
        -- Optionally, add a default policy (e.g., allow all access for demonstration purposes)
        -- Replace this with your actual policy requirements
        EXECUTE format('CREATE POLICY default_select_%I ON %I.%I FOR SELECT TO %I USING (true)', username, schema_name, table_record.table_name, username);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT public.enable_rls_for_schema('inventory_archive', 'anon');
SELECT public.enable_rls_for_schema('lookup', 'anon');

SELECT public.enable_rls_for_schema('inventory_archive', 'ti_read');
SELECT public.enable_rls_for_schema('lookup', 'ti_read'); 


-- DROP SELECT ACCESS FOR ANON
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.edges;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.position;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.plot_coordinates;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.plot_landmark;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.subplots_relative_position;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.tree_coordinates;


-- PUBLIC RLS

-- rls INSERT public.organizations where user_profile.is_admin = true 
create policy "Enable insert for authenticated users only"
on "public"."organizations"
as PERMISSIVE
for INSERT
to authenticated
WITH CHECK (auth.uid() = created_by OR EXISTS (
    SELECT 1
    FROM public.users_profile
    WHERE id = auth.uid() AND is_admin = true
));

-- Bestehende SELECT-Policy beibehalten oder anpassen
create policy "Enable read access for all users"
on "public"."organizations"
as PERMISSIVE
for SELECT
to public
USING (auth.uid() = created_by OR EXISTS (
    SELECT 1
    FROM public.users_profile
    WHERE id = auth.uid() AND is_admin = true
));

-- Neue UPDATE-Policy hinzufügen
create policy "Enable update for users based on email"
on "public"."organizations"
as PERMISSIVE
for UPDATE
to public
using (auth.uid() = created_by OR EXISTS (
    SELECT 1
    FROM public.users_profile
    WHERE id = auth.uid() AND is_admin = true
))  -- Prüft vor dem Update, ob der Benutzer der Ersteller ist
    WITH CHECK (auth.uid() = created_by OR EXISTS (
    SELECT 1
    FROM public.users_profile
    WHERE id = auth.uid() AND is_admin = true
));  -- Stellt sicher, dass created_by nicht geändert wird

