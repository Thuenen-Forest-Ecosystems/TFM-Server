CREATE OR REPLACE FUNCTION public.enable_rls_for_schema(
        schema_name TEXT,
        usernames TEXT [] DEFAULT ARRAY ['anon']
    ) RETURNS VOID AS $$
DECLARE table_record RECORD;
policy_name TEXT;
role_list TEXT;
BEGIN -- Convert the array of usernames to a comma-separated list for the SQL command
SELECT string_agg(quote_ident(username), ', ') INTO role_list
FROM unnest(usernames) AS username;
-- Loop through all tables in the specified schema
FOR table_record IN
SELECT table_name
FROM information_schema.tables
WHERE table_schema = schema_name
    AND table_type = 'BASE TABLE' LOOP -- Enable RLS for each table
    EXECUTE format(
        'ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY',
        schema_name,
        table_record.table_name
    );
EXECUTE format(
    'ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY',
    schema_name,
    table_record.table_name
);
-- Create a policy name based on the first role or a generic name
policy_name := 'default_select_' || array_to_string(usernames, '_and_');
-- Try to drop existing policy first to avoid conflicts
BEGIN EXECUTE format(
    'DROP POLICY IF EXISTS %I ON %I.%I',
    policy_name,
    schema_name,
    table_record.table_name
);
EXCEPTION
WHEN OTHERS THEN -- Ignore errors from non-existent policies
END;
-- Create a single policy that applies to all specified roles
EXECUTE format(
    'CREATE POLICY %I ON %I.%I FOR SELECT TO %s USING (true)',
    policy_name,
    schema_name,
    table_record.table_name,
    role_list
);
END LOOP;
END;
$$ LANGUAGE plpgsql;
SELECT public.enable_rls_for_schema(
        'inventory_archive',
        ARRAY ['ti_read', 'authenticated']
    );
SELECT public.enable_rls_for_schema('inventory_archive', ARRAY ['anon']);
SELECT public.enable_rls_for_schema(
        'lookup',
        ARRAY ['anon', 'ti_read', 'authenticated']
    );
-- DROP SELECT ACCESS FOR ANON
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.edges;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.edges_coordinates;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.position;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.plot_coordinates;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.plot_support_points;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.subplots_relative_position_coordinates;
DROP POLICY IF EXISTS default_select_anon ON inventory_archive.tree_coordinates;
-- PUBLIC RLS
-- rls INSERT public.organizations where user_profile.is_admin = true 
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.organizations;
create policy "Enable insert for authenticated users only" on "public"."organizations" as PERMISSIVE for
INSERT to authenticated WITH CHECK (
        auth.uid() = created_by
        OR EXISTS (
            SELECT 1
            FROM public.users_profile
            WHERE id = auth.uid()
                AND is_admin = true
        )
    );
-- Bestehende SELECT-Policy beibehalten oder anpassen
DROP POLICY IF EXISTS "Enable read access for all users" ON public.organizations;
create policy "Enable read access for all users" on "public"."organizations" as PERMISSIVE for
SELECT to public USING (
        auth.uid() = created_by
        OR EXISTS (
            SELECT 1
            FROM public.users_profile
            WHERE id = auth.uid()
                AND is_admin = true
        )
    );
