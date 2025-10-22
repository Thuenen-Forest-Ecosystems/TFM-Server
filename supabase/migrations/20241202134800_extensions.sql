CREATE EXTENSION postgis;
create extension http with schema extensions;

CREATE SCHEMA IF NOT EXISTS topology;
CREATE EXTENSION IF NOT EXISTS postgis_topology WITH SCHEMA topology;

-- add pg_jsonschema in schema extensions
CREATE EXTENSION IF NOT EXISTS pg_jsonschema WITH SCHEMA extensions;

-- add moddatetime extension
create extension if not exists moddatetime schema extensions;
