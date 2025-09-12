SELECT * FROM public.records  LIMIT 5;

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE SERVER remote_server
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (host '134.110.100.75', port '3389', dbname 'postgres');
--Replace:

-- remote_host with the IP address or hostname of the remote server.
-- 5432 with the port number (default for PostgreSQL).
-- remote_db with the name of the remote database.
-- 3. Create a User Mapping
-- Map a local user to a remote user for authentication:

-- Sql

-- Code kopieren
CREATE USER MAPPING FOR postgres
SERVER remote_server
OPTIONS (user 'postgres', password 'ESG34Epm97hndHHUVe5YvwV');
-- Replace:

-- local_user with the local PostgreSQL user.
-- remote_user and remote_password with the credentials of the remote PostgreSQL user.
-- 4. Import Schema or Create Foreign Tables
-- You can either import all tables from a schema or define specific foreign tables.

-- Option A: Import All Tables from a Schema
-- Sql

CREATE SCHEMA IF NOT EXISTS public1

--Code kopieren
IMPORT FOREIGN SCHEMA public
FROM SERVER remote_server
INTO public1;


-- Replace:

-- remote_schema with the schema name on the remote database.
-- local_schema with the schema name in the local database.
-- Option B: Create Specific Foreign Tables
-- Sql

Code kopieren
CREATE FOREIGN TABLE local_table (
    id INT,
    name TEXT
)
SERVER remote_server
OPTIONS (schema_name 'remote_schema', table_name 'remote_table');
Replace:

local_table with the name of the table in the local database.
remote_schema and remote_table with the schema and table name on the remote database.
5. Query the Remote Data
You can now query the remote data as if it were local:

Sql

Code kopieren
SELECT * FROM local_schema.local_table;
6. Optional: Grant Permissions
If other users need access to the foreign tables, grant them the necessary permissions:

Sql

Code kopieren
GRANT USAGE ON FOREIGN SERVER remote_server TO postgres;
GRANT SELECT ON ALL TABLES IN SCHEMA public1 TO postgres;
This setup allows seamless querying between PostgreSQL databases. Let me know if you need further clarification! 😊

