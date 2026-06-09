-- Create denormalized table for records_messages with access control fields
-- Users write to this table via PowerSync, triggers auto-populate access control fields
DROP TABLE IF EXISTS public.records_messages CASCADE;
CREATE TABLE public.records_messages (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    note text NULL,
    user_id uuid NULL,
    records_id uuid NOT NULL,
    object_name SMALLINT NULL,
    -- Denormalized access control fields from records table
    responsible_administration uuid NULL,
    responsible_state uuid NULL,
    responsible_provider uuid NULL,
    responsible_troop uuid NULL,
    is_system_message boolean NOT NULL DEFAULT false,
    CONSTRAINT records_messages_pkey PRIMARY KEY (id),
    CONSTRAINT records_messages_id_key UNIQUE (id),
    CONSTRAINT records_messages_records_id_fkey FOREIGN KEY (records_id) REFERENCES records (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT object_name_id_fkey FOREIGN KEY (object_name) REFERENCES lookup.lookup_object_type (code)
) TABLESPACE pg_default;
-- Grant appropriate permissions
GRANT SELECT,
    INSERT,
    UPDATE,
    DELETE ON public.records_messages TO authenticated;
GRANT SELECT ON public.records_messages TO anon;
-- Function to auto-populate access control fields from records table
CREATE OR REPLACE FUNCTION public.populate_records_messages_access_control() RETURNS TRIGGER AS $$ BEGIN -- Populate access control fields from the linked record
SELECT r.responsible_administration,
    r.responsible_state,
    r.responsible_provider,
    r.responsible_troop INTO NEW.responsible_administration,
    NEW.responsible_state,
    NEW.responsible_provider,
    NEW.responsible_troop
FROM public.records r
WHERE r.id = NEW.records_id;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- Trigger to auto-populate on INSERT or when records_id changes
CREATE TRIGGER populate_records_messages_access_control_trigger BEFORE
INSERT
    OR
UPDATE OF records_id ON public.records_messages FOR EACH ROW EXECUTE FUNCTION public.populate_records_messages_access_control();
-- Function to update access control fields when the linked record changes
CREATE OR REPLACE FUNCTION public.update_records_messages_on_records_change() RETURNS TRIGGER AS $$ BEGIN
UPDATE public.records_messages
SET responsible_administration = NEW.responsible_administration,
    responsible_state = NEW.responsible_state,
    responsible_provider = NEW.responsible_provider,
    responsible_troop = NEW.responsible_troop
WHERE records_id = NEW.id;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- Trigger on records to cascade access control changes to messages
CREATE TRIGGER update_records_messages_on_records_change_trigger
AFTER
UPDATE ON public.records FOR EACH ROW
    WHEN (
        OLD.responsible_administration IS DISTINCT
        FROM NEW.responsible_administration
            OR OLD.responsible_state IS DISTINCT
        FROM NEW.responsible_state
            OR OLD.responsible_provider IS DISTINCT
        FROM NEW.responsible_provider
            OR OLD.responsible_troop IS DISTINCT
        FROM NEW.responsible_troop
    ) EXECUTE FUNCTION public.update_records_messages_on_records_change();
-- Unique constraint to allow idempotent upserts during migration
ALTER TABLE public.records_messages
ADD CONSTRAINT records_messages_records_id_created_at_key UNIQUE (records_id, created_at);
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