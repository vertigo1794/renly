# renly — Listing Module Design

Status: approved (2026-08-17). Third milestone, built on the auth+verification module merged in `docs/superpowers/specs/2026-08-16-renly-auth-verification-design.md`. Design/features still expected to evolve — this is the working spec, not a frozen contract.

## Goal

A verified negotiator can post a property listing (with photos), browse the marketplace of other negotiators' active listings, manage their own inventory (mark sold/withdrawn), and view a single listing's detail — matching the Stitch mockups (`post_listing`, `marketplace`, `my_inventory`, `property_detail`).

## Scope split from the original brainstorm

The user asked for full symmetric treatment of `requirement` (browse + manage, same as `listing`) and full multi-photo upload (up to 10, matching the mockup) — both larger than the original brainstorm assumed. Rather than build one oversized plan, this milestone covers **listing only**. `requirement` (its own DB table, a "Requirement Board" browse screen, and a "My Requirements" manage screen, neither of which has a Stitch mockup to work from) is the next milestone, reusing this milestone's patterns. `PostListingScreen` in this milestone is single-purpose (listing only) — the mockup's "Sediakan Listing / Cari Listing" tab toggle is deferred to the requirement milestone, which adds the second tab rather than this milestone building a toggle with only one working branch.

## Gaps the mockups don't cover

The `post_listing` mockup collects `property-type`, `price` (labeled "Price (IDR)", Indonesian Rupiah — a generic Stitch template default, not a real requirement) and `location` (free text) — plus a photo grid. It's missing several fields the ERD and the proposal's matching algorithm (`docs/superpowers/specs/2026-08-16-renly-mvp-design.md`) require:

- **`transaction_type`** (sale/rent) — in the original ERD, and a *mandatory filter* in the matching algorithm, but the mockup only implies it visually (marketplace shows `$12,000 /mo` for a rental vs `$4,250,000` for a sale, no explicit input control). Add an explicit dropdown.
- **`state`** — in the original ERD, also a mandatory matching filter. The mockup's single "Location" field ("City, Neighborhood, or Zip") conflates it with area. Split into `state` (dropdown of Malaysian states, same pattern as `territory` in registration) + `area` (free text, matches the mockup's field and the ERD's `area` column, scored up to 30 points by the matching algorithm).
- **`title`**, **`description`** — shown in `property_detail` ("The Vertex Residency", "Property Overview" paragraph) but never collected anywhere in `post_listing`. Add both as required fields on the create form.
- **`bathrooms`** — shown in `marketplace`/`property_detail` (bathtub icon + count) but not in the ERD and not used by the matching algorithm (which only scores `bedrooms`). Include as an optional display field; never wire it into matching logic.
- **Currency** — mockups show `$` (marketplace, USD-styled) and `Rp` (post_listing, Indonesian Rupiah). Both are Stitch template defaults for a generic property app, not deliberate choices for this Malaysian-negotiator product. Use **RM** (Malaysian Ringgit) everywhere, formatted `RM 1,250,000`.
- **Listing status** — ERD's `listing.status` plus the mockup's Active/Sold toggle (`my_inventory`) cover two states; the proposal's own text says listings must be withdrawable once sold, so add a third: `active | sold | withdrawn`.

## Data model

```sql
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
```

