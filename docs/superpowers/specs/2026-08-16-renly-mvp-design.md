# renly — MVP Design

Status: approved (2026-08-16). Design/features expected to change and grow as build progresses — this doc captures the starting point, not a frozen spec.

## Goal

Verified co-broking mobile app for Malaysian Real Estate Negotiators (REN/REA), per `Fakhrullah_Renly_Project_Proposal.pdf`. Solo developer, first Flutter project, priority is speed over strict adherence to the proposal's 3-month calendar.

## Reference material already in repo

- `Fakhrullah_Renly_Project_Proposal.pdf` — problem statement, ERD, matching algorithm, RLS design, objectives.
- `stitch_renly_property_agent_network/` — 13 Google Stitch screen mockups (`screen.png` + `code.html` each): splash, onboarding x3, login/register selection, registration (personal/professional), verification pending, main dashboard, marketplace, my inventory, post listing, property detail, messages, profile settings, logo.
- `stitch_renly_property_agent_network/lumina_prime/DESIGN.md` — design system: colors (Vibrant Lime `#536600`/`#d4ff00` primary, Deep Charcoal secondary, Electric Violet tertiary, off-white `#f9faf7` background), typography (Syne headlines / Hanken Grotesk body / JetBrains Mono data labels), 8pt spacing grid, shape/elevation/component rules.

These are implementation references, not to be redesigned from scratch — Flutter UI should port this system, not invent a new one.

## Tech stack

- Client: Flutter (Dart), Android first, iOS same codebase later.
- State management: **Riverpod** — chosen over Bloc (less boilerplate) and GetX (less testable/scalable for RLS-gated multi-role data). Reassess only if a specific screen proves Riverpod awkward.
- Backend: Supabase — Postgres, Auth, Storage, Realtime (messaging), Row-Level Security enforced in DB (not client).
- Notifications: Firebase Cloud Messaging.
- Billing: Google Play Billing (Free / Professional subscription tiers).
- Localization: **easy_localization** (JSON string tables, no ARB/codegen) — Bahasa Melayu + English, device-locale default with English fallback, switch exposed in Profile Settings screen.

## Project structure

```
lib/
  core/            # theme (ported from Lumina Prime DESIGN.md), constants, router, supabase client init
  features/
    auth/          # registration, tag-scan verification (camera + manual fallback)
    listing/
    requirement/
    matching/
    collaboration/ # cobroke_request -> message -> agreement
    subscription/
    profile/
  l10n/            # en.json, ms.json
assets/
```

Each `features/*` folder is self-contained: its own widgets, providers, and Supabase queries. No cross-feature reach-in — shared stuff goes in `core/`.

## Database (from proposal ERD, unchanged)

9 tables: `agency`, `negotiator`, `verification_record`, `listing`, `requirement`, `match`, `cobroke_request`, `message`, `agreement`. Foreign keys as specified in proposal Table 6.1. Every table gets an explicit deny-by-default RLS policy — no table ships without one (proposal §7.3 flags this as the highest-risk item for a solo dev).

## Matching algorithm (from proposal §6.4, unchanged)

Mandatory filters: `transaction_type`, `state` (mismatch = disqualified). Weighted score: location/district up to 30, price (graduated: full weight in-budget, reduced up to 10% over max, zero beyond) up to 35, property type up to 25, bedroom count up to 10. Below-threshold pairs discarded, not stored.

## Build order (compressed — no calendar months, sequential milestones)

1. Git init, Flutter scaffold, Supabase project wired, theme ported from `DESIGN.md` into `ThemeData`.
2. Auth + verification module — manual credential entry first (camera tag-scan is an enhancement, proposal's own fallback design), Supabase Auth + `negotiator`/`verification_record` tables + RLS.
3. Listing + Requirement CRUD, matching against `marketplace` / `my_inventory` / `post_listing` mockups.
4. Matching engine as a Postgres function (weighted scoring above).
5. Collaboration flow — `cobroke_request` → `message` (Supabase Realtime) → `agreement`, matching `messages` mockup.
6. Subscription tiers + Google Play Billing gate (posting limits, notification delay for Free tier).
7. Localization pass — actually wired in from step 1 onward per-screen, not retrofitted at the end.
8. Polish + manual test pass on physical Android device (camera + push notification behavior per proposal §7.3).

## Explicitly deferred / out of scope for now

- `agency` account activation (table exists per proposal's schema-migration argument, but no agency-side UI yet).
- Peer rating/reputation system (proposal survey Figure 9.13 shows lowest demand, 11.8%).
- iOS build (same codebase, but not tested/released this pass).

## Open — will evolve

User has flagged that design and feature set will change and expand as work progresses. This doc is the entry point, not a lock-in; revisit and amend rather than treating deviations as scope creep.
