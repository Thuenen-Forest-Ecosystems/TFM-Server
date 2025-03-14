SET search_path TO public;

-- Create the auth hook function
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
as $$
  declare
    claims jsonb;
    claim_troop_id uuid;
    claim_state_responsible smallint;
    claim_is_admin BOOLEAN;
  begin

    --
    select state_responsible, is_admin into claim_state_responsible, claim_is_admin from public.users_profile where id = (event->>'user_id')::uuid;

    -- Fetch the user role in the troop table
    select id into claim_troop_id from public.troop where user_id = (event->>'user_id')::uuid;

    claims := event->'claims';

    if claim_troop_id is not null then
      -- Set the claim
      claims := jsonb_set(claims, '{troop_id}', to_jsonb(claim_troop_id));
    else
      claims := jsonb_set(claims, '{troop_id}', 'null');
    end if;

    if claim_state_responsible is not null then
      -- Set the claim
      claims := jsonb_set(claims, '{state_responsible}', to_jsonb(claim_state_responsible));
    else
      claims := jsonb_set(claims, '{state_responsible}', 'null');
    end if;

    if claim_is_admin is not null then
      -- Set the claim
      claims := jsonb_set(claims, '{is_admin}', to_jsonb(claim_is_admin));
    else
      claims := jsonb_set(claims, '{is_admin}', 'null');
    end if;

    -- Update the 'claims' object in the original event
    event := jsonb_set(event, '{claims}', claims);

    -- Return the modified or original event
    return event;
  end;
$$;

grant usage on schema public to supabase_auth_admin;

grant select on table public.users_profile to supabase_auth_admin;
grant select on table public.troop to supabase_auth_admin;


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