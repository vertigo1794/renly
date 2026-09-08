# Profile & Settings Ultra-Premium Restyle — Design

## Overview

`ProfileScreen` is restyled from a Stitch mockup ("Renly - Profile & Settings (Ultra-Premium Edition)", project `13581751397915601898`, screen `9ffe7238cef14edb9cb5955d226c0398`, HTML fetched to `/tmp/stitch_profile_settings/profile_settings.html`). Per this project's own never-fabricate-data convention (enforced across every prior restyle this session — Post Broadcast, Property Detail, Negotiator Avatar + Online Presence), every mockup element gets one of three treatments, decided explicitly with the user:

- **Real** — backed by an existing or newly-computed real value, hidden/omitted when the backing value is null/false.
- **Reframed** — the mockup's copy is replaced with an honest statement about a mechanic that genuinely exists today (often by reusing a field/toggle this app already has elsewhere).
- **Deferred/Dropped** — the underlying capability doesn't exist and is either large enough to be its own future sub-project (Digital Card, Bank Account & Payouts, Co-Broke Escrow Wallet) or has no real justification to build at all (Default Split Rate, license expiry date) — omitted from this pass.

## Element-by-Element Decisions

| Mockup element | Decision | Notes |
|---|---|---|
| Header (wordmark, REN pill, share, bell) | Real | Same pattern already used on Marketplace/Messages/Property Detail headers — pure restyle, no new data. |
| Avatar, name, REN, agency | Real | Already shipped (Negotiator Avatar + Online Presence milestone). |
| "BOVAEA / LPPEH VERIFIED" badge | Reframed | Generic "Verified" badge using the real `verificationStatus == 'approved'` check — no specific certifying-body name invented. |
| "Edit Profile" button | Real, UI change | Becomes a toggle button that shows/hides the existing `_EditForm` (currently always visible). `_EditForm` starts HIDDEN; tapping "Edit Profile" reveals it, tapping again (or a successful save) hides it. Not a new capability — a visibility state change around the form that already exists. |
| "Digital Card" button | Deferred | A shareable digital business-card view/generator is a genuinely new feature (new screen, QR/share logic) — logged as a future sub-project, not built now. |
| Active Listings / Deals Closed / Trust Score stats | Real | Already real (`profileCountsProvider`, `_TrustScoreCard`) — carried forward unchanged. |
| "Co-Broke Vol. RM 38.4M" | Real, new computation | Sum of `listing.price` across every `agreement` with `status = 'accepted'` that this negotiator is a party to. See Data Flow below. |
| "Co-Broke Escrow Wallet" card + Withdraw | Dropped | No payment/escrow/wallet subsystem exists anywhere in this app (confirmed via full-repo grep) — this app's only money-movement feature is Stripe subscription billing, a completely different thing. Logged as a future sub-project if ever pursued. |
| "Auto-Match Radar" toggle | Real, shortcut | The backing field (`negotiator.notify_match`) and its real toggle already exist on the Notification Settings screen (`/settings/notification`, via `SettingsRepository`) — this adds a second real toggle bound to the same data on the Profile screen itself, not a new concept. |
| "Default Split Rate" | Dropped | No negotiator-level default-split field exists (Listing/Requirement each carry their own per-item split); no real need identified for one. |
| "Designated Areas" (multiple tags) | Reframed | Shown using the real `territory` field (a single free-text string) — relabeled honestly as one territory, not fabricated as multiple discrete tags. |
| "REN License & Verification: ...until Dec 2026" | Reframed | Shows the real approved/pending/rejected status only — the expiry date is dropped (no such date is tracked anywhere; the REN board has no API this app integrates with). |
| "Bank Account & Payouts" | Dropped | Same reasoning as the Escrow Wallet — no backing subsystem, logged as a future item if ever pursued. |
| "Security & Biometrics: Face ID Enabled" | Real, shortcut | The real biometric-login feature (`biometricLoginEnabledProvider`, `account_settings_screen.dart`) already exists — this adds a real status display on the Profile screen linking through to Account Settings to change it. |
| "Push Notifications" row | Real | Already a real `ListTile` — unchanged. |
| "Renly Agent Support: Dedicated 24/7 VIP Concierge" | Reframed | Relabeled onto the existing real Help settings row — the fabricated "24/7 VIP Concierge" framing is dropped, honest "Get help" copy used instead. No new row, no new support channel. |
| "Terms of Service & Privacy" row | Real | Already a real `ListTile` (Privacy settings) — unchanged. |
| Requirement Board / My Requirements / My Matches / My Requests shortcuts | Real, kept | Not present in the mockup, but real and load-bearing navigation this screen already provides — not removed just because the mockup omits them. |
| Footer "Renly v2.4.0 • ..." | Dropped | Cosmetic-only, no version-tracking infrastructure in this app; not worth adding for a footer string. |

## Data Flow — Co-Broke Volume

No new migration needed. `agreement`'s own RLS policy (`agreement_select`, `supabase/migrations/0009_agreement.sql`) already scopes every visible row to one where the current user is a party (the agreement's own initiator, or the owner of the underlying match's listing/requirement) — so a plain client-side query under that policy is already correctly scoped, the same pattern `ProfileRepository.countDealsClosed()` already uses for "Deals Closed."

New `ProfileRepository.fetchCoBrokeVolume(negotiatorId)` queries `agreement` filtered to `status = 'accepted'`, using PostgREST's foreign-key embedding to pull each accepted agreement's underlying listing price in one round trip (`agreement.request_id → cobroke_request.match_id → match.listing_id → listing.price`, all real foreign keys already in place since `0006_matching.sql`/`0007_cobroke_request.sql`/`0009_agreement.sql`), and sums the prices client-side. Returns `0` (not null) when the negotiator has no accepted agreements yet — this is a real "no volume yet" fact, not a fabricated fallback.

## Screen Structure

`ProfileScreen`'s `build()` gains: a real header (mirroring the shared header pattern), the reframed "Verified" badge next to the name, an "Edit Profile" toggle button controlling `_EditForm`'s visibility, a 4th stat card ("Co-Broke Vol.") alongside the existing 3, a new small "Co-Broking Preferences" card (Auto-Match Radar toggle + Designated Areas display), a new small "Compliance" row (verification status + Security & Biometrics shortcut), and the existing settings-navigation card's Help row copy adjusted. No existing real behavior (counts, ratings, sign-out, language switch, avatar upload, territory/specialisation edit) is altered — this is additive/relabeling only, per the element table above.

## Testing

- `ProfileRepository.fetchCoBrokeVolume` is a Supabase-boundary method — not unit-tested, per this project's established convention; manually verified once real accepted agreements exist for a test account.
- The "Verified" badge reframe, Edit Profile toggle, Auto-Match Radar shortcut toggle, and Security & Biometrics shortcut display all get real widget tests (provider-override style, matching this file's existing test conventions) — real state assertions, not tautological.
- `flutter analyze` + full suite + l10n parity (en.json/ms.json) run after every task, per this project's standing convention.

## Out of Scope (logged as future sub-projects, not built now)

- Digital Card (shareable business-card view/generator).
- Co-Broke Escrow Wallet (payment/escrow/withdraw subsystem).
- Bank Account & Payouts (payout subsystem).
