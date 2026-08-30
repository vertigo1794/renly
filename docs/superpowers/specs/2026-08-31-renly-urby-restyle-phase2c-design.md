# renly — Urby-Inspired Visual Restyle, Phase 2C (Profile/Settings/Subscription) Design

## Goal

Restyle the 7 Profile/Settings/Subscription screens with the neo-brutalist design system (`BrutalistButton`, `BrutalistCard`, Phosphor Bold icons) established across Phase 1, 2A, and 2B. No functionality, data model, or business logic changes — visual restyle only. This closes out the Urby Restyle initiative's screen coverage (24 screens across Phase 1 + 2A + 2B + 2C).

## Scope

Sub-phase 3 of 3 in Phase 2's feature-area split (2A Listing/Requirement — done; 2B Matching/Collaboration — done). 2C covers 7 screens: `ProfileScreen`, `AccountSettingsScreen`, `NotificationSettingsScreen`, `PrivacyScreen`, `HelpScreen`, `SubscriptionScreen`, `ReviewsScreen`. `ReviewsScreen` lives under `features/ratings/` but is reached only from `ProfileScreen`'s Trust Score card (`/reviews` route), so it's grouped here rather than left as an orphaned future phase.

`PrivacyScreen` and `HelpScreen` contain no `Card`/button widgets to swap (confirmed by direct read — pure static text screens) — both already inherit the global theme's background/typography automatically via `app_theme.dart`. No changes needed to either file; they are in scope only in the sense of being verified, not touched.

`BrutalistButton`'s API is already feature-complete as of Phase 2B (`fullWidth`, `icon`, `Semantics`) — this phase needs no widget-level work, only screen-level restyling.

## Screen-by-screen mapping

| Screen | Element | Current | Target | Variant | fullWidth | Icon |
|---|---|---|---|---|---|---|
| ProfileScreen | App Settings list card (5 `ListTile` nav rows) | `Card` | `BrutalistCard` | — | — | — |
| | `_StatCard` (×2: active listings, deals closed) | `Card` | `BrutalistCard` | — | — | — |
| | `_TrustScoreCard` (tappable, navigates to `/reviews`) | `Card`+`InkWell` | `BrutalistCard`+`InkWell` | — | — | — |
| | Sign Out button | `OutlinedButton` | `BrutalistButton` | secondary | true | `signOut` bold |
| | Save button (`_EditForm`) | `ElevatedButton` | `BrutalistButton` | primary | true | `check` bold |
| AccountSettingsScreen | Password submit button | `ElevatedButton` | `BrutalistButton` | primary | true | `check` bold |
| NotificationSettingsScreen | 3× `SwitchListTile` (match/message/co-broke toggles) | bare `ListView` | wrapped in `BrutalistCard` | — | — | — |
| SubscriptionScreen | Refresh button (timeout state) | `ElevatedButton` | `BrutalistButton` | primary | true | `arrowClockwise` bold |
| | Manage Subscription button (professional tier) | `ElevatedButton` | `BrutalistButton` | primary | true | `gear` bold |
| | Upgrade button (free tier) | `ElevatedButton` | `BrutalistButton` | primary | true | `crown` bold |
| ReviewsScreen | Review row card (non-tappable) | `Card` | `BrutalistCard` | — | — | — |

Every Retry `TextButton` (error-state fallback, present in `AccountSettingsScreen`, `NotificationSettingsScreen`, `SubscriptionScreen`) is explicitly out of scope — matches the established convention from every prior phase (a minor recovery action, not a primary CTA).

## Card treatment

`NotificationSettingsScreen`'s 3 `SwitchListTile`s currently have no `Card` wrapper at all (a bare `ListView`). Wrapping them in a single `BrutalistCard` (matching `ProfileScreen`'s "App Settings" list treatment) is a deliberate, explicit addition — not just a widget swap — for visual consistency between the two settings-list screens a user navigates between. The switches themselves need no styling change: Phase 1's global `switchTheme` (lime track, ink thumb when selected) already applies automatically.

`_TrustScoreCard` keeps its `InkWell`-wrapped tappable pattern (single `onTap` owner, same accepted ripple-loss trade-off as every other `BrutalistCard`+`InkWell` composition since Phase 1). `_StatCard` and the App Settings list card are non-tappable, matching `MyRequestsScreen`'s precedent from Phase 2B (`BrutalistCard` with no `InkWell` wrapper needed).

## Illustration

`ReviewsScreen`'s empty state (no reviews received yet) gets an illustration slot wired the same way as every prior phase: `Image.asset('assets/illustrations/reviews_empty.png', errorBuilder: (context, error, stackTrace) => const SizedBox.shrink())`. No real artwork produced this sub-phase — code-path wiring only, consistent with the established pattern (10 slots now reserved app-wide across all 4 phases, still zero art produced; this is a known, already-logged backlog item, not newly introduced scope).

## Testing approach

Same boundary as every prior phase: `flutter analyze` and the full `flutter test` suite must stay clean throughout. Each affected screen's existing widget tests must be checked for `find.byType(Card/ElevatedButton/OutlinedButton)` matchers that would break on a widget-type swap — this risk has recurred in every phase and is expected here too, though Phase 2A and 2B both showed most of this project's screens use text-based (`find.text`) assertions that survive widget-type swaps untouched. No golden-image tests.

## Explicitly deferred / out of scope

- Real illustration artwork for all 10 empty-state slots now reserved app-wide (2 Phase 1 + 4 Phase 2A + 3 Phase 2B + 1 this phase).
- Any functional/business-logic change to any of the 7 screens.
- The 4 error-state Retry `TextButton`s.
- `PrivacyScreen`/`HelpScreen` — confirmed to have nothing to restyle.
- This closes the Urby Restyle initiative's planned screen coverage — no Phase 2D is anticipated after this.
