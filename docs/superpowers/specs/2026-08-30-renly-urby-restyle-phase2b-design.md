# renly — Urby-Inspired Visual Restyle, Phase 2B (Matching/Collaboration) Design

## Goal

Restyle the 7 Matching/Collaboration screens with the neo-brutalist design system Phase 1 established (`BrutalistButton`, `BrutalistCard`, the lime/black/white/purple palette, Space Grotesk typography, Phosphor Bold icons). No functionality, data model, or business logic changes — visual restyle only, same as Phase 1 and Phase 2A. Also extends `BrutalistButton`'s API (deferred gap from Phase 1/2A) with a `fullWidth` toggle, an `icon` slot, and an accessibility `Semantics` fix — all three needed the moment this phase's screens are reached.

## Scope

Sub-phase 2 of 3 in Phase 2's feature-area split (2A Listing/Requirement — done, merged; 2C Profile/Settings/Subscription — future). 2B covers exactly these 7 screens:

**Matching:** `MatchesForListingScreen`, `MatchesForRequirementScreen`, `MyMatchesScreen` — three screens with an identical structural mirror (confirmed via direct diff), each showing a `ListView` of ranked match cards with a "Send Co-Broke" CTA.

**Collaboration:** `MyRequestsScreen` (Received/Sent tabs, largest and most complex screen in this phase — cobroke-request accept/decline, chat entry, inline agreement propose/accept/decline, inline rating), `ProposeAgreementDialog`, `RateDialog` (both `AlertDialog`-based modals), `ChatScreen` (message list + inline send button).

`send_cobroke_request_action.dart` (a shared action function, not a screen) is out of scope — nothing to restyle.

## BrutalistButton API extension

Confirmed backlog items from Phase 1's and Phase 2A's final reviews, both now load-bearing for this phase's screens:

- **`fullWidth: bool = true`** (new, additive) — when `false`, width shrinks to fit content (label + optional icon + padding) instead of `double.infinity`. Height stays 56px (this app's established touch-target constant) regardless. Needed for every side-by-side button pair this phase introduces (Accept/Decline, Agreement Accept/Decline, dialog Cancel/Confirm) and every compact inline button (Chat's send button next to a `TextField`).
- **`icon: IconData? = null`** (new, additive) — renders an `Icon` before the label with an 8px gap, same color as the label text. Callers pass Phosphor icons (e.g. `PhosphorIcons.check(PhosphorIconsStyle.bold)`), matching this app's established Bold-weight-for-functional-icons convention from Phase 1.
- **`Semantics(button: true, enabled: isEnabled, ...)` wrapper** (fix, not additive) — Phase 2A's final review found disabled `BrutalistButton`s signal only via `Opacity(0.5)`, a purely visual cue invisible to TalkBack/VoiceOver, since `InkWell` alone doesn't emit the M3 button/enabled semantics role `ElevatedButton`/`OutlinedButton` did before Phase 1. Explicitly recommended folding into this phase since it's already opening the file. Fixes all 17 existing call sites (Phase 1 + 2A) plus this phase's new ones in one place.

Both new parameters default to the widget's current behavior (`fullWidth: true`, `icon: null`) — all 17 existing call sites across Phase 1 and Phase 2A stay byte-identical in rendered output.

## Screen-by-screen mapping

| Screen | Element | Current | Target | Variant | fullWidth | Icon |
|---|---|---|---|---|---|---|
| MatchesForListingScreen | card | `Card`+`InkWell` | `BrutalistCard`+`InkWell` | — | — | — |
| | Send Co-Broke button | `ElevatedButton` | `BrutalistButton` | primary | true | `handshake` bold |
| MatchesForRequirementScreen | (structural mirror of above) | | | | | |
| MyMatchesScreen | (mirror + `isMyListing` branch) | | | | | |
| MyRequestsScreen | card | `Card` | `BrutalistCard` | — | — | — |
| | Accept button | `ElevatedButton` | `BrutalistButton` | primary | false | `check` bold |
| | Decline button | `OutlinedButton` | `BrutalistButton` | secondary | false | `x` bold |
| | Chat button | `OutlinedButton` | `BrutalistButton` | secondary | true | `chatCircle` bold |
| | Propose Agreement button | `OutlinedButton` | `BrutalistButton` | secondary | true | — |
| | Agreement Accept button | `ElevatedButton` | `BrutalistButton` | primary | false | `check` bold |
| | Agreement Decline button | `OutlinedButton` | `BrutalistButton` | secondary | false | `x` bold |
| | Rate/Edit-rating button | `OutlinedButton` | `BrutalistButton` | secondary | true | `star` bold |
| | Retry button (error state) | `TextButton` | **unchanged** | — | — | — |
| ProposeAgreementDialog | Cancel button | `TextButton` | `BrutalistButton` | secondary | false | — |
| | Confirm button | `ElevatedButton` | `BrutalistButton` | primary | false | `check` bold |
| RateDialog | Cancel button | `TextButton` | `BrutalistButton` | secondary | false | — |
| | Confirm button | `ElevatedButton` | `BrutalistButton` | primary | false | `check` bold |
| | star picker (×5) | `IconButton` + `Icons.star`/`star_border` | local `_BrutalistStar` widget | — | — | `star` bold (selected) / regular (unselected) |
| ChatScreen | send button | `ElevatedButton` | `BrutalistButton` | primary | false | `paperPlaneRight` bold |

