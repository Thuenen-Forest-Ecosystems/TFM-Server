pg_dump -U postgres -h 127.0.0.1 -p 54322 postgres -s -t public.records -f records.sql
--natürlich als shell script
-- pg_dump -h 127.0.0.1 -p 54322  -U postgres  -d postgres -n supabase_migrations  --data-only --enable-row-security 
psql -U postgres -h 127 