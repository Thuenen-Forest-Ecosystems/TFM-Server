SET search_path TO public;

CREATE TYPE "enum_interval_name" AS ENUM (
    'bwi1987',
    'bwi1992',
    'bwi2002',
    'ci2008',
    'bwi2012',
    'ci2017',
    'ci2022',
    'ci2027'
);

ALTER TYPE "enum_interval_name" OWNER TO "postgres";