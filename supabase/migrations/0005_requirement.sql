-- supabase/migrations/0005_requirement.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0004.
--
-- Written to be re-runnable from the start (drop policy if exists / on
-- conflict do nothing / guarded constraint adds) -- 0003_listing.sql
-- shipped without `to authenticated` and column-scoped grants, and needed
-- a follow-up 0004_listing_hardening.sql to fix both. Those lessons are
-- folded in here directly instead of being deferred to a 0006.

create table if not exists requirement (
  requirement_id uuid primary key default gen_random_uuid(),
  negotiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  property_type text not null check (property_type in ('apartment', 'house', 'commercial', 'land')),
  transaction_type text not null check (transaction_type in ('sale', 'rent')),
  state text not null,
  area text not null,
  budget_min numeric not null check (budget_min > 0),
  budget_max numeric not null check (budget_max >= budget_min),
  bedrooms integer,
  photo_urls text[] not null default '{}',
  status text not null default 'open' check (status in ('open', 'fulfilled', 'withdrawn')),
  created_at timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'requirement_bedrooms_nonnegative') then
    alter table requirement add constraint requirement_bedrooms_nonnegative check (bedrooms is null or bedrooms >= 0);
  end if;
end $$;

alter table requirement enable row level security;

-- Owner sees all of their own requirements regardless of status; everyone
-- else (browsing the board) sees only open ones.
drop policy if exists requirement_select on requirement;
create policy requirement_select on requirement for select
  to authenticated using (negotiator_id = auth.uid() or status = 'open');

drop policy if exists requirement_insert_own on requirement;
create policy requirement_insert_own on requirement for insert
  to authenticated with check (negotiator_id = auth.uid());

drop policy if exists requirement_update_own on requirement;
create policy requirement_update_own on requirement for update
  to authenticated using (negotiator_id = auth.uid());

-- Column-scoped INSERT: requirement_id, photo_urls, status and created_at
-- stay at their table defaults on insert (photos are attached by a
-- follow-up UPDATE once they have been uploaded under the new
-- requirement_id).
revoke insert on requirement from authenticated;
grant insert (
  negotiator_id, property_type, transaction_type, state, area,
  budget_min, budget_max, bedrooms
) on requirement to authenticated;

-- Column-scoped UPDATE: requirement_id, negotiator_id and created_at are
-- deliberately excluded -- RLS restricts which ROW may be updated, only
-- GRANT/REVOKE can restrict which COLUMNS. photo_urls IS included here
-- (not in the insert grant) because photos are attached via UPDATE after
-- the row already exists.
revoke update on requirement from authenticated;
grant update (
  property_type, transaction_type, state, area, budget_min, budget_max,
  bedrooms, status, photo_urls
) on requirement to authenticated;

-- Storage: path convention {negotiator_id}/{requirement_id}/{n}.jpg
insert into storage.buckets (id, name, public) values ('requirement-photos', 'requirement-photos', false)
  on conflict (id) do nothing;

drop policy if exists requirement_photos_select_authenticated on storage.objects;
create policy requirement_photos_select_authenticated on storage.objects for select
  to authenticated using (bucket_id = 'requirement-photos');

drop policy if exists requirement_photos_insert_own on storage.objects;
create policy requirement_photos_insert_own on storage.objects for insert
  to authenticated with check (bucket_id = 'requirement-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists requirement_photos_update_own on storage.objects;
create policy requirement_photos_update_own on storage.objects for update
  to authenticated using (bucket_id = 'requirement-photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'requirement-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists requirement_photos_delete_own on storage.objects;
create policy requirement_photos_delete_own on storage.objects for delete
  to authenticated using (bucket_id = 'requirement-photos' and (storage.foldername(name))[1] = auth.uid()::text);

update storage.buckets
set public = false,
    file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png']
where id = 'requirement-photos';
