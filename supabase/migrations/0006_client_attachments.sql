-- Azimuth BuildTrack — let a client read the build photos of their own trucks.
-- attachments had only a staff policy; clients need read access to stage photos
-- on projects that belong to their client_account.

do $$ begin
  if not exists (select 1 from pg_policies where tablename='attachments' and policyname='p_att_client') then
    create policy p_att_client on attachments for select using (
      owner_type = 'stage' and exists (
        select 1 from stages s
        join projects p on p.id = s.project_id
        where s.id = attachments.owner_id
          and p.client_account_id = public.my_client_account()
      )
    );
  end if;
end $$;
