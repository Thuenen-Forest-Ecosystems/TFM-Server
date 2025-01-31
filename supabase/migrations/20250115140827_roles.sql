CREATE ROLE ti_read WITH LOGIN PASSWORD 'qjze5aruuR9vJz';


GRANT CONNECT ON DATABASE postgres TO ti_read;
GRANT USAGE ON SCHEMA public TO ti_read;
GRANT SELECT ON ALL TABLES IN SCHEMA inventory_archive TO ti_read;
