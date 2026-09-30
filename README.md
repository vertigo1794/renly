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

## Install the APK (Android)

1. Download the latest APK from the [Releases page](https://github.com/vertigo1794/renly/releases/latest).
2. On your Android phone, open the downloaded `app-release.apk` file.
3. If prompted "install unknown apps", tap **Settings** → allow installs from that source (browser / file manager), then go back and tap **Install**.
4. Open **Renly** once installed.

## How to use the app

1. **Register** — sign up with your personal + professional details (REN/REA tag). Verify your account via email, then wait for tag verification (camera scan or manual entry).
2. **Post a listing** — go to My Inventory → Post Listing to add a property you're selling/renting out.
3. **Post a requirement** — go to Requirement Board → Post Requirement to describe what your client is looking for.
4. **Check matches** — the app automatically scores your listings/requirements against everyone else's; view matches from the listing/requirement detail screen.
5. **Collaborate** — send a co-broke request to a matched negotiator, chat in real time once accepted, then formalize the deal with a digital agreement.
6. **Manage subscription** — Free tier has posting limits and delayed notifications; upgrade to Professional in Settings → Subscription for full access.
7. **Switch language** — toggle Bahasa Melayu / English in Settings.

## Status

Actively developed. Design and feature set are expected to evolve — this README reflects the current state, not a frozen spec.

## What's new in v1.0.1

- **Geolocation** — "Use my current location" on Post Listing/Post Requirement captures real GPS coordinates, reverse-geocodes to Area/State, and powers an accurate "View Map" link on Property Detail.
- **Offline-first Marketplace** — listings are cached locally after every successful fetch; going offline shows the last-saved listings with a clear banner instead of an empty error screen.
- **Background match scoring** — listing/requirement matching now runs on a background isolate (`compute()`), keeping the UI thread free as the network of listings/requirements grows.
- **Drag-to-reorder photos** — reorder a listing's photo strip before submitting, via a native reorderable list.
- **Responsive layouts** — Marketplace and Requirement Board switch to a multi-column grid on tablet-width screens.
- **Real HTML5/CSS3/JavaScript/jQuery module** — an in-app Commission Split Calculator is a genuine HTML5 document (semantic markup, CSS3 flexbox/custom properties, jQuery-driven live validation) rendered in an embedded WebView, with a real AJAX call pulling live active-listing counts from the backend.
- **Literal MySQL integration** — a small, fully separate MySQL database tracks property view counts, connected to directly over the MySQL wire protocol (independent of the app's Supabase/Postgres core).
- **Clickable legal pages** — Terms of Service and Privacy Policy are now real, cross-linked HTML documents (with working hyperlinks and a support email link) instead of static text.

## Install the v1.0.1 APK

Same steps as above — grab `app-release.apk` from the [v1.0.1 release](https://github.com/vertigo1794/renly/releases/tag/v1.0.1).
