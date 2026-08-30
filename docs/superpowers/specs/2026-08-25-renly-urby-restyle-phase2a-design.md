# renly — Urby-Inspired Visual Restyle, Phase 2A (Listing/Requirement) Design

## Goal

Restyle the 8 Listing/Requirement screens with the neo-brutalist design system Phase 1 established (`BrutalistButton`, `BrutalistCard`, the lime/black/white/purple palette, Space Grotesk typography). No functionality, data model, or business logic changes — visual restyle only, same as Phase 1.

## Scope

This is Sub-phase 2A of the Urby Restyle's Phase 2 rollout (the remaining ~17 screens beyond Phase 1's 3 flagship screens), decomposed by feature area. 2A covers exactly these 8 screens: `MarketplaceScreen`, `MyInventoryScreen`, `PostListingScreen`, `PropertyDetailScreen`, `RequirementBoardScreen`, `MyRequirementsScreen`, `PostRequirementScreen`, `RequirementDetailScreen`. Sub-phases 2B (Matching/Collaboration) and 2C (Profile/Settings/Subscription) are separate, not-yet-brainstormed future design cycles.

## Card treatment

4 of these 8 screens (`MarketplaceScreen`, `MyInventoryScreen`, `RequirementBoardScreen`, `MyRequirementsScreen`) currently use plain `Card()`, which Phase 1's global `cardTheme` already gives an ink border + 12px radius but NOT a hard shadow. All 4 switch to explicit `BrutalistCard` (Phase 1's widget, unused by any real screen until now), gaining the full hard-shadow treatment and resolving Phase 1's "two different card looks" inconsistency for this sub-phase's screens. (The remaining ~6 screens elsewhere in the app that still use plain `Card()` are out of this sub-phase's scope — 2B/2C will address those.)

## Status badge (first real use of `AppColors.accent`)

A new small reusable widget, `StatusBadge`, displays a listing's status (`active`/`sold`/`withdrawn`) or a requirement's status (`open`/`fulfilled`/`withdrawn`) as a compact pill using `AppColors.accent` (purple, `#7C3AED`) — the first real use case for this color since Phase 1 introduced it unused. Appears on every card in the 4 list screens (Marketplace, My Inventory, Requirement Board, My Requirements) and in the header of both detail screens (Property Detail, Requirement Detail).

## Buttons

Every CTA across all 8 screens (Post, Mark Sold/Fulfilled, Withdraw, Reactivate, form submit, etc.) becomes `BrutalistButton`, using the existing primary/secondary variant split (main action per screen = primary, secondary/destructive-adjacent actions = secondary) — no new variant needed. `BrutalistButton` stays text-only for this sub-phase; an icon slot is explicitly deferred (see below), since none of these 8 screens' buttons need one.

## Illustration

The 4 list screens' empty states (no active listings/requirements yet) get an illustration slot wired the same way Phase 1 did for its 2 slots: an `Image.asset(...)` call with an `errorBuilder` fallback to empty space, declared in `pubspec.yaml`'s existing `assets/illustrations/` directory. No actual artwork is produced by this sub-phase (no image-generation tool is available this session either) — this is code-path wiring only, ready to receive real art whenever it exists.

## Testing approach

Same boundary as Phase 1: `flutter analyze` and the full `flutter test` suite must stay clean throughout. Each of the 8 screens' existing widget tests (if any) must be checked for `find.byType`/`find.byIcon` matchers that would silently break once buttons/cards swap to the Brutalist widgets — this was a real, repeated risk in Phase 1's own execution and is expected to recur here. No golden-image tests, consistent with this project's established convention.

## Explicitly deferred / out of scope

- `BrutalistButton`'s icon-slot and full-width-toggle gaps (both real, both confirmed in Phase 1's final review) — deferred to Sub-phase 2B, which actually needs them (icon+label buttons likely in Chat/Matching screens, side-by-side Cancel/Confirm pairs in the 2 collaboration dialogs).
- Sub-phases 2B and 2C entirely — separate future design cycles.
- Real illustration artwork for the empty-state slots this sub-phase wires.
- Any functional/business-logic change to any of the 8 screens.