The `MyRequestsScreen` error-state Retry `TextButton` (inside `_AgreementSection`'s error branch, a `Row` with `Expanded(Text(...))` + `TextButton`) is explicitly left unchanged — a minor recovery action, not a primary CTA, consistent with this phase's restraint on scope (same reasoning Phase 2A applied to screens' non-CTA elements).

## Star picker redesign

`RateDialog`'s 5-star picker currently uses `IconButton(icon: Icon(Icons.star / Icons.star_border), onPressed: ...)`. Replaced with a local `_BrutalistStar` widget (private to `rate_dialog.dart`, not a shared core widget — single use site, avoids premature abstraction): a `GestureDetector` wrapping `Icon(PhosphorIcons.star(selected ? PhosphorIconsStyle.bold : PhosphorIconsStyle.regular), color: AppColors.ink, size: 32)`, `Padding(all: 8)` around the icon (48×48 touch target, matching `IconButton`'s `kMinInteractiveDimension`), and a `Semantics(button: true, label: '<localized "Star"> N', selected: ...)` wrapper — `GestureDetector` alone, unlike `IconButton`, contributes a tap action but no button role/label, so this app's first hard-shadow-free interactive control still needs explicit semantics, same lesson as `BrutalistButton`'s own accessibility fix. No button chrome (no border/shadow/fill) — a star rating control is not a CTA button, so it does not become a `BrutalistButton`.

## Card treatment

`MyRequestsScreen`'s and all 3 Matching screens' plain `Card()` become `BrutalistCard`, matching Phase 2A's precedent exactly (`InkWell`-wrapped, hard hard-shadow hidden by the same accepted Phase-1 ripple-loss trade-off). No `StatusBadge` use in this phase — none of these 7 screens show a single-item status header the way Phase 2A's 2 detail screens did; `MyRequestsScreen`'s per-row status (`_statusLabel`) stays as plain `Text`, consistent with its current design (a badge per Received/Sent row would compete visually with the Accept/Decline/Chat button row already there).

## Illustration slots

3 new empty-state illustration slots, wired the same way as Phase 1 and Phase 2A (`Image.asset(...)` + `errorBuilder` fallback to empty space, declared in `pubspec.yaml`'s existing `assets/illustrations/` directory): `matching_empty.png` (shared by all 3 Matching screens' empty state), `cobroke_request_empty.png` (`MyRequestsScreen`'s empty state, both tabs). No real artwork produced this sub-phase (no image-generation tool confirmed available) — code-path wiring only, consistent with the user's explicit choice to keep pace with the established pattern app-wide rather than pause on 6 already-reserved-but-empty slots from Phase 1/2A.

## Testing approach

Same boundary as Phase 1/2A: `flutter analyze` and the full `flutter test` suite must stay clean throughout. Each of the 7 screens' existing widget tests must be checked for `find.byType(ElevatedButton/OutlinedButton/TextButton)` or `find.byIcon(Icons.star/Icons.star_border)` matchers that will break once widgets swap — a real, repeated risk in every prior phase, expected to recur here. `BrutalistButton`'s own test file (`brutalist_button_test.dart`) gains new tests for `fullWidth: false` (asserts width is not `double.infinity`), the `icon` parameter (asserts an `Icon` renders with the given `IconData`), and the `Semantics` wrapper (asserts `button: true` and `enabled` matches `onPressed != null`, via `tester.getSemantics()`). No golden-image tests, consistent with this project's established convention.

## Explicitly deferred / out of scope

- Sub-phase 2C (Profile/Settings/Subscription) — separate future design cycle.
- Real illustration artwork for all 9 empty-state slots now reserved app-wide (2 Phase 1 + 4 Phase 2A + 3 this phase).
- Any functional/business-logic change to any of the 7 screens.
- `MyRequestsScreen`'s Retry `TextButton` — left as a plain Material widget, not a CTA.
- A shared/exported `_BrutalistStar` widget — kept private to `rate_dialog.dart` until a second use site exists.
