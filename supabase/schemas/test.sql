create table test(
    id uuid not null default gen_random_uuid() primary key,
    name text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
)