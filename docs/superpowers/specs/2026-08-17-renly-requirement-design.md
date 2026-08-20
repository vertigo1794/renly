# renly — Requirement Module Design

Status: approved (2026-08-17). Fourth milestone, built on the Listing module merged in `docs/superpowers/specs/2026-08-17-renly-listing-design.md`. Design/features still expected to evolve — this is the working spec, not a frozen contract.

## Goal

A verified negotiator can post an anonymised client requirement (structured criteria, no client identity), browse the requirement board of other negotiators' open requirements, and manage their own requirements (open/fulfilled/withdrawn) — completing the split this milestone inherited from the Listing design doc's "Scope split" section.

## Why this is smaller than Listing

No photos. No Storage bucket, no signed-URL widget, no multi-file upload flow, no `dart:io`-vs-web concern. The repository/provider/screen shape, RLS hardening approach (row-scope + column-grant, no privileged self-elevation field here either), testing boundary, and translation-key discipline are all already-decided precedent from Listing — this doc only covers what's actually new.

## Gaps the mockup doesn't cover, and deliberate field omissions

The `post_listing` mockup's "Cari Listing" tab (`stitch_renly_property_agent_network/post_listing/code.html`) toggles only the photos section — the same `property-type`/`price`/`location` fields stay visible for both tabs. It gives no distinct field list for a requirement. Building from the proposal's ERD and matching-algorithm spec (`docs/superpowers/specs/2026-08-16-renly-mvp-design.md`) instead:

- **`budget_min`/`budget_max`** (a range) instead of Listing's single `price` — a requirement expresses what a client is willing to pay, not a fixed figure.
- **`bedrooms`** (optional int) — the matching algorithm scores this for requirements too (up to 10 points), so it's a real field, not a display nicety like Listing's `bathrooms` was.
- **No `bathrooms`** — the matching algorithm's four scored attributes are location, price, property_type, bedrooms; bathrooms was never part of it for requirements. Skipping it is a YAGNI call, not an oversight.
- **No `title`/`description`** — this is the deliberate omission, unlike Listing which added both. The proposal's anonymisation principle is explicit: "No personally identifying information about the client is ever stored or displayed... structured criteria only." A free-text field is exactly the kind of surface a negotiator could accidentally type a client's name or phone number into. Keeping the requirement form 100% structured (dropdowns/numbers only) makes that a non-issue rather than a policy to remember.

## Data model

```sql
create table requirement (
  requirement_id uuid primary key default gen_random_uuid(),
  negotiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  property_type text not null check (property_type in ('apartment', 'house', 'commercial', 'land')),
  transaction_type text not null check (transaction_type in ('sale', 'rent')),
  state text not null,
  area text not null,
  budget_min numeric not null check (budget_min > 0),
  budget_max numeric not null check (budget_max >= budget_min),
  bedrooms integer,
  status text not null default 'open' check (status in ('open', 'fulfilled', 'withdrawn')),
  created_at timestamptz not null default now()
);
```

## RLS

Same shape as Listing's `listing_select`/`listing_insert_own`/`listing_update_own` — row-scoped to authenticated, owner sees everything of their own, everyone else sees only `status = 'open'`. Column-scoped INSERT/UPDATE grants exclude `requirement_id`/`negotiator_id`/`created_at` from UPDATE (same rationale as Listing: RLS restricts which row, only GRANT/REVOKE restricts which columns) and exclude `status` from INSERT (stays at its `'open'` default).

```sql
alter table requirement enable row level security;

create policy requirement_select on requirement for select
  to authenticated using (negotiator_id = auth.uid() or status = 'open');

create policy requirement_insert_own on requirement for insert
  to authenticated with check (negotiator_id = auth.uid());

create policy requirement_update_own on requirement for update
  to authenticated using (negotiator_id = auth.uid());

revoke insert on requirement from authenticated;
grant insert (
  negotiator_id, property_type, transaction_type, state, area,
  budget_min, budget_max, bedrooms
) on requirement to authenticated;

revoke update on requirement from authenticated;
grant update (
  property_type, transaction_type, state, area, budget_min, budget_max,
  bedrooms, status
) on requirement to authenticated;
```

