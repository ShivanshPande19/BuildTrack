--
-- Atomic design-version numbering.
--
-- addVersion() in the app did read-max-then-insert: it read an artifact's
-- highest version_no and inserted max+1. But DESIGN IS A TEAM, not one person —
-- more than one designer can be on the same build. Two "new version"
-- submissions milliseconds apart both read the same max and both insert the
-- SAME version_no, then each overwrites current_version_id: a lost update.
-- Nothing stopped it because version_no had no uniqueness.
--
-- This makes version numbering safe:
--   * a UNIQUE index on (artifact_id, version_no) so a duplicate can never land
--   * fn_add_design_version() computes the next number under a row lock on the
--     artifact, inserts the version and repoints current_version_id — all in
--     one transaction, so concurrent callers serialise instead of racing.
--
-- Idempotent: safe to re-run.


-- 1. Uniqueness — a version number is unique within its artifact.
create unique index if not exists ux_design_versions_artifact_no
  on design_versions (artifact_id, version_no);


-- 2. Atomic "add a new version" (after a change request, or a redraft).
create or replace function public.fn_add_design_version(
  p_artifact    uuid,
  p_model_url   text default null,
  p_image_url   text default null,
  p_change_note text default null,
  p_submit      boolean default false)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_next int;
  v_id   uuid;
begin
  if not public.has_role(array['admin','design']) then
    raise exception 'Only design or an admin can add a design version.' using errcode = '42501';
  end if;

  -- Lock the artifact row so concurrent version inserts for the SAME artifact
  -- serialise: a second caller waits here, then reads the number the first one
  -- just committed instead of colliding on it.
  perform 1 from design_artifacts where id = p_artifact for update;
  if not found then
    raise exception 'Design not found.';
  end if;

  select coalesce(max(version_no), 0) + 1 into v_next
    from design_versions where artifact_id = p_artifact;

  insert into design_versions (artifact_id, version_no, model_url, file_url, change_note)
    values (p_artifact, v_next, nullif(p_model_url, ''), nullif(p_image_url, ''), nullif(p_change_note, ''))
    returning id into v_id;

  update design_artifacts
     set current_version_id = v_id,
         status = (case when p_submit then 'pending_approval' else 'draft' end)::design_status,
         client_feedback = null
   where id = p_artifact;

  return v_id;
end $$;