`photo_urls` stores Storage object paths (not public URLs — the bucket is private, paths are resolved to signed/authenticated URLs client-side same as the `ren-tags` bucket pattern from Milestone 2). Capped at 10 entries, enforced client-side (matches the mockup's own "Max 10" label) — not a DB constraint, since a server-side array-length CHECK adds complexity for a limit that's a UX nicety, not a security boundary.

## RLS

Unlike `negotiator.verification_status` (Milestone 2's real bug), `listing` has **no privileged field a client could self-elevate into** — `status` transitions (`active → sold → withdrawn`) are all legitimate actions the listing's own owner should be able to make freely. So row-scoped RLS is sufficient here; no column-level GRANT/REVOKE hardening is needed (documenting this explicitly since Milestone 2's review found the opposite was true for `negotiator`, and getting this distinction right up front avoids a repeat of that two-round fix).

```sql
alter table listing enable row level security;

-- Owner sees all of their own listings regardless of status; everyone else
-- (browsing the marketplace) sees only active ones — sold/withdrawn listings
-- are the owner's business, not visible in other negotiators' marketplace feed.
create policy listing_select on listing for select
  using (negotiator_id = auth.uid() or status = 'active');

create policy listing_insert_own on listing for insert
  with check (negotiator_id = auth.uid());

create policy listing_update_own on listing for update
  using (negotiator_id = auth.uid());
```

No delete policy — withdrawal is a status change (`status = 'withdrawn'`), not a row deletion, so `DELETE` stays denied by RLS's default (consistent with `verification_record`'s immutable-audit-trail treatment, though for a different reason here: there's no audit-trail requirement for listings, deletion is just not a feature this milestone needs).

## Storage

```sql
insert into storage.buckets (id, name, public) values ('listing-photos', 'listing-photos', false)
  on conflict (id) do nothing;

-- Path convention: {negotiator_id}/{listing_id}/{n}.jpg
-- Unlike ren-tags (Milestone 2, owner-only read — it's an evidentiary
-- document), listing photos must be readable by every authenticated
-- negotiator browsing the marketplace, not just the listing's owner.
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
set file_size_limit = 5242880, -- 5MB per photo
    allowed_mime_types = array['image/jpeg', 'image/png']
where id = 'listing-photos';
```

`delete` policy is included here (unlike Milestone 2's `ren-tags` bucket, which only needed `update` for the upsert-retry case) because removing an individual photo from the gallery is a real, expected user action for a 10-photo gallery, not just a retry path.

## Screens

All under `lib/features/listing/`.

1. **`MarketplaceScreen`** — ports `marketplace/code.html`. Search bar (client-side filter on `title`/`area`/`state` for this pass — no server-side full-text search yet, YAGNI until the corpus is large enough to matter), list of `active` listings across all negotiators (RLS already scopes this — the query is just "select all listings", the visible rows are whatever RLS permits). Card: cover photo (first `photo_urls` entry, placeholder icon if empty), price (`RM 1,250,000`, or `RM 1,250,000 /mo` when `transaction_type = 'rent'`), bed/bath icons, `area`. Tap → `PropertyDetailScreen`.
2. **`MyInventoryScreen`** — ports `my_inventory/code.html`. Toggle tabs Active / Sold (a third, Withdrawn, added as a tab too, even though not in the mockup — the ERD status model has three states and hiding withdrawn listings from their own owner would be a real gap, not a deliberate simplification). Lists the caller's own listings regardless of status (RLS `negotiator_id = auth.uid()` branch), filtered client-side by the selected tab. "Post New Listing" button → `PostListingScreen`.
3. **`PostListingScreen`** — ports `post_listing/code.html`'s "Sediakan Listing" branch only (see Scope split above). Fields: `title`, `description`, `property_type` (dropdown), `transaction_type` (dropdown, new), `state` (dropdown, new), `area`, `price` (RM), `bedrooms`, `bathrooms`, photo grid (up to 10, `image_picker` multi-select where the platform supports it, else repeated single-picks appended to a local list — either way the UI is one grid with an "Add Photo" tile and per-photo remove buttons, matching the mockup). Submit uploads each photo to Storage, inserts the `listing` row with the resulting `photo_urls`.
4. **`PropertyDetailScreen`** — ports `property_detail/code.html`. Photo carousel (swipeable `PageView` over `photo_urls`, placeholder state if empty), title, price, bed/bath, `description`, `state`/`area`, and the listing's negotiator (name + REN number, joined from `negotiator`). If the viewer is the listing's owner (`negotiator_id == current user id`), show status-change actions (mark sold / withdraw / reactivate); otherwise show nothing extra — no "contact"/"collaborate" CTA yet, that's the Collaboration milestone (needs `match`/`cobroke_request` tables that don't exist yet).

## File structure

```
lib/
  features/
    listing/
      marketplace_screen.dart
      my_inventory_screen.dart
      post_listing_screen.dart
      property_detail_screen.dart
      listing_repository.dart          # Supabase I/O — the only file that talks to Supabase for this module
      listing_providers.dart           # Riverpod: listingRepositoryProvider, marketplaceListingsProvider, myListingsProvider
      models/
        listing.dart                   # Listing model, fromJson
```

Same repository-owns-all-Supabase-calls pattern as `AuthRepository` (Milestone 2) — screens never call `Supabase.instance.client` directly.

## Router

New routes: `/marketplace` → `MarketplaceScreen`, `/my-inventory` → `MyInventoryScreen`, `/post-listing` → `PostListingScreen`, `/property/:listingId` → `PropertyDetailScreen` (path param, not `extra` — a listing detail page is a real shareable/bookmarkable location, unlike the `negotiatorId` handoff between registration steps which is transient session state). All four require a session (added to the router's private-route set — i.e., NOT added to `_publicRoutes` in `computeAuthRedirect`, so an unauthenticated deep link bounces to `/` same as `/home` does today). `HomePlaceholderScreen` (Milestone 2's one-line "dashboard coming soon" stand-in) gets a real button/nav-bar linking to `/marketplace` and `/my-inventory` — this is the first milestone that gives the placeholder home screen actual navigation destinations, though it stays a placeholder otherwise (the `main_dashboard` mockup itself is still out of scope, real dashboard is a later milestone).

## Manual setup

Same pattern as Milestones 1–2: this session has no DB credentials, so the SQL above (combined into one migration file the plan will generate, `supabase/migrations/0003_listing.sql`) is a manual paste into the Supabase SQL Editor. No Auth-dashboard toggle is needed this time (unlike Milestone 2's email-confirmation setting) — this module doesn't touch Auth configuration.

## Testing approach

Same boundary as Milestones 1–2: `ListingRepository` (Supabase-calling code) isn't unit-tested directly. `Listing.fromJson` (pure parsing) and any pure helper logic (e.g. currency formatting, the active/sold/withdrawn tab-filter predicate) get real unit tests. Screens get widget tests following the established pattern (`testWidgets`, `rootBundle.clear()` in `setUp` for multi-test files, `GoogleFonts.config.allowRuntimeFetching = false`, pre-interaction `pumpAndSettle`) — verifying rendering and required-field validation, not a live Supabase round trip.

## Explicitly deferred / out of scope for this milestone

- `requirement` table and its screens (Requirement Board, My Requirements) — next milestone.
- The `post_listing` mockup's "Cari Listing" tab toggle — added when the requirement milestone lands.
- Server-side/full-text search on the marketplace (client-side filter only, for now).
- "Contact"/"collaborate" CTA on `PropertyDetailScreen` — needs `match`/`cobroke_request`, not built yet.
- Real `main_dashboard` screen — `HomePlaceholderScreen` just gains two navigation links this pass.
- DB-enforced photo count cap (client-side "max 10" only).
