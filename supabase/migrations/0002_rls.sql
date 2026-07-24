-- Azimuth BuildTrack — Row Level Security (role permission matrix, enforced in DB)

-- ===== helpers =====
create or replace function public.my_role() returns user_role
  language sql stable security definer set search_path = public as
$$ select role from profiles where id = auth.uid() $$;

create or replace function public.is_admin() returns boolean
  language sql stable as $$ select public.my_role() = 'admin' $$;

create or replace function public.is_staff() returns boolean
  language sql stable as $$ select coalesce(public.my_role() <> 'client', false) $$;

create or replace function public.my_client_account() returns uuid
  language sql stable security definer set search_path = public as
$$ select id from client_accounts where contact_user_id = auth.uid() limit 1 $$;

-- enable RLS on everything
do $$ declare t text;
begin
  for t in select tablename from pg_tables where schemaname='public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ===== profiles =====
create policy p_profiles_read on profiles for select using (auth.uid() is not null);
create policy p_profiles_admin on profiles for all using (public.is_admin()) with check (public.is_admin());

-- ===== staff-only operational tables (clients blocked) =====
-- vendors, item_catalog, stock_items, purchase_orders, po_lines, goods_receipts,
-- procurement_requirements, workflow_templates, template_stages, bays, delay_logs,
-- stage_approvals, service_visits, audit_log, component_instances
do $$ declare t text;
begin
  foreach t in array array[
    'vendors','item_catalog','stock_items','purchase_orders','po_lines','goods_receipts',
    'procurement_requirements','workflow_templates','template_stages','bays','delay_logs',
    'stage_approvals','service_visits','audit_log','component_instances'
  ] loop
    execute format('create policy %I on public.%I for all using (public.is_staff()) with check (public.is_staff())', t||'_staff', t);
  end loop;
end $$;

-- ===== projects =====  staff read all; client reads own; admin/pm write
create policy p_projects_staff  on projects for select using (public.is_staff());
create policy p_projects_client on projects for select using (client_account_id = public.my_client_account());
create policy p_projects_write  on projects for all
  using (public.is_admin() or pm_id = auth.uid())
  with check (public.is_admin() or pm_id = auth.uid());

-- ===== stages / checklist =====  staff all; client read own project
create policy p_stages_staff  on stages for all using (public.is_staff()) with check (public.is_staff());
create policy p_stages_client on stages for select using (
  exists (select 1 from projects p where p.id = stages.project_id and p.client_account_id = public.my_client_account()));
create policy p_check_staff on checklist_items for all using (public.is_staff()) with check (public.is_staff());

-- ===== designs =====  staff all; client read own project + act on approvals
create policy p_design_staff  on design_artifacts for all using (public.is_staff()) with check (public.is_staff());
create policy p_design_client on design_artifacts for select using (
  exists (select 1 from projects p where p.id = design_artifacts.project_id and p.client_account_id = public.my_client_account()));
create policy p_dver_staff  on design_versions for all using (public.is_staff()) with check (public.is_staff());
create policy p_dver_client on design_versions for select using (
  exists (select 1 from design_artifacts a join projects p on p.id=a.project_id
          where a.id = design_versions.artifact_id and p.client_account_id = public.my_client_account()));
create policy p_dappr_staff  on design_approvals for all using (public.is_staff()) with check (public.is_staff());
create policy p_dappr_client on design_approvals for all
  using (client_user_id = auth.uid()) with check (client_user_id = auth.uid());

-- ===== tickets =====  service staff all; client own
create policy p_tickets_staff  on tickets for all using (public.is_staff()) with check (public.is_staff());
create policy p_tickets_client on tickets for select using (raised_by = auth.uid());
create policy p_tickets_client_new on tickets for insert with check (raised_by = auth.uid());

-- ===== documents =====  staff all; client read own available docs
create policy p_docs_staff  on documents for all using (public.is_staff()) with check (public.is_staff());
create policy p_docs_client on documents for select using (
  available and exists (select 1 from projects p where p.id = documents.project_id and p.client_account_id = public.my_client_account()));

-- ===== attachments =====  staff all; client read attachments on own tickets
create policy p_att_staff on attachments for all using (public.is_staff()) with check (public.is_staff());

-- ===== notifications =====  each user their own
create policy p_notif_own on notifications for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ===== client_accounts =====  staff all; client reads own
create policy p_ca_staff  on client_accounts for all using (public.is_staff()) with check (public.is_staff());
create policy p_ca_client on client_accounts for select using (contact_user_id = auth.uid());
