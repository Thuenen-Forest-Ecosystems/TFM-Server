-- Create denormalized table for records_messages with access control fields
-- Users write to this table via PowerSync, triggers auto-populate access control fields
DROP TABLE IF EXISTS public.records_messages CASCADE;
CREATE TABLE public.records_messages (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    note text NULL,
    user_id uuid NULL,
    records_id uuid NOT NULL,
    object_name SMALLINT NOT NULL,
    -- Denormalized access control fields from records table
    responsible_administration uuid NULL,
    responsible_state uuid NULL,
    responsible_provider uuid NULL,
    responsible_troop uuid NULL,
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