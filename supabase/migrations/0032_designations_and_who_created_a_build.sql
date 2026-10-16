-- 0032_designations_and_who_created_a_build.sql
--
-- Two small facts the app had nowhere to put.
--
-- **A designation.** `profiles.role` says which department somebody is in —
-- admin, pm, workshop — and that is what every permission is built on. It does
-- not say what they *do* there, and a growing company needs both: two admins
-- may be Operations and Finance, two workshop members a supervisor and a
-- fitter. The role stays the permission; the designation is what people call
-- each other, shown wherever a name is.
--
-- `is_supervisor` is the one piece of it the app has to *act* on rather than
-- display: a workshop supervisor is who a project manager hands workshop work
-- to, and who then breaks it down for their own people. Kept as a flag rather
-- than a magic designation string so the rule never depends on how somebody
-- typed a job title, and deliberately not a `user_role`, because a supervisor
-- is still workshop — every stage rule, every discipline match and every RLS
-- policy for them is the workshop one.
--
-- **Who created a build.** With one admin it was obvious. With several, the
-- owner wants to filter the fleet by the admin who onboarded each build — and
-- nothing recorded it. `fn_audit('onboard_project', …)` has the trail, but the
-- audit log is admin-only, unindexed for this, and not what a list should be
-- filtered on.
--
-- Idempotent: three additive columns, one backfill from the audit log.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. What somebody does, beside what they may do
-- ════════════════════════════════════════════════════════════════════════════

alter table public.profiles
  add column if not exists designation   text,
  add column if not exists is_supervisor boolean not null default false;

comment on column public.profiles.designation is
  'What this person does — "Operations", "Senior Fitter". Display only; `role` remains the permission.';
comment on column public.profiles.is_supervisor is
  'A workshop supervisor: the person a PM hands workshop work to, who then assigns it on. Not a role — they are still workshop.';

-- A supervisor only means anything inside workshop. Nothing enforces a
-- department on a free-text designation, but this one drives behaviour, so it
-- is worth being exact about.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_supervisor_is_workshop') then
    alter table public.profiles
      add constraint profiles_supervisor_is_workshop
      check (not is_supervisor or role = 'workshop') not valid;
  end if;
end $$;


-- ════════════════════════════════════════════════════════════════════════════
-- 2. Which admin brought this build in
-- ════════════════════════════════════════════════════════════════════════════

alter table public.projects
  add column if not exists created_by uuid references profiles(id) on delete set null;

comment on column public.projects.created_by is
  'The admin who onboarded this build. ON DELETE SET NULL like every other nullable FK to profiles (0009).';

create index if not exists idx_projects_created_by on public.projects(created_by);

-- Backfill from the audit log, which has recorded this since 0009 even though
-- nothing could read it usefully. Builds onboarded before auditing, or whose
-- admin has since been offboarded, keep a null — which the filter shows as
-- "Not recorded" rather than guessing.
update public.projects p
   set created_by = a.actor_id
  from (
    select distinct on (entity_id) entity_id, actor_id
      from audit_log
     where action = 'onboard_project'
       and entity_type = 'project'
       and actor_id is not null
     order by entity_id, created_at
  ) a
 where a.entity_id = p.id
   and p.created_by is null;

-- New builds record it as they are created. `auth.uid()` is the admin doing it;
-- a row written with no JWT (seed, SQL editor) simply has none.
create or replace function public.trg_project_created_by() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.created_by is null then
    new.created_by := auth.uid();
  end if;
  return new;
end $$;

drop trigger if exists t_project_created_by on public.projects;
create trigger t_project_created_by before insert on public.projects
  for each row execute function public.trg_project_created_by();

-- ════════════════════════════════════════════════════════════════════════════
-- 3. Neither of these is yours to set about yourself
--
-- 0026 let a member edit their own row — name, phone, avatar, and accepting an
-- invite — with a trigger holding role, email, team and status on the admin's
-- side. Two new columns land in that same gap, and one of them *matters*:
-- `is_supervisor` decides who a PM can hand workshop work to and who may then
-- assign it on. Left unguarded, any workshop member could promote themselves.
--
-- Body is 0026's, with the two columns added to the list. Nothing else changes.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.trg_profiles_self_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  if new.id is distinct from old.id then
    raise exception 'A profile id cannot change.' using errcode = '42501';
  end if;
  if new.id <> auth.uid() then return new; end if;   -- not the self-service path

  -- Yours to edit: full_name, phone, avatar_color — plus accepting the invite.
  if new.role        is distinct from old.role
     or new.email       is distinct from old.email
     or new.created_by  is distinct from old.created_by
     or new.sub_team_id is distinct from old.sub_team_id
     or new.designation   is distinct from old.designation
     or new.is_supervisor is distinct from old.is_supervisor then
    raise exception 'Only an admin can change your role, email, team or designation.' using errcode = '42501';
  end if;
  -- Status: invited → active only. Nobody re-enables their own disabled login.
  if new.status is distinct from old.status
     and not (old.status = 'invited' and new.status = 'active') then
    raise exception 'Only an admin can change your account status.' using errcode = '42501';
  end if;
  return new;
end $$;
