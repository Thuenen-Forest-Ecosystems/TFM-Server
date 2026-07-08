-- TFM-Server/supabase/migrations/20260605120000_add_admin_sync_selections.sql

CREATE TABLE IF NOT EXISTS public.organization_admin_sync_selections (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at timestamptz NOT NULL DEFAULT now(),
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    record_id uuid NOT NULL REFERENCES public.records(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE, -- Optional: to know who made the selection
    CONSTRAINT unique_org_record_selection UNIQUE (organization_id, record_id)
);

ALTER TABLE public.organization_admin_sync_selections ENABLE ROW LEVEL SECURITY;

-- Allow admins to manage their own organization's selections
CREATE POLICY "Allow admin to manage sync selections"
ON public.organization_admin_sync_selections
FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.users_permissions
        WHERE users_permissions.user_id = auth.uid()
        AND users_permissions.organization_id = organization_admin_sync_selections.organization_id
        AND users_permissions.is_organization_admin = true
    )
);

-- Allow admins to read selections for their organization
CREATE POLICY "Allow admin to read sync selections"
ON public.organization_admin_sync_selections
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.users_permissions
        WHERE users_permissions.user_id = auth.uid()
        AND users_permissions.organization_id = organization_admin_sync_selections.organization_id
        AND users_permissions.is_organization_admin = true
    )
);
