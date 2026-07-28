-- 0008_design_storage.sql
-- Self-serve design uploads: a public 'designs' bucket where designers upload
-- their .glb models + 2D preview images straight from the app. Public read so
-- <model-viewer> can fetch the .glb; only staff can upload/replace.

insert into storage.buckets (id, name, public)
values ('designs', 'designs', true)
on conflict (id) do nothing;

-- Anyone can read (needed for the public 3D preview URL).
drop policy if exists "designs public read" on storage.objects;
create policy "designs public read" on storage.objects
  for select using (bucket_id = 'designs');

-- Only signed-in staff can upload / replace / remove design files.
drop policy if exists "designs staff insert" on storage.objects;
create policy "designs staff insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'designs' and public.is_staff());

drop policy if exists "designs staff update" on storage.objects;
create policy "designs staff update" on storage.objects
  for update to authenticated
  using (bucket_id = 'designs' and public.is_staff())
  with check (bucket_id = 'designs' and public.is_staff());

drop policy if exists "designs staff delete" on storage.objects;
create policy "designs staff delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'designs' and public.is_staff());
