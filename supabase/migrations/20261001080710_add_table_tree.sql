create table if not exists trees (
  id bigint primary key generated always as identity,
  name text not null,
  dbh text,
  created_at timestamptz default now()
);