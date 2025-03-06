SET search_path TO public;

-- CREATE troop table
-- https://supabase.com/docs/guides/database/postgres/custom-claims-and-role-based-access-control-rbac?queryGroups=language&language=plpgsql
-- https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook
CREATE TABLE IF NOT EXISTS troop (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    name text NULL,
    user_id uuid NOT NULL
);

ALTER TABLE troop ENABLE ROW LEVEL SECURITY;

-- Create the auth hook function
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
as $$
  declare
    claims jsonb;
    troop_id uuid;
  begin
    -- Fetch the user role in the troop table
    select id into troop_id from public.troop where user_id = (event->>'user_id')::uuid;

    claims := event->'claims';

    if troop_id is not null then
      -- Set the claim
      claims := jsonb_set(claims, '{troop_id}', to_jsonb(troop_id));
    else
      claims := jsonb_set(claims, '{troop_id}', 'null');
    end if;

    -- Update the 'claims' object in the original event
    event := jsonb_set(event, '{claims}', claims);

    -- Return the modified or original event
    return event;
  end;
$$;

grant usage on schema public to supabase_auth_admin;

grant execute
  on function public.custom_access_token_hook
  to supabase_auth_admin;

revoke execute
  on function public.custom_access_token_hook
  from authenticated, anon, public;

grant all
  on table public.troop
to supabase_auth_admin;

revoke all
  on table public.troop
  from authenticated, anon, public;

create policy "Allow auth admin to read user roles" ON public.troop
as permissive for select
to supabase_auth_admin
using (true)