No Storage policies needed — requirement has no photos.

**Reusing `get_listing_owner_info`:** the Requirement Board needs to show which negotiator posted a requirement (so another negotiator with a matching listing knows who to contact) — same need Listing's `PropertyDetailScreen` had. Rather than duplicate the `security definer` RPC, `RequirementRepository` calls the existing `get_listing_owner_info(p_negotiator_id uuid)` function (from `0004_listing_hardening.sql`) as-is — it's already generic (takes any negotiator id, returns `full_name`/`ren_number`, nothing listing-specific about its logic). The name is a minor accepted naming debt; a rename is a cheap follow-up, not worth a migration just for clarity right now.

## Screens

All under `lib/features/requirement/`.

1. **`RequirementBoardScreen`** — browse all `open` requirements across negotiators, same shape as `MarketplaceScreen` (client-side search, list of cards). Card shows property type, transaction type, state/area, budget range, bedrooms if set, and the posting negotiator's name + REN (via the shared RPC).
2. **`MyRequirementsScreen`** — the caller's own requirements, tabbed by status (open/fulfilled/withdrawn), same shape as `MyInventoryScreen`.
3. **`PostRequirementScreen`** — create form: property type, transaction type, state, area, budget min, budget max, bedrooms (optional). **A separate screen from `PostListingScreen`**, not a retrofit of the mockup's tab toggle into the existing, already-tested `PostListingScreen` — avoids touching shipped/reviewed Listing code for a UI convenience (co-locating two forms behind a tab) that isn't worth the regression risk. Faithful to the proposal's functionality (both creation flows exist), not to the mockup's exact single-screen-with-toggle layout.

`HomePlaceholderScreen` gains two more navigation links (Requirement Board, My Requirements), alongside Milestone 3's Marketplace/My Inventory links.

## File structure

```
lib/
  features/
    requirement/
      requirement_board_screen.dart
      my_requirements_screen.dart
      post_requirement_screen.dart
      requirement_repository.dart      # Supabase I/O — sole Supabase touchpoint for this module
      requirement_providers.dart       # Riverpod: requirementRepositoryProvider, boardRequirementsProvider, myRequirementsProvider, requirementOwnerProvider
      models/
        requirement.dart               # Requirement model, fromJson
```

`RequirementRepository`'s `fetchRequirementOwner` calls the shared `get_listing_owner_info` RPC directly (no new `ListingOwner`-equivalent model needed — reuse `lib/features/listing/models/listing_owner.dart`'s `ListingOwner` type, since the RPC returns the identical shape; this is a legitimate cross-feature import, the same way `listing_providers.dart` already imports `authStateProvider` from the auth feature).

## Router

New routes, all requiring a session (not added to `_publicRoutes`): `/requirement-board` → `RequirementBoardScreen`, `/my-requirements` → `MyRequirementsScreen`, `/post-requirement` → `PostRequirementScreen`.

## Manual setup

Same pattern as before: `supabase/migrations/0005_requirement.sql` is a manual paste into the Supabase SQL Editor, no Auth-dashboard changes.

## Testing approach

Same boundary as Listing: `RequirementRepository` untested directly (Supabase-calling code). `Requirement.fromJson` and any pure helpers (a budget-range formatter, a status-filter predicate mirroring `ListingStatusFilter`) get real unit tests. Screens get widget tests following the established pattern (`rootBundle.clear()` for multi-testWidgets files, pre-interaction `pumpAndSettle`, no unverified finder-to-Key swaps).

## Explicitly deferred / out of scope for this milestone

- Retrofitting `PostListingScreen`'s tab toggle to match the mockup exactly (accepted as a cosmetic gap, not a functional one).
- Matching Engine (needs both `listing` and `requirement` populated — this milestone finishes that precondition, the engine itself is next).
- `RequirementBoardScreen`'s "contact this negotiator" CTA — needs `match`/`cobroke_request`, still not built.
- Renaming `get_listing_owner_info` to something feature-neutral — cheap follow-up, not blocking.
