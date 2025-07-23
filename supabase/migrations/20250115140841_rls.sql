CREATE OR REPLACE FUNCTION public.enable_rls_for_schema(
    schema_name TEXT, 
    usernames TEXT[] DEFAULT ARRAY['anon']
) RETURNS VOID AS $$
DECLARE
    table_record RECORD;
    policy_name TEXT;
    role_list TEXT;
BEGIN
    -- Convert the array of usernames to a comma-separated list for the SQL command
    SELECT string_agg(quote_ident(username), ', ') INTO role_list FROM unnest(usernames) AS username;
    
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
        
        -- Create a policy name based on the first role or a generic name
        policy_name := 'default_select_' || array_to_string(usernames, '_and_');
        
        -- Try to drop existing policy first to avoid conflicts
        BEGIN
            EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', 
                           policy_name, schema_name, table_record.table_name);
        EXCEPTION WHEN OTHERS THEN
            -- Ignore errors from non-existent policies
        END;
        
        -- Create a single policy that applies to all specified roles
        EXECUTE format('CREATE POLICY %I ON %I.%I FOR SELECT TO %s USING (true)', 
                      policy_name, schema_name, table_record.table_name, role_list);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT public.enable_rls_for_schema('inventory_archive', ARRAY['ti_read', 'authenticated']);
SELECT public.enable_rls_for_schema('inventory_archive', ARRAY['anon']);
SELECT public.enable_rls_for_schema('lookup', ARRAY['anon', 'ti_read', 'authenticated']);


-- DROP SELECT ACCESS FOR ANON
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.edges;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.edges_coordinates;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.position;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.plot_coordinates;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.plot_landmark;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.subplots_relative_position_coordinates;
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

-- Create an RLS policy for updating public.users_profile
CREATE POLICY "update_same_org_admin_policy"
ON public.users_profile
AS PERMISSIVE
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.users_profile AS up
        WHERE up.id = auth.uid()
        AND up.organization_id = public.users_profile.organization_id
        AND up.is_organization_admin = true
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM public.users_profile AS up
        WHERE up.id = auth.uid()
        AND up.organization_id = public.users_profile.organization_id
        AND up.is_organization_admin = true
    )
);
-- Drop the problematic policy first
DROP POLICY IF EXISTS "select_same_organization_policy" ON public.users_profile;

-- Create a security definer function to safely get user organization and admin status
CREATE OR REPLACE FUNCTION public.get_user_profile_info(user_id uuid)
RETURNS TABLE (organization_id uuid, is_admin boolean)
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT organization_id, is_admin
    FROM public.users_profile
    WHERE id = user_id;
$$;

-- Create a fixed policy using the helper function
CREATE POLICY "select_same_organization_policy"
ON public.users_profile
AS PERMISSIVE
FOR SELECT
TO authenticated
USING (
    -- User can see their own profile
    auth.uid() = id
    OR 
    -- User can see profiles in the same organization
    (
        SELECT p.organization_id
        FROM public.get_user_profile_info(auth.uid()) p
    ) = organization_id
    OR
    -- Admins can see all profiles
    (
        SELECT p.is_admin
        FROM public.get_user_profile_info(auth.uid()) p
    ) = true
);

-- Neue UPDATE-Policy hinzufügen
create policy "Enable update for same user and admin"
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



-- Function to check if the current user is a member of a troop
--CREATE OR REPLACE FUNCTION public.is_troop_member(troop_id uuid)
--RETURNS boolean
--LANGUAGE sql
--SECURITY DEFINER
--AS $$
--    SELECT EXISTS (
--        SELECT 1 
--        FROM public.troop
--        WHERE id = troop_id 
--        AND (
--            supervisor_id = auth.uid() 
--            OR auth.uid()::uuid = ANY(user_ids)
--        )
--    );
--$$;

-- Enable RLS
ALTER TABLE public.records ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "record_access_policy" ON public.records;

-- Create a single unified policy for all operations
--CREATE POLICY "record_access_policy"
--ON public.records
--FOR ALL
--USING (
--    -- User is record supervisor
--    supervisor_id = auth.uid()
--    OR
--    -- User is a member of the troop associated with the record
--    public.is_troop_member(troop_id)
--    OR
--    -- User is an admin
--    EXISTS (
--        SELECT 1
--        FROM public.users_profile
--        WHERE id = auth.uid() AND is_admin = true
--    )
--)
--WITH CHECK (
--    -- Same conditions for write operations
--    supervisor_id = auth.uid()
--    OR
--    public.is_troop_member(troop_id)
--    OR
--    EXISTS (
--        SELECT 1
--        FROM public.users_profile
--        WHERE id = auth.uid() AND is_admin = true
--    )
--);



-- Troop
-- Create policy for supervisors to have full access to their troops
--CREATE POLICY "troop_supervisor_all_policy"
--ON public.troop
--FOR ALL
--USING (supervisor_id = auth.uid())
--WITH CHECK (supervisor_id = auth.uid());

-- Create policy for troop members to read troops they belong to
CREATE POLICY "troop_member_read_policy"
ON public.troop
FOR SELECT
USING (true);