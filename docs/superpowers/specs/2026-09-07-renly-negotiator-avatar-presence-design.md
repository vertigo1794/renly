# Negotiator Avatar + Online Presence — Design

## Overview

Adds two genuinely new, real features to how negotiators are shown across the app: a profile photo (uploaded by the negotiator themselves) and a functional online/offline indicator (driven by a real `last_seen_at` heartbeat, not a decorative dot). Both are surfaced everywhere the app already shows another negotiator's name/REN number, plus the upload flow for a negotiator's own photo.

This crosses the project's established inline-vs-brainstorm threshold: it needs a new migration, a new Storage bucket, a new upload UI, and a new (small) presence subsystem — not a pure restyle of existing real data.

## Data Model

New migration `supabase/migrations/0028_negotiator_avatar_presence.sql`, adding to `negotiator`:

```sql
-- supabase/migrations/0028_negotiator_avatar_presence.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0027.
--
-- avatar_url: path in the new public `avatar-photos` Storage bucket (NOT a
-- signed URL -- the bucket is public-read, see Storage section below).
-- Nullable -- absent means no photo uploaded yet, UI falls back to an
-- initials avatar (the same fallback conversation_list_screen.dart already
-- renders today), never a fabricated placeholder image.
--
-- last_seen_at: updated by the client itself (on app resume + a periodic
-- heartbeat while active). Nullable -- a negotiator who has never triggered
-- a heartbeat (shouldn't happen post-login, but is possible for rows
-- created before this migration) reads as offline, never "online" by
-- default.
alter table negotiator add column if not exists avatar_url text;
alter table negotiator add column if not exists last_seen_at timestamptz;

-- Additive only -- no prior REVOKE statement, per 0012_settings.sql's own
-- established reasoning: Postgres GRANT is additive and does not reset
-- prior column grants, so there is no need to (and real danger in trying
-- to) restate the full existing UPDATE column list. The existing 10-column
-- grant (full_name, ic_number, phone_number, ren_number, agency_id,
-- territory, property_specialisation, notify_match, notify_message,
-- notify_cobroke_request) is left untouched; these 2 columns are simply
-- added on top of it. No RLS policy change needed -- negotiator_update_own
-- (0001) already gates which ROW can be touched.
grant update (avatar_url, last_seen_at) on negotiator to authenticated;
```

## Storage

