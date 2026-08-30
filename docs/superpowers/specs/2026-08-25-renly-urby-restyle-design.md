# renly — Urby-Inspired Visual Restyle (Phase 1: Design System Core) Design

## Goal

Replace renly's unused "Lumina Prime" design system with a new visual identity inspired by a reference app the user admires purely for its aesthetic ("Urby" — a fractional-property-investment app whose business concept is NOT being adopted, only its look). This is a **design/theme change only** — no functionality, screen flow, data model, or business logic changes. All 14 functional milestones already built stay exactly as they are.

Phase 1 (this design/plan): rebuild the theme source of truth (`app_theme.dart`/`app_colors.dart`) and apply it fully to 3 flagship screens — `AuthSelectionScreen`, `LoginScreen`, `HomePlaceholderScreen` — to validate the new direction before rolling it out to the remaining ~17 screens in later phases.

## Why Lumina Prime is being replaced, not extended

Lumina Prime (`stitch_renly_property_agent_network/lumina_prime/DESIGN.md`) was defined at project scaffold time but never actually implemented in the built screens — `HomePlaceholderScreen`/`ProfileScreen` and every other screen use plain, largely unstyled Material widgets. Since nothing depends on Lumina Prime's specifics today, adopting a new direction cleanly is simpler and lower-risk than trying to reconcile two unfinished design systems.

## Palette

```dart
// app/lib/core/theme/app_colors.dart
static const primary = Color(0xFFD2FF00);   // lime -- CTA buttons, active nav indicator, highlights
static const ink = Color(0xFF0A0A0A);       // near-black -- outlines, borders, primary text
static const surface = Color(0xFFFFFFFF);   // white -- backgrounds
static const accent = Color(0xFF7C3AED);    // purple -- secondary accent (status badges, tags), not a primary CTA color
```

## Typography

Single font family: **Space Grotesk**, via the existing `google_fonts` dependency (already in `pubspec.yaml`, no new package needed). Bold geometric sans, reads clearly at both display and body sizes without needing a second pairing font.

- Headings: weight 700-800
- Body: weight 500-600

## Iconography and illustration

Two different asset classes need two different sourcing strategies -- conflating them produces inconsistent, hard-to-recolor results:

- **Functional icons** (nav bar, buttons, in-list icons -- small, need to recolor per state like active/inactive, need broad coverage of ~15-20 distinct meanings): sourced from **`phosphor_flutter`** (new dependency, `flutter pub add phosphor_flutter`), **Bold** weight variant. Free, actively maintained, genuinely thick-stroke by design -- matches the neo-brutalist look natively without custom asset work.
- **Decorative illustration** (hero art, empty-state graphics -- large, few needed, style consistency matters at the composition level not the pixel level): AI-generated per screen, matching the neo-brutalist thick-black-outline + flat-color style. Stored as PNG assets under `app/assets/illustrations/`. Phase 1 needs 2: one hero illustration for the Auth flow, one empty-state illustration for `HomePlaceholderScreen`.

## Component patterns

The defining neo-brutalist signature is a **hard shadow** -- a solid offset black shadow with zero blur, distinct from Material's default soft/blurred elevation shadows:

```dart
BoxShadow(color: AppColors.ink, offset: Offset(4, 4), blurRadius: 0)
```

Applied consistently across:

- **Primary button**: lime fill, `AppColors.ink` border (2-3px), hard shadow, ~12px corner radius (moderate, not sharp 0px -- keeps it approachable rather than harsh)
- **Secondary/outline button**: white/transparent fill, ink border only, no fill shadow needed (visually lighter-weight by design, for secondary actions)
- **Card**: white background, ink border, hard shadow -- same treatment as the primary button for visual consistency
- **Info/banner block**: ink or lime solid background, bold border, bold text -- for standout informational content (e.g. a status banner)
- **Celebratory modal**: card styling + a confetti decoration (static illustration or a lightweight animation), lime CTA button -- for positive-outcome moments
- **Bottom navigation**: white or ink bar, active tab indicated by a solid lime filled circle behind its icon

These become reusable widgets under `app/lib/core/widgets/` (e.g. `BrutalistButton`, `BrutalistCard`) rather than repeated inline styling, so later phases restyling the remaining ~17 screens reuse the same components instead of re-deriving the pattern.

## Testing approach

Pure visual/theme change -- no logic changes, so no new test scenarios to cover. What must hold:

- `flutter analyze` and the full `flutter test` suite stay clean after the restyle.
- **Known risk**: any existing widget test using `find.byIcon(Icons.xxx)` against a widget whose icon is swapped from Material to `PhosphorIcons.xxx` will break. The implementation plan must identify and update any such test in the 3 phase-1 screens.
- No golden-image/screenshot tests are introduced -- this project has never used them, and adding the tooling now would be scope creep unrelated to the restyle itself. Verification is manual: open the 3 restyled screens and visually confirm against this doc.

## Explicitly deferred / out of scope

- The remaining ~17 screens (Marketplace, Listing/Requirement CRUD, Matching, Messaging, Agreements, Ratings, Settings, Subscription, Profile, etc.) -- restyled in future phases, reusing the `BrutalistButton`/`BrutalistCard` components this phase establishes.
- Any change to app functionality, navigation flow, data model, or business logic.
- Golden/screenshot-based visual regression testing.
- A second typography family/pairing -- Space Grotesk alone covers both heading and body needs for this phase.
- Full custom illustration coverage of every screen -- only 2 illustrations in phase 1 (Auth hero, Home empty-state).
