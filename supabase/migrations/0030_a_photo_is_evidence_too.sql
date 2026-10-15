-- 0030_a_photo_is_evidence_too.sql
--
-- 0029 made a checklist tick evidence: recorded, optionally photo-backed, and
-- frozen once the PM approves. It left the photos themselves wide open.
--
-- `attachments` has carried one policy since 0002:
--
--     create policy p_att_staff on attachments for all using (public.is_staff())
--
-- so **any** staff member — a welder on another build, store, procurement —
-- could delete any photo on any stage of any truck. Nothing recorded it, and
-- nothing stopped it after the PM had approved the stage and signed off on
-- those very photos as the evidence. A check whose proof can be deleted by a
-- passer-by is not proof, which makes 0029's rule only half a rule.
--
-- The stage screen is also about to offer "delete" on a photo for the first
-- time (until now a photo could be added and never removed, which is its own
-- problem: a fitter who uploads the wrong shot had no way back). Offering it
-- without a rule behind it would be the same mistake as the bare `done`
-- column.
--
-- So: deleting a stage photo is for the person who took it, the build's PM, or
-- an admin — and once the stage is approved, only an admin, exactly as the
-- checklist freezes. Adding one is unchanged. Tickets and designs keep their
-- own policies and are untouched.
--
-- Idempotent: one function, one trigger.


create or replace function public.trg_guard_attachments() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pm uuid; v_sstatus stage_status; v_uploader uuid;
begin
  -- No JWT = service role / SQL editor / seed, as everywhere else.
  if auth.uid() is null then return old; end if;
  if public.is_admin() then return old; end if;

  -- Only stage photos are governed here. A ticket photo belongs to the client
  -- who raised it and a design file to its version; both have their own rules.
  if old.owner_type <> 'stage' then return old; end if;

  select p.pm_id, s.status into v_pm, v_sstatus
    from stages s join projects p on p.id = s.project_id
   where s.id = old.owner_id;

  -- An attachment pointing at a stage that no longer exists is orphaned; let
  -- it go rather than stranding it forever.
  if v_pm is null and v_sstatus is null then return old; end if;

  if v_sstatus = 'done' then
    raise exception 'This stage is already approved as complete — its photos are part of that approval.'
      using errcode = '42501';
  end if;

  v_uploader := old.uploaded_by;
  if not (v_uploader = auth.uid() or v_pm = auth.uid()) then
    raise exception 'Only whoever took this photo, or the build''s project manager, can remove it.'
      using errcode = '42501';
  end if;

  return old;
end $$;

drop trigger if exists t_guard_attachments on public.attachments;
create trigger t_guard_attachments before delete on public.attachments
  for each row execute function public.trg_guard_attachments();
