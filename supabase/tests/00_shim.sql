-- Local stand-in for the bits Supabase provides, so the real migrations can run
-- unchanged against a plain Postgres 15.
create schema if not exists auth;
create schema if not exists storage;

create table if not exists auth.users (id uuid primary key, email text);

-- auth.uid() reads a session GUC so a test can "log in" as any user.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('test.uid', true), '')::uuid
$$;

create table if not exists storage.buckets (
  id text primary key, name text, public boolean default false);
create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(), bucket_id text, name text);
alter table storage.objects enable row level security;

-- Supabase ships this; the storage policies use it to scope uploads to a folder.
create or replace function storage.foldername(name text) returns text[]
language sql immutable as $$
  select string_to_array(regexp_replace(name, '/[^/]*$', ''), '/')
$$;

-- the role PostgREST uses for signed-in users (RLS actually applies to it)
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end $$;
grant usage on schema public, storage to authenticated;
