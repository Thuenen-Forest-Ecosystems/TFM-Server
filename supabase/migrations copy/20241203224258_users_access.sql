create table public.users_access (
    id uuid not null references auth.users on delete cascade,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by uuid DEFAULT auth.uid() NOT NULL,
	modified_at TIMESTAMP DEFAULT NULL,
	modified_by uuid DEFAULT auth.uid() NOT NULL,
  
    interval text not null,
    plots_select_access uuid[],
    plots_update_access uuid[],

    primary key (id)
);

alter table public.users_access enable row level security;

-- Allow logged-in users to insert a row into users_access and update own rows
CREATE POLICY "Allow logged-in users to insert a row" 
ON public.users_access 
FOR INSERT 
WITH CHECK (auth.uid() = created_by);

-- Allow logged-in users to update own rows
CREATE POLICY "Allow logged-in users to update own rows" 
ON public.users_access 
FOR UPDATE 
USING (auth.uid() = created_by OR auth.uid() = modified_by);