New bucket `avatar-photos`, created via the Supabase Dashboard (Storage → New bucket), **public**, unlike `listing-photos`/`requirement-photos` (both private + signed URL). Rationale: avatars are low-sensitivity, meant to be shown broadly (9 call sites below), and a public bucket avoids managing signed-URL expiry/refresh at every one of those sites. Path convention: `{negotiator_id}/avatar.jpg` (upsert on re-upload, mirroring `ListingRepository.uploadListingPhoto`'s own path/upsert convention).

Storage policies (same RLS-on-storage pattern the existing private buckets already use, just with a public-read policy instead of a signed-URL-only one): `select` allowed for everyone (`true`) since the bucket is public; `insert`/`update` restricted to `auth.uid()::text = (storage.foldername(name))[1]` (the negotiator can only write into their own `{negotiator_id}/...` folder) -- written as part of the same migration file.

## Presence Mechanism

- `ProfileRepository` gains `updateLastSeen()` — a plain `update negotiator set last_seen_at = now() where negotiator_id = ...` Supabase-boundary call, same shape as its existing methods.
- A `WidgetsBindingObserver` at the app's top level (wired in `main.dart`/the router wrapper) calls `updateLastSeen()` on `AppLifecycleState.resumed`, and starts a `Timer.periodic(Duration(seconds: 60), ...)` that also calls it while the app stays active, cancelling the timer on pause/dispose. Runs only when a negotiator is logged in.
- Failures are swallowed silently (best-effort, same reasoning as `_loadPreviewCandidates`) — a heartbeat failing must never surface an error or block the app.
- `is_online` is **computed server-side**, inside the RPC (`(now() - last_seen_at) < interval '2 minutes'`), not client-side — avoids clock-skew between devices and keeps every consumer dumb (just reads a bool).

## RPC & Model Changes

`get_negotiator_public_info` (0004 → 0015 rename → 0019 agency_name → 0026 verification_status) is extended once more, the same drop-and-recreate pattern as before (Postgres disallows changing `RETURNS TABLE` shape via `CREATE OR REPLACE`):

```sql
drop function if exists get_negotiator_public_info(uuid);

create function get_negotiator_public_info(p_negotiator_id uuid)
returns table (
  full_name text, ren_number text, agency_name text, verification_status text,
  avatar_url text, is_online boolean
)
language sql
security definer
set search_path = public
as $$
  select n.full_name, n.ren_number, a.firm_name, n.verification_status,
         n.avatar_url, (n.last_seen_at is not null and now() - n.last_seen_at < interval '2 minutes')
  from negotiator n
  left join agency a on a.agency_id = n.agency_id
  where n.negotiator_id = p_negotiator_id;
$$;

revoke execute on function get_negotiator_public_info(uuid) from public;
grant execute on function get_negotiator_public_info(uuid) to authenticated;
```

`ListingOwner` (the single shared model every consumer below already uses) gains `avatarUrl` (`String?`) and `isOnline` (`bool`, defaults `false`).

## Shared Widget

New `NegotiatorAvatar` (`core/widgets/negotiator_avatar.dart`) generalizes the pattern `conversation_list_screen.dart` already hand-rolls today (`CircleAvatar(radius: 22, backgroundColor: 0xFF0B0F19, child: Text(initial))`):

- Takes `fullName`, `avatarUrl`, `isOnline`, and a `size` param (mirroring `RStarBadge`'s own `size` convention).
- Renders `NetworkImage(avatarUrl)` when `avatarUrl` is non-null, else the existing black-circle/lime-initial fallback.
- Overlays a small green dot (bottom-right, white/border ring for contrast) only when `isOnline == true` — no dot at all when offline, avoiding a "gray = offline vs gray = unknown" ambiguity.

## Rollout

`NegotiatorAvatar` replaces or is added to the existing name/REN display at 9 call sites, all of which already consume `ListingOwner` (directly or via `MatchCandidate.listingOwner`/`requirementOwner`, `CobrokeRequestCandidate`):

1. `property_detail_screen.dart` — `_AgentCard` (the original ask; larger size, e.g. 56)
2. `my_matches_screen.dart` — both the `requirementOwner` and `listingOwner` rows
3. `matches_for_requirement_screen.dart` — the `listingOwner` row
4. `matches_for_listing_screen.dart` — the `requirementOwner` row
5. `conversation_list_screen.dart` — the counterparty row (extends its own existing initials-circle in place)
6. `my_requests_screen.dart` — the `counterpartyOwner` row
7. `requirement_board_screen.dart` — the owner row
8. `requirement_detail_screen.dart` — the owner row
9. `marketplace_screen.dart` — the listing-owner row inside each listing card

All list-style call sites (2–9) use the existing `conversation_list_screen.dart` sizing (radius 22 / size 44); the Property Detail Agent Card (1) uses a larger size (56) matching its own hero-card prominence.

**Explicitly excluded**, per direct instruction: `main_dashboard_screen.dart`. Also excluded (out of scope, not "another negotiator"): every place a screen shows the **viewer's own** profile (Marketplace/Messages/Post Broadcast header badges, Account Settings) — those stay as they are.

## Upload UI

`profile_screen.dart`'s `_EditForm` gains a tappable avatar (current photo or initials fallback) that opens `image_picker` (already a dependency), uploads to `avatar-photos/{negotiator_id}/avatar.jpg` via a new `ProfileRepository.uploadAvatar()` method, then calls the existing negotiator-row update path to set `avatar_url`. Upload failure shows the existing generic error snackbar pattern (`listing_error_generic`); the row is left unchanged and the user can retry.

## Testing

- `ListingOwner` round-trip test: `avatarUrl`/`isOnline` parse correctly from JSON, including absent/null cases.
- `NegotiatorAvatar` widget tests: renders the network image when `avatarUrl` is set, renders the initials fallback when null, shows the online dot only when `isOnline` is true.
- Each of the 9 rollout call sites gets a small widget-test assertion that `NegotiatorAvatar` is present (reusing each screen's existing test fixtures).
- `updateLastSeen()`/`uploadAvatar()` (Supabase-boundary repository methods) are **not** unit-tested, per this project's established convention — manually verified after the migration and bucket are applied, same as every prior repository method.

## Out of Scope

- Realtime (session-level) presence via Supabase Realtime Presence channels — the heartbeat approach was chosen for simplicity; may be revisited later if 2-minute granularity proves insufficient.
- `main_dashboard_screen.dart` — explicitly excluded by the user; can be added later as a small follow-up reusing the same `NegotiatorAvatar` widget.
- Cropping/resizing the uploaded photo client-side — uploaded as-is (same as this app's existing listing/requirement photo uploads, which also don't crop).
