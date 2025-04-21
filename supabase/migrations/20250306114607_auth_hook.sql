SET search_path TO public;

DROP function IF EXISTS public.custom_access_token_hook;

-- Create the auth hook function with extensive debugging
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
VOLATILE
as $$
  declare
    claims jsonb;
    claim_troop_id uuid;
    claim_organization_id uuid;
    claim_state_responsible smallint;
    claim_is_admin BOOLEAN;
    user_id_text text;
    user_id_uuid uuid;
    found_user_record boolean := false;
    record_count integer;
  begin
    -- Debug the input
    RAISE NOTICE 'Event received: %', event;

    -- Extract user_id safely
    user_id_text := event->>'user_id';
    RAISE NOTICE 'User ID text: %', user_id_text;
    
    -- Count total users in profile table
    SELECT COUNT(*) INTO record_count FROM public.users_profile;
    RAISE NOTICE 'Total user profiles in database: %', record_count;

    -- Check if we can cast to UUID
    BEGIN
      user_id_uuid := user_id_text::uuid;
      RAISE NOTICE 'User ID converted to UUID: %', user_id_uuid;
    EXCEPTION WHEN others THEN
      RAISE NOTICE 'Failed to convert user_id to UUID: %', SQLERRM;
      -- Still proceed with the original user_id
    END;

    -- Check if user exists in users_profile first
    SELECT 
      organization_id  -- Using MAX to get a single value when COUNT > 0
    INTO 
      claim_organization_id
    FROM public.users_profile
    WHERE id = user_id_uuid Limit 1;



    -- Try to get data from users_profile with error handling
    BEGIN
      SELECT 
        COALESCE(users_profile.state_responsible, 0), 
        COALESCE(users_profile.is_admin, FALSE)
      INTO claim_state_responsible, claim_is_admin
      FROM public.users_profile
      WHERE id = user_id_uuid;
      
      IF NOT FOUND THEN
        RAISE NOTICE 'No user profile found for ID: %', user_id_uuid;
        claim_state_responsible := 0;
        claim_is_admin := FALSE;
      ELSE
        RAISE NOTICE 'Profile found! state_responsible: %, is_admin: %', 
          claim_state_responsible, claim_is_admin;
      END IF;
    EXCEPTION WHEN others THEN
      RAISE NOTICE 'Error fetching user profile: %', SQLERRM;
      claim_state_responsible := 0;
      claim_is_admin := FALSE;
    END;

    -- Fetch the user role in the troop table
    BEGIN
      SELECT id INTO claim_troop_id 
      FROM public.troop 
      WHERE user_id_uuid = ANY(user_ids);
      
      IF NOT FOUND THEN
        RAISE NOTICE 'No troop found for user: %', user_id_uuid;
      ELSE
        RAISE NOTICE 'Troop found: %', claim_troop_id;
      END IF;
    EXCEPTION WHEN others THEN
      RAISE NOTICE 'Error fetching troop: %', SQLERRM;
    END;

    -- Extract claims from event
    claims := event->'claims';
    IF claims IS NULL THEN
      RAISE NOTICE 'Claims is NULL, creating empty object';
      claims := '{}'::jsonb;
    END IF;

    -- Set the claims
    claims := jsonb_set(claims, '{troop_id}', 
              CASE WHEN claim_troop_id IS NULL THEN 'null' ELSE to_jsonb(claim_troop_id) END);
    claims := jsonb_set(claims, '{state_responsible}', to_jsonb(claim_state_responsible));
    claims := jsonb_set(claims, '{is_admin}', to_jsonb(claim_is_admin));
    claims := jsonb_set(claims, '{organization_id}',
              CASE WHEN claim_organization_id IS NULL THEN 'null' ELSE to_jsonb(claim_organization_id) END);

    RAISE NOTICE 'Final claims: %', claims;
    
    -- Update the event
    event := jsonb_set(event, '{claims}', claims);

    RETURN event;
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'Uncaught exception in hook: %', SQLERRM;
    RETURN event;
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
to supabase_auth_admin, authenticated;

revoke all
  on table public.troop
  from anon, public;

create policy "Allow auth admin to read user roles" ON public.users_profile
as permissive for select
to supabase_auth_admin
using (true);