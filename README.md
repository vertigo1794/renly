# Renly

Verified co-broking mobile app for Malaysian Real Estate Negotiators (REN/REA). Solo-developer Final Year Project — Flutter + Supabase.

Renly lets negotiators list properties and client requirements, get matched automatically by a weighted scoring algorithm, and collaborate on deals (co-broke request → chat → agreement) inside one verified, RLS-secured platform.

## Features

- **Auth & verification** — registration (personal + professional details), REN/REA tag verification (camera scan with manual fallback), email verification flow.
- **Listing** — post, browse, and manage property listings (marketplace + personal inventory).
- **Requirement** — post client requirements (buy/rent briefs) for other negotiators to match against.
- **Matching** — automatic weighted matching between listings and requirements.
- **Collaboration** — co-broke requests, realtime chat, and digital agreements between negotiators.
- **Subscription** — Free / Professional tiers gating posting limits and notification delay, billed via Stripe.
- **Ratings** — post-deal reviews between collaborating negotiators.
- **Notifications** — push notifications (FCM) with deep-linking into the relevant screen.
- **Localization** — full Bahasa Melayu + English support, device-locale default.

## Tech stack

| Layer | Choice |
|---|---|
| Client | Flutter (Dart), Android-first |
| State management | Riverpod |
| Backend | Supabase — Postgres, Auth, Storage, Realtime |
| Authorization | Postgres Row-Level Security (enforced in DB, not client) |
| Notifications | Firebase Cloud Messaging |
| Billing | Stripe (subscription tiers) |
| Localization | easy_localization (JSON string tables) |
| Routing | go_router |

## Data model

9 tables driven by the project ERD: `agency`, `negotiator`, `verification_record`, `listing`, `requirement`, `match`, `cobroke_request`, `message`, `agreement`. Every table ships with an explicit deny-by-default RLS policy.

### Matching algorithm

Mandatory filters: `transaction_type` and `state` must match, otherwise the pair is disqualified. Weighted score out of 100:

- Location/district — up to 30
- Price — up to 35 (full weight in-budget, graduated down to 10% over max, zero beyond)
- Property type — up to 25
- Bedroom count — up to 10

Pairs below the score threshold are discarded, not stored.

## Project structure

```
app/lib/
  core/            # theme, constants, router, Supabase client init
  features/
    auth/
    listing/
    requirement/
    matching/
    collaboration/   # cobroke_request -> message -> agreement
    subscription/
    profile/
    ratings/
    notifications/
    settings/
    home/
assets/translations/  # en.json, ms.json
```

Each `features/*` folder is self-contained (widgets, providers, Supabase queries). No cross-feature reach-in — shared code lives in `core/`.

## Getting started

```bash
cd app
flutter pub get
flutter run
```

Requires a `.env` with Supabase project credentials (see `flutter_dotenv` config in `main.dart`).

## Status

Actively developed. Design and feature set are expected to evolve — this README reflects the current state, not a frozen spec.