-- Create an RLS policy for updating public.users_profile
DROP POLICY IF EXISTS "update_same_org_admin_policy" ON public.users_profile;
CREATE POLICY "update_same_org_admin_policy" ON public.users_profile AS PERMISSIVE FOR
UPDATE TO authenticated USING (
        EXISTS (
            SELECT 1
            FROM public.users_profile AS up
            WHERE up.id = auth.uid()
                AND up.organization_id = public.users_profile.organization_id
                AND up.is_organization_admin = true
        )
    ) WITH CHECK (
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
CREATE OR REPLACE FUNCTION public.get_user_profile_info(user_id uuid) RETURNS TABLE (organization_id uuid, is_admin boolean) LANGUAGE sql SECURITY DEFINER AS $$
SELECT organization_id,
    is_admin
FROM public.users_profile
WHERE id = user_id;
$$;
-- Create a fixed policy using the helper function
CREATE POLICY "select_same_organization_policy" ON public.users_profile AS PERMISSIVE FOR
SELECT TO authenticated USING (
        -- User can see their own profile
        auth.uid() = id
        OR -- User can see profiles in the same organization
        (
            SELECT p.organization_id
            FROM public.get_user_profile_info(auth.uid()) p
        ) = organization_id
        OR -- Admins can see all profiles
        (
            SELECT p.is_admin
            FROM public.get_user_profile_info(auth.uid()) p
        ) = true
    );
-- Neue UPDATE-Policy hinzufügen
DROP POLICY IF EXISTS "Enable update for same user and admin" ON public.organizations;
create policy "Enable update for same user and admin" on "public"."organizations" as PERMISSIVE for
UPDATE to public using (
        auth.uid() = created_by
        OR EXISTS (
            SELECT 1
            FROM public.users_profile
            WHERE id = auth.uid()
                AND is_admin = true
        )
    ) -- Prüft vor dem Update, ob der Benutzer der Ersteller ist
    WITH CHECK (
        auth.uid() = created_by
        OR EXISTS (
            SELECT 1
            FROM public.users_profile
            WHERE id = auth.uid()
                AND is_admin = true
        )
    );
-- Stellt sicher, dass created_by nicht geändert wird
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
DROP POLICY IF EXISTS "troop_member_read_policy" ON public.troop;
CREATE POLICY "troop_member_read_policy" ON public.troop FOR
SELECT USING (true);
-- ============================================================================
-- POLICIES: organizations
-- ============================================================================
-- Users can access organizations they are members of or parent organizations
-- ============================================================================
-- SELECT: View organizations user has access to
DROP POLICY IF EXISTS "Enable all access for authenticated users with same parent_organization_id" ON organizations;
CREATE POLICY "Enable all access for authenticated users with same parent_organization_id" ON organizations AS PERMISSIVE FOR
SELECT TO authenticated USING (
        EXISTS (
            SELECT 1
            FROM public.users_permissions up
            WHERE up.user_id = auth.uid()
                AND (
                    up.organization_id = organizations.id
                    OR up.organization_id = organizations.parent_organization_id
                )
        )
    );
-- ALL: Modify organizations user has access to
DROP POLICY IF EXISTS "Enable all access for authenticated users with same organization_id or parent_organization_id" ON organizations;
CREATE POLICY "Enable all access for authenticated users with same organization_id or parent_organization_id" ON organizations AS PERMISSIVE FOR ALL TO authenticated USING (
    EXISTS (
        SELECT 1
        FROM public.users_permissions up
        WHERE up.user_id = auth.uid()
            AND (
                up.organization_id = organizations.id
                OR up.organization_id = organizations.parent_organization_id
            )
    )
) WITH CHECK (
    EXISTS (
        SELECT 1
        FROM public.users_permissions up
        WHERE up.user_id = auth.uid()
            AND (
                up.organization_id = organizations.id
                OR up.organization_id = organizations.parent_organization_id
            )
    )
);
-- ============================================================================
-- POLICIES: troop
-- ============================================================================
-- Users can access troops within their organizations
-- ============================================================================
DROP POLICY IF EXISTS "Enable all access for authenticated users of same organization_id" ON troop;
CREATE POLICY "Enable all access for authenticated users of same organization_id" ON troop AS PERMISSIVE FOR ALL TO authenticated USING (
    organization_id IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    )
) WITH CHECK (
    organization_id IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    )
);
-- ============================================================================
-- POLICIES: organizations_lose
-- ============================================================================
-- Users can access lose within their organizations
-- ============================================================================
DROP POLICY IF EXISTS "Lose Enable all access for authenticated users of same organization_id" ON organizations_lose;
CREATE POLICY "Lose Enable all access for authenticated users of same organization_id" ON organizations_lose AS PERMISSIVE FOR ALL TO authenticated USING (
    organization_id IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    )
) WITH CHECK (
    organization_id IN (
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    )
);
-- ============================================================================
-- POLICIES: users_permissions
-- ============================================================================
-- All authenticated users can view permissions (for collaboration)
-- ============================================================================
DROP POLICY IF EXISTS "Enable users with own role equals organization_admin and same organization_id" ON "public"."users_permissions";
CREATE POLICY "Enable users with own role equals organization_admin and same organization_id" ON "public"."users_permissions" AS PERMISSIVE FOR
SELECT TO authenticated USING (true);
-- ============================================================================
-- POLICIES: records
-- ============================================================================
-- Users can access records assigned to their organizations or troops
-- Root organization users can access all records
-- ============================================================================
-- SELECT: View records user has access to
DROP POLICY IF EXISTS "Enable SELECT access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON "records";
CREATE POLICY "Enable SELECT access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON "records" AS PERMISSIVE FOR
SELECT TO authenticated USING (
        -- Root organization users can see all records
        EXISTS (
            SELECT 1
            FROM public.organizations org
                JOIN public.users_permissions up ON org.id = up.organization_id
            WHERE up.user_id = auth.uid()
                AND org.type = 'root'
        )
        OR -- Users can see records assigned to their organizations
        responsible_state IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
        OR responsible_provider IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
        OR responsible_troop IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
    );
