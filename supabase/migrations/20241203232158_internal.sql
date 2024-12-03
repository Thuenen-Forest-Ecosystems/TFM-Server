-- Internal Schema to manage 


-- Create table to store company profiles and email domains for each company
create table public.companies_access (
  id uuid not null default gen_random_uuid(),

  company_name text not null,
  company_email_domain text not null,

  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
  modified_at TIMESTAMP DEFAULT NULL,
  modified_by uuid DEFAULT auth.uid() NULL,

  primary key (id)
);

alter table public.companies_access enable row level security;

-- insert Thühnen Institute as the first company
insert into public.companies_access (company_name, company_email_domain) values ('Thühnen Institute', 'thuenen.de');


-- Allow only people with company email domains to sign up
CREATE OR REPLACE FUNCTION public.check_user_domain() RETURNS TRIGGER AS $$
DECLARE
    user_domain TEXT;
BEGIN

    -- Extract the domain part of the user's email
    user_domain := substring(NEW.email FROM '@(.+)$');

    -- Check if the extracted domain exists in the public.companies_access table
    IF EXISTS (SELECT 1 FROM public.companies_access WHERE company_email_domain = user_domain) THEN
        RETURN NEW;
    ELSE
        raise exception 'INCORRECT_DOMAIN';
    END IF;

    ---IF NEW.email NOT LIKE '%@thuenen.de' THEN
    ---    raise exception 'INCORRECT_DOMAIN';
    ---END IF;
---
    ---RETURN NEW;
END;
$$ LANGUAGE plpgsql 
SECURITY DEFINER;

CREATE TRIGGER
    check_user_domain_trigger
    before INSERT ON auth.users
    FOR EACH ROW
    EXECUTE PROCEDURE public.check_user_domain();