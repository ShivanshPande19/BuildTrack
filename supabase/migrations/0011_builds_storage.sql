-- ============================================================================
-- 0011_builds_storage.sql — real photo uploads
--
-- Two placeholders become real:
--   * Workshop "Add photo" attached a random picsum.photos URL — there was no
--     bucket to put an actual site photo in.
--   * The client's "Add a photo" on a support request was a coming-soon snackbar.
--
-- Adds a public 'builds' bucket (same shape as 'designs' in 0008) and lets a
-- client attach photos to their *own* ticket — nothing more.
-- Safe to re-run (idempotent).
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1. The bucket
--    Public read, like 'designs': the client's app and the stage gallery load
--    these straight from the URL stored on the attachment row.
-- ════════════════════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public)
values ('builds', 'builds', true)
on conflict (id) do nothing;

drop policy if exists "builds public read" on storage.objects;
create policy "builds public read" on storage.objects
  for select using (bucket_id = 'builds');

-- Staff upload build photos (workshop progress shots, part close-ups…).
drop policy if exists "builds staff insert" on storage.objects;
create policy "builds staff insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'builds' and public.is_staff());

drop policy if exists "builds staff update" on storage.objects;
create policy "builds staff update" on storage.objects
  for update to authenticated
  using (bucket_id = 'builds' and public.is_staff())
  with check (bucket_id = 'builds' and public.is_staff());

drop policy if exists "builds staff delete" on storage.objects;
create policy "builds staff delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'builds' and public.is_staff());

-- A client may upload, but only under tickets/ — they have no reason to write
-- anywhere else in the bucket.
drop policy if exists "builds client ticket insert" on storage.objects;
create policy "builds client ticket insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'builds'
    and public.my_role() = 'client'
    and (storage.foldername(name))[1] = 'tickets'
  );


-- ════════════════════════════════════════════════════════════════════════════
-- 2. Ticket attachments
--    attachments already carried owner_type='ticket' in its comment, but only
--    staff could ever read or write a row. A client needs both, for their own
--    ticket only — that's the photo that makes a support request useful.
-- ════════════════════════════════════════════════════════════════════════════

create index if not exists idx_attachments_owner on attachments(owner_type, owner_id);

drop policy if exists p_att_client_ticket on attachments;
create policy p_att_client_ticket on attachments for select using (
  owner_type = 'ticket' and exists (
    select 1 from tickets t
     where t.id = attachments.owner_id
       and t.raised_by = auth.uid()));

drop policy if exists p_att_client_ticket_new on attachments;
create policy p_att_client_ticket_new on attachments for insert with check (
  owner_type = 'ticket'
  and uploaded_by = auth.uid()
  and exists (
    select 1 from tickets t
     where t.id = attachments.owner_id
       and t.raised_by = auth.uid()));
