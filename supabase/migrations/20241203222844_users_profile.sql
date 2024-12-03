-- https://supabase.com/docs/guides/auth/managing-user-data?queryGroups=language&language=js


create table public.users_profile (
  id uuid not null references auth.users on delete cascade,
  supervisor_id uuid references auth.users on delete set null,
  
  users_name text,
  users_company text,

  primary key (id)
);

alter table public.users_profile enable row level security;

-- Allow logged-in users or supervisor to view profile
create policy "Allow logged-in users to view their own profile" on public.users_profile for select using (auth.uid() = id or auth.uid() = supervisor_id);

-- Allow logged-in users to update their own profile
create policy "Allow logged-in users to update their own profile" on public.users_profile for update using (auth.uid() = id);

-- inserts a row into public.users_profile
create function public.setup_new_user_profile()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.users_profile (id, users_name, users_company)
  values (new.id, new.raw_user_meta_data ->> 'name', new.raw_user_meta_data ->> 'company');
  return new;
end;
$$;

-- trigger the function every time a user is created
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.setup_new_user_profile();