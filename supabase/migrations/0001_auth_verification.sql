-- supabase/migrations/0001_auth_verification.sql
-- Run this once in the Supabase project's SQL Editor (Dashboard -> SQL Editor -> New query -> paste -> Run).

-- agency
create table agency (
  agency_id uuid primary key default gen_random_uuid(),
  firm_name text not null,
  registration_no text,
  address text,
  created_at timestamptz not null default now()
);
create unique index agency_firm_name_lower_idx on agency (lower(trim(firm_name)));

-- negotiator (negotiator_id IS the Supabase Auth user id -- 1:1 with auth.users)
create table negotiator (
  negotiator_id uuid primary key references auth.users(id) on delete cascade,
  agency_id uuid references agency(agency_id),
  full_name text not null,
  ic_number text not null,
  phone_number text not null,
  ren_number text,
  territory text,
  verification_status text not null default 'pending'
    check (verification_status in ('pending', 'approved', 'rejected')),
  subscription_tier text not null default 'free'
    check (subscription_tier in ('free', 'professional')),
  created_at timestamptz not null default now()
);

-- verification_record (immutable audit trail -- insert/select only, no update/delete policy)
create table verification_record (
  record_id uuid primary key default gen_random_uuid(),
  negotiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  method text not null default 'manual_registration',
  tag_photo_url text,
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  outcome text not null default 'pending'
    check (outcome in ('pending', 'approved', 'rejected'))
);

-- RLS: every table is deny-by-default the moment RLS is enabled; each gets an explicit policy.
alter table negotiator enable row level security;
create policy negotiator_select_own on negotiator for select using (auth.uid() = negotiator_id);
create policy negotiator_insert_own on negotiator for insert with check (auth.uid() = negotiator_id);
create policy negotiator_update_own on negotiator for update using (auth.uid() = negotiator_id);

alter table verification_record enable row level security;
create policy verification_record_select_own on verification_record for select using (auth.uid() = negotiator_id);
create policy verification_record_insert_own on verification_record for insert with check (auth.uid() = negotiator_id);

alter table agency enable row level security;
create policy agency_select_all on agency for select using (true);
create policy agency_insert_authenticated on agency for insert to authenticated with check (true);

-- Storage: private bucket for REN tag photos, path convention {auth.uid()}/tag.jpg
insert into storage.buckets (id, name, public) values ('ren-tags', 'ren-tags', false)
  on conflict (id) do nothing;

create policy ren_tags_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'ren-tags' and (storage.foldername(name))[1] = auth.uid()::text);
create policy ren_tags_select_own on storage.objects for select to authenticated
  using (bucket_id = 'ren-tags' and (storage.foldername(name))[1] = auth.uid()::text);
