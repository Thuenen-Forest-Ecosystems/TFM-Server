SET search_path TO private_ci2027_001;

CREATE TABLE lookup_TEMPLATE (
    --id SERIAL PRIMARY KEY, // To be set by lookup table individualy
    --abbreviation varchar(10) UNIQUE NOT NULL,  // To be set by lookup table individualy
    name_de VARCHAR(150) NOT NULL,
    name_en VARCHAR(150) NOT NULL,
    interval enum_interval_name[] NOT NULL,
    sort INTEGER NOT NULL
);