-- 0014_client_ticket_visibility.sql — a client sees every ticket about their truck
--
-- The client could only see tickets where raised_by = themselves
-- (p_tickets_client, 0002). But Service raises tickets on a client's behalf
-- after a phone call or a site visit (fn_create_ticket stamps raised_by with the
-- service member), and those were invisible to the client — they could neither
-- follow the status nor reopen one. A client should see anything raised against
-- a truck that belongs to their account, whoever logged it.
--
-- Additive: RLS SELECT policies are OR'd, so this widens visibility without
-- touching the existing "own tickets" policy. Write access is unchanged — a
-- client still only inserts tickets as themselves (p_tickets_client_new).

drop policy if exists p_tickets_client_project on tickets;
create policy p_tickets_client_project on tickets for select using (
  exists (
    select 1 from projects p
     where p.id = tickets.project_id
       and p.client_account_id = public.my_client_account()
  )
);
