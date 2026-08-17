-- supabase/migrations/0003_listing.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001 and 0002.

create table listing (
  listing_id uuid primary key default gen_random_uuid(),
  negotiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  title text not null,
  description text not null,
  property_type text not null check (property_type in ('apartment', 'house', 'commercial', 'land')),
  transaction_type text not null check (transaction_type in ('sale', 'rent')),
  state text not null,
  area text not null,
  price numeric not null check (price > 0),
  bedrooms integer,
  bathrooms integer,
  photo_urls text[] not null default '{}',
  status text not null default 'active' check (status in ('active', 'sold', 'withdrawn')),
  created_at timestamptz not null default now()
);

alter table listing enable row level security;

-- Owner sees all of their own listings regardless of status; everyone else
-- (browsing the marketplace) sees only active ones.
create policy listing_select on listing for select
  using (negotiator_id = auth.uid() or status = 'active');

create policy listing_insert_own on listing for insert
  with check (negotiator_id = auth.uid());

create policy listing_update_own on listing for update
  using (negotiator_id = auth.uid());

-- Storage: path convention {negotiator_id}/{listing_id}/{n}.jpg
insert into storage.buckets (id, name, public) values ('listing-photos', 'listing-photos', false)
  on conflict (id) do nothing;

create policy listing_photos_select_authenticated on storage.objects for select
  to authenticated using (bucket_id = 'listing-photos');

create policy listing_photos_insert_own on storage.objects for insert
  to authenticated with check (bucket_id = 'listing-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy listing_photos_update_own on storage.objects for update
  to authenticated using (bucket_id = 'listing-photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'listing-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy listing_photos_delete_own on storage.objects for delete
  to authenticated using (bucket_id = 'listing-photos' and (storage.foldername(name))[1] = auth.uid()::text);

update storage.buckets
set file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png']
where id = 'listing-photos';