-- UPDATE: Modify records user has access to
DROP POLICY IF EXISTS "Enable UPDATE access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON "records";
CREATE POLICY "Enable UPDATE access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON "records" AS PERMISSIVE FOR
UPDATE TO authenticated USING (
        -- Root organization or admin users
        EXISTS (
            SELECT 1
            FROM public.organizations org
                JOIN public.users_permissions up ON org.id = up.organization_id
            WHERE up.user_id = auth.uid()
                AND org.type = 'root'
        )
        OR EXISTS (
            SELECT 1
            FROM public.users_profile prof
            WHERE prof.id = auth.uid()
                AND prof.is_admin = true
        )
        OR -- Users with organizational access
        responsible_state IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
        OR responsible_provider IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
        OR responsible_troop IN (
            SELECT t.id
            FROM public.troop t
                JOIN public.users_permissions up ON t.organization_id = up.organization_id
            WHERE up.user_id = auth.uid()
        )
    ) WITH CHECK (
        -- Same constraints for updates
        EXISTS (
            SELECT 1
            FROM public.organizations org
                JOIN public.users_permissions up ON org.id = up.organization_id
            WHERE up.user_id = auth.uid()
                AND org.type = 'root'
        )
        OR EXISTS (
            SELECT 1
            FROM public.users_profile prof
            WHERE prof.id = auth.uid()
                AND prof.is_admin = true
        )
        OR responsible_state IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
        OR responsible_provider IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
        OR responsible_troop IN (
            SELECT t.id
            FROM public.troop t
                JOIN public.users_permissions up ON t.organization_id = up.organization_id
            WHERE up.user_id = auth.uid()
        )
    );
-- ============================================================================
-- POLICIES: record_changes
-- ============================================================================
-- Same access rules as records table for viewing audit history
-- ============================================================================
DROP POLICY IF EXISTS "record_changes: Enable SELECT access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON "record_changes";
CREATE POLICY "record_changes: Enable SELECT access for authenticated users with same organization_id of responsible_state, responsible_provider or responsible_troop" ON "record_changes" AS PERMISSIVE FOR
SELECT TO authenticated USING (
        -- Root organization users can see all changes
        EXISTS (
            SELECT 1
            FROM public.organizations org
                JOIN public.users_permissions up ON org.id = up.organization_id
            WHERE up.user_id = auth.uid()
                AND org.type = 'root'
        )
        OR -- Users can see changes for records assigned to their organizations
        responsible_state IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
        OR responsible_provider IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
        OR responsible_troop IN (
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
    );