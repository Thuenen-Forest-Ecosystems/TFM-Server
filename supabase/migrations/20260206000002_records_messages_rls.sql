-- ============================================================================
-- POLICIES: records_messages
-- ============================================================================
-- Users can access messages for records they have access to
-- Root organization users can access all messages
-- ============================================================================
-- Enable RLS
ALTER TABLE public.records_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.records_messages FORCE ROW LEVEL SECURITY;
-- SELECT: View messages for records user has access to
DROP POLICY IF EXISTS "Enable SELECT access for records_messages" ON public.records_messages;
CREATE POLICY "Enable SELECT access for records_messages" ON public.records_messages AS PERMISSIVE FOR
SELECT TO authenticated USING (
        -- Root organization users can see all messages
        EXISTS (
            SELECT 1
            FROM public.organizations org
                JOIN public.users_permissions up ON org.id = up.organization_id
            WHERE up.user_id = auth.uid()
                AND org.type = 'root'
        )
        OR -- Users can see messages for records assigned to their organizations
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
-- INSERT: Create messages for records user has access to
-- Note: On INSERT, responsible_* fields are NULL and populated by trigger
-- So we check access via the records_id foreign key instead
DROP POLICY IF EXISTS "Enable INSERT access for records_messages" ON public.records_messages;
CREATE POLICY "Enable INSERT access for records_messages" ON public.records_messages AS PERMISSIVE FOR
INSERT TO authenticated WITH CHECK (
        -- Root organization users can insert messages on any record
        EXISTS (
            SELECT 1
            FROM public.organizations org
                JOIN public.users_permissions up ON org.id = up.organization_id
            WHERE up.user_id = auth.uid()
                AND org.type = 'root'
        )
        OR -- Users can insert messages for records they have access to
        EXISTS (
            SELECT 1
            FROM public.records r
            WHERE r.id = records_messages.records_id
                AND (
                    r.responsible_state IN (
                        SELECT organization_id
                        FROM public.users_permissions
                        WHERE user_id = auth.uid()
                    )
                    OR r.responsible_provider IN (
                        SELECT organization_id
                        FROM public.users_permissions
                        WHERE user_id = auth.uid()
                    )
                    OR r.responsible_troop IN (
                        SELECT organization_id
                        FROM public.users_permissions
                        WHERE user_id = auth.uid()
                    )
                )
        )
    );
-- UPDATE: Modify messages user has access to
DROP POLICY IF EXISTS "Enable UPDATE access for records_messages" ON public.records_messages;
CREATE POLICY "Enable UPDATE access for records_messages" ON public.records_messages AS PERMISSIVE FOR
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
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
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
            SELECT organization_id
            FROM public.users_permissions
            WHERE user_id = auth.uid()
        )
    );
-- DELETE: Remove messages user has access to
DROP POLICY IF EXISTS "Enable DELETE access for records_messages" ON public.records_messages;
CREATE POLICY "Enable DELETE access for records_messages" ON public.records_messages AS PERMISSIVE FOR DELETE TO authenticated USING (
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
    OR -- Users can delete their own messages
    user_id = auth.uid()
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
        SELECT organization_id
        FROM public.users_permissions
        WHERE user_id = auth.uid()
    )
);