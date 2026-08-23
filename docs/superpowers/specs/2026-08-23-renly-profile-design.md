# renly — Profile Management (Core) Design

Status: approved (2026-08-23). Ninth milestone. Covers proposal §6.1 module 2 of 6 ("Profile Management Module") — the last core module of the six the proposal defines, all others (Auth+Verification, Listing, Requirement, Matching, Collaboration) now merged.

## Goal

Let a negotiator view and partially edit their own verified professional profile, sign out of the app (currently impossible — the single most-flagged missing piece of UX across every prior milestone's backlog), and switch the app's language, all from one screen reached via a new icon on `HomePlaceholderScreen`'s app bar.

## Scope decision

The Stitch mockup for this screen (`stitch_renly_property_agent_network/profile_settings/code.html`) is significantly more ambitious than the proposal's own text and ERD: it shows a Trust Score rating, a "View Full Report" action, and Notification/Account/Privacy/Help settings sub-pages. **Resolved with the user**: this milestone ("Profile core") builds only what the proposal's own module description and ERD support, plus two long-standing backlog items that naturally belong on a profile screen:

- Display: registration number, agency, territory, property specialisation, verification status.
- Edit: territory and property specialisation only — registration number, agency, and verification status stay read-only, since they're tied to the verification pipeline and letting a client edit them client-side would reopen the exact class of self-approval risk the Auth+Verification milestone's Critical RLS fix closed.
- Sign-out button.
- Language switcher (EN/MS) — `easy_localization` has been wired app-wide since Scaffold, but no UI has ever let a user actually change locale.
- Two counts pulled from existing data, since the user explicitly asked for them despite being mockup-only, not proposal-scoped: Active Listings, Deals Closed.

**Explicitly out of scope, deferred to future sub-milestones** (the user chose to sequence this way, mirroring how Collaboration was split into three):
- A full ratings/reviews system for the mockup's "Trust Score" — this has no data source anywhere in the ERD and needs its own table, RLS, a rating-submission mechanism, and design decisions (who rates whom, when, on what scale) that haven't been resolved yet. Real scope of its own, not an extra field.
- Notification/Privacy/Help settings sub-pages — mostly hollow without a real backend behind them (no push notification system exists yet, no privacy-preference storage, no help content).

## Data model

`property_specialisation` is mentioned in the proposal's module description but is not a column in the `negotiator` table per the ERD. **Resolved with the user**: add it as a real column, matching the proposal's literal wording rather than treating it as descriptive-only.

```sql
alter table negotiator add column if not exists property_specialisation text;

-- Territory and property_specialisation are the only user-editable fields
-- on this table. Every other column (ren_number, agency_id, full_name,
-- verification_status, subscription_tier) stays unwritable by the client --
-- UPDATE was fully revoked from `negotiator` during Auth+Verification's
-- Critical self-approval fix (0002_rls_hardening.sql), and this grant is
-- the first UPDATE access the client has had on this table since.
grant update (territory, property_specialisation) on negotiator to authenticated;
```

No RLS policy changes needed: `negotiator_select_own` (from `0001_auth_verification.sql`) already lets a negotiator read their own full row, including the new column once added. `negotiator_update_own` already exists too — only the column grant was missing. `agency_select_all` already lets any authenticated user read agency rows, which is how the profile screen resolves the current user's agency name via their `agency_id`.

## Repository

No RPC needed — plain composed queries under existing RLS:

- `fetchMyProfile()` — `select()` on `negotiator` (own row, via `negotiator_select_own`) joined with a follow-up `agency` lookup by `agency_id` (via `agency_select_all`). Returns a `Profile` model carrying negotiator fields + agency name.
- `updateProfile({territory, propertySpecialisation})` — `update` on `negotiator`, `.eq('negotiator_id', ...)`, writing only the two grantable columns.
- `countActiveListings()` — `count` query on `listing` filtered to the current user's own active rows. RLS already scopes `listing_select` to own-or-active rows; filtering by `negotiator_id = auth.uid()` in the query itself (not relying on RLS alone) makes the count's intent explicit.
- `countDealsClosed()` — `count` query on `agreement` filtered to `status = 'accepted'`. No negotiator-id filter needed in the query: `agreement_select`'s RLS already scopes every visible row to one where the current user is a party, so a plain count under that policy is already "my deals."

## Screen

`ProfileScreen` (new route `/profile`): header card (full name, REN number, agency name, a verification-status badge reusing the visual pattern already established on `PropertyDetailScreen`/`MyRequestsScreen` cards), two stat cards (Active Listings, Deals Closed), an edit form (territory + property specialisation text fields, Save button, following the established `_submitting`/error-copy pattern from every prior form in this app), a language switcher (EN/MS segmented toggle calling `context.setLocale`), and a Sign Out button at the bottom (destructive styling, calls `Supabase.instance.client.auth.signOut()` — the existing `GoRouterRefreshStream` already listens to `onAuthStateChange`, so signing out automatically redirects to `/` with no extra router wiring needed).

**Access point:** a new profile icon added to `HomePlaceholderScreen`'s `AppBar` (its `actions` list), not retrofitted onto every other screen's app bar — Home is already the app's navigation hub (every other feature link lives there too), so this keeps the change scoped to one file instead of touching every screen.

## File structure

```
lib/features/profile/
  profile_repository.dart   # fetchMyProfile, updateProfile, countActiveListings, countDealsClosed
  profile_providers.dart    # profileRepositoryProvider, myProfileProvider, profileCountsProvider
  profile_screen.dart       # ProfileScreen
  models/
    profile.dart            # negotiatorId, fullName, renNumber, agencyName, territory, propertySpecialisation, verificationStatus
```

## Router

New route, requiring a session: `/profile` → `ProfileScreen`.

## Manual setup

`supabase/migrations/0010_profile.sql` — single file, adds the `property_specialisation` column and the new UPDATE grant. Re-runnable from the start (`add column if not exists`), same pattern as every prior migration. No storage bucket, no Auth-dashboard changes.

## Testing approach

Same boundary as every prior milestone: `ProfileRepository` untested directly (Supabase-calling code). `Profile.fromJson` gets a real unit test. `ProfileScreen` gets widget tests via provider override (form validation, Save success/failure, Sign Out button present and wired, language switcher present) following the established pattern.

## Explicitly deferred / out of scope for this milestone

- Ratings/reviews system (the mockup's "Trust Score") — needs its own design cycle.
- Notification/Privacy/Help settings sub-pages — no real backend to back them yet.
- Profile photo upload/edit.
- "Share profile" action.
- Editing registration number, agency, or verification status (tied to the verification pipeline, intentionally read-only).
- Retrofitting a profile icon onto every screen's app bar (Home-only for this milestone).
