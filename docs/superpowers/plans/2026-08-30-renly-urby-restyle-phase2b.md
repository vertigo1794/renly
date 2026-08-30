# Urby Restyle Phase 2B (Matching/Collaboration) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the 7 Matching/Collaboration screens with the neo-brutalist design system (`BrutalistButton`, `BrutalistCard`, Phosphor Bold icons), extending `BrutalistButton`'s API with a `fullWidth` toggle, an `icon` slot, and a `Semantics` accessibility fix that this phase's screens require.

**Architecture:** Task 1 extends the shared `BrutalistButton` widget (additive, backward-compatible) since every other task consumes it. Tasks 2-4 restyle the three structurally-mirrored Matching screens. Task 5 restyles the largest screen (`MyRequestsScreen`, 5 distinct button call sites). Tasks 6-7 restyle the two `AlertDialog`-based modals. Task 8 restyles `ChatScreen`'s inline send button.

**Tech Stack:** Flutter, Riverpod, `phosphor_flutter` (already a dependency since Phase 1), no new packages.

## Global Constraints

- `BrutalistButton`'s existing 17 call sites (Phase 1 + Phase 2A) must render byte-identical after this phase — both new params (`fullWidth`, `icon`) default to current behavior (`fullWidth: true`, `icon: null`).
- All icons use `PhosphorIcons.X(PhosphorIconsStyle.bold)` — never `Icons.*` Material icons — for functional/CTA icons. The star picker's UNSELECTED state is the one exception, using `PhosphorIconsStyle.regular`.
- No functional/business-logic change to any of the 7 screens.
- No global theme file (`app_theme.dart`/`app_colors.dart`) touched.
- `BrutalistCard` wrapped in `InkWell` — Material ripple loss is an accepted Phase 1 trade-off, not a defect to fix.
- `flutter analyze` and the full `flutter test` suite must stay clean throughout every task.
- No golden-image tests.
- `assets/illustrations/` is already declared as a directory in `app/pubspec.yaml`'s `flutter: assets:` section (confirmed this session) — new illustration files placed in that directory need no pubspec change.

---

### Task 1: Extend `BrutalistButton` with `fullWidth`, `icon`, and accessibility semantics

**Files:**
- Modify: `app/lib/core/widgets/brutalist_button.dart`
- Test: `app/test/core/widgets/brutalist_button_test.dart`

**Interfaces:**
- Produces: `BrutalistButton({required String label, required VoidCallback? onPressed, BrutalistButtonVariant variant = BrutalistButtonVariant.primary, bool fullWidth = true, IconData? icon, Key? key})` — every later task in this plan consumes this exact signature.

- [ ] **Step 1: Write the new failing tests**

Append these 3 tests to the existing `group('BrutalistButton', ...)` block in `app/test/core/widgets/brutalist_button_test.dart` (after the existing 5 tests, before the closing `});`):

```dart
    testWidgets('fullWidth:false sizes to content instead of double.infinity', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: BrutalistButton(label: 'Compact', onPressed: () {}, fullWidth: false),
        ),
      ));
      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, isNot(double.infinity));
      expect(sizedBox.width, isNull);
    });

    testWidgets('icon renders before the label when provided', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: BrutalistButton(label: 'Send', onPressed: () {}, icon: Icons.send),
      ));
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('exposes button semantics matching the enabled state', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: Column(children: [
          BrutalistButton(label: 'Enabled', onPressed: () {}),
          const BrutalistButton(label: 'Disabled', onPressed: null),
        ]),
      ));

      expect(
        tester.getSemantics(find.text('Enabled')),
        matchesSemantics(label: 'Enabled', isButton: true, isEnabled: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.text('Disabled')),
        matchesSemantics(label: 'Disabled', isButton: true, isEnabled: false),
      );
      handle.dispose();
    });
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `cd app && flutter test test/core/widgets/brutalist_button_test.dart`
Expected: the 3 new tests FAIL (`fullWidth`/`icon` are undefined named parameters; the semantics test fails because no `Semantics(button: true, ...)` node exists yet). The 5 existing tests still PASS.

- [ ] **Step 3: Implement the widget changes**

Replace the full contents of `app/lib/core/widgets/brutalist_button.dart` with:

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum BrutalistButtonVariant { primary, secondary }

/// A button matching this app's neo-brutalist visual identity
/// (docs/superpowers/specs/2026-08-25-renly-urby-restyle-design.md):
/// primary is lime-filled with a solid offset "hard shadow" and an ink
/// border; secondary is outline-only with no shadow, visually
/// lighter-weight for less prominent actions. Both use the same 56px-tall
/// touch target this app's auth buttons already established -- full-width
/// by default, or content-sized via `fullWidth: false` for side-by-side
/// pairs and compact inline placements.
class BrutalistButton extends StatelessWidget {
  const BrutalistButton({
    required this.label,
    required this.onPressed,
    this.variant = BrutalistButtonVariant.primary,
    this.fullWidth = true,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final BrutalistButtonVariant variant;
  final bool fullWidth;
  final IconData? icon;

  bool get _isPrimary => variant == BrutalistButtonVariant.primary;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final backgroundColor = _isPrimary ? AppColors.primary : Colors.transparent;
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.ink);

    return Semantics(
      button: true,
      enabled: isEnabled,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: SizedBox(
          width: fullWidth ? double.infinity : null,
          height: 56,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: fullWidth ? null : const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  border: Border.all(color: AppColors.ink, width: 2.5),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _isPrimary
                      ? const [BoxShadow(color: AppColors.ink, offset: Offset(4, 4), blurRadius: 0)]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: textStyle?.color, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(label, style: textStyle),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

The only rendering difference for every existing call site (`fullWidth: true` default, `icon: null` default): the `Text` is now wrapped in a `Row(mainAxisSize: MainAxisSize.min, children: [Text(...)])` instead of being a direct child. `mainAxisSize: MainAxisSize.min` makes the `Row` exactly as wide as the `Text`, and the surrounding `Container`'s `alignment: Alignment.center` centers it identically to before — this is a no-op visually.

- [ ] **Step 4: Run the full test file to verify all 8 tests pass**

Run: `cd app && flutter test test/core/widgets/brutalist_button_test.dart`
Expected: PASS (8/8 — the original 5 plus the 3 new ones).

- [ ] **Step 5: Run the full suite and analyze to confirm no regression on the 17 existing call sites**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues. (This is the empirical check that every Phase 1 and Phase 2A screen using `BrutalistButton` still renders and behaves identically.)

- [ ] **Step 6: Commit**

```bash
git add app/lib/core/widgets/brutalist_button.dart app/test/core/widgets/brutalist_button_test.dart
git commit -m "feat: add fullWidth/icon params and button semantics to BrutalistButton"
```

---

### Task 2: Restyle `MatchesForListingScreen`

**Files:**
- Modify: `app/lib/features/matching/matches_for_listing_screen.dart`
- Test: `app/test/features/matching/matches_for_listing_screen_test.dart` (verified this session: all 3 existing tests use `find.text(...)` only, no `find.byType(Card)`/`find.byType(ElevatedButton)` matcher — no test changes needed this task)

**Interfaces:**
- Consumes: `BrutalistButton({label, onPressed, variant, fullWidth, icon})` (Task 1), `BrutalistCard({required child, padding = EdgeInsets.all(16)})` (Phase 1, unchanged).

- [ ] **Step 1: Confirm no test matchers are at risk**

`app/test/features/matching/matches_for_listing_screen_test.dart` was read in full this session: all 3 tests (`renders score, budget range, area, and owner`, `tapping a match navigates...`, `renders empty state when no matches`) assert via `find.text(...)` only. No `Card`/`ElevatedButton` type matcher exists. No test file changes are needed in this task.

- [ ] **Step 2: Add imports**

In `app/lib/features/matching/matches_for_listing_screen.dart`, add:

```dart
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/brutalist_card.dart';
```

- [ ] **Step 3: Replace the card and button**

Replace:

```dart
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                  onTap: () => context.push('/requirement-board/${requirement.requirementId}'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${candidate.score}/100',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          RequirementFormatting.formatBudgetRange(
                            requirement.budgetMin,
                            requirement.budgetMax,
                            requirement.transactionType,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(requirement.area, style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 4),
                        Text(
                          '${candidate.requirementOwner.fullName} (REN: ${candidate.requirementOwner.renNumber})',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => sendCobrokeRequest(context, ref, candidate.matchId),
                          child: Text('cobroke_request_send'.tr()),
                        ),
                      ],
                    ),
                  ),
                ),
              );
```

with:

```dart
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.push('/requirement-board/${requirement.requirementId}'),
                    child: BrutalistCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${candidate.score}/100',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            RequirementFormatting.formatBudgetRange(
                              requirement.budgetMin,
                              requirement.budgetMax,
                              requirement.transactionType,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(requirement.area, style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 4),
                          Text(
                            '${candidate.requirementOwner.fullName} (REN: ${candidate.requirementOwner.renNumber})',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          const SizedBox(height: 8),
                          BrutalistButton(
                            label: 'cobroke_request_send'.tr(),
                            onPressed: () => sendCobrokeRequest(context, ref, candidate.matchId),
                            icon: PhosphorIcons.handshake(PhosphorIconsStyle.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
```

This is the same `Padding` > `Material` > `InkWell` > `BrutalistCard` wrapper pattern Phase 2A established for tappable cards (single `onTap` owner on the `InkWell`, `BrutalistCard`'s own default `EdgeInsets.all(16)` padding replaces the removed `Padding(padding: const EdgeInsets.all(16))`, avoiding double-padding).

- [ ] **Step 4: Add the empty-state illustration**

Replace:

```dart
          if (matches.isEmpty) {
            return Center(child: Text('matching_empty'.tr()));
          }
```

with:

```dart
          if (matches.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/illustrations/matching_empty.png',
                    height: 160,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 16),
                  Text('matching_empty'.tr()),
                ],
              ),
            );
          }
```

No `pubspec.yaml` change is needed — `assets/illustrations/` is already declared as a directory (confirmed this session), which covers any file placed inside it.

- [ ] **Step 5: Run tests and analyze**

Run: `cd app && flutter test test/features/matching/matches_for_listing_screen_test.dart && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/matching/matches_for_listing_screen.dart
git commit -m "feat: restyle MatchesForListingScreen with BrutalistCard and BrutalistButton"
```

---

### Task 3: Restyle `MatchesForRequirementScreen`

**Files:**
- Modify: `app/lib/features/matching/matches_for_requirement_screen.dart`
- Test: `app/test/features/matching/matches_for_requirement_screen_test.dart` (verified this session: no `Card`/`ElevatedButton` type matcher — no test changes needed)

**Interfaces:**
- Consumes: same as Task 2.

- [ ] **Step 1: Confirm no test matchers are at risk**

`app/test/features/matching/matches_for_requirement_screen_test.dart` was checked this session via `grep` for `ElevatedButton|Card|byIcon|OutlinedButton|TextButton` — zero matches. No test file changes are needed.

- [ ] **Step 2: Add imports**

In `app/lib/features/matching/matches_for_requirement_screen.dart`, add:

```dart
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/brutalist_card.dart';
```

- [ ] **Step 3: Replace the card and button**

Replace:

```dart
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                  onTap: () => context.push('/property/${listing.listingId}'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${candidate.score}/100',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink),
                        ),
                        const SizedBox(height: 4),
                        Text(ListingFormatting.formatPrice(listing.price, listing.transactionType)),
                        const SizedBox(height: 4),
                        Text(listing.area, style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 4),
                        Text(
                          '${candidate.listingOwner.fullName} (REN: ${candidate.listingOwner.renNumber})',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => sendCobrokeRequest(context, ref, candidate.matchId),
                          child: Text('cobroke_request_send'.tr()),
                        ),
                      ],
                    ),
                  ),
                ),
              );
```

with:

```dart
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.push('/property/${listing.listingId}'),
                    child: BrutalistCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${candidate.score}/100',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink),
                          ),
                          const SizedBox(height: 4),
                          Text(ListingFormatting.formatPrice(listing.price, listing.transactionType)),
                          const SizedBox(height: 4),
                          Text(listing.area, style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 4),
                          Text(
                            '${candidate.listingOwner.fullName} (REN: ${candidate.listingOwner.renNumber})',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          const SizedBox(height: 8),
                          BrutalistButton(
                            label: 'cobroke_request_send'.tr(),
                            onPressed: () => sendCobrokeRequest(context, ref, candidate.matchId),
                            icon: PhosphorIcons.handshake(PhosphorIconsStyle.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
```

- [ ] **Step 4: Add the empty-state illustration**

Replace:

```dart
          if (matches.isEmpty) {
            return Center(child: Text('matching_empty'.tr()));
          }
```

with:

```dart
          if (matches.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/illustrations/matching_empty.png',
                    height: 160,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 16),
                  Text('matching_empty'.tr()),
                ],
              ),
            );
          }
```

(Same `matching_empty.png` file as Task 2 — shared across all 3 Matching screens, not a new asset.)

- [ ] **Step 5: Run tests and analyze**

Run: `cd app && flutter test test/features/matching/matches_for_requirement_screen_test.dart && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/matching/matches_for_requirement_screen.dart
git commit -m "feat: restyle MatchesForRequirementScreen with BrutalistCard and BrutalistButton"
```

---

### Task 4: Restyle `MyMatchesScreen`

**Files:**
- Modify: `app/lib/features/matching/my_matches_screen.dart`
- Test: `app/test/features/matching/my_matches_screen_test.dart` (verified this session: no `Card`/`ElevatedButton` type matcher — no test changes needed)

**Interfaces:**
- Consumes: same as Task 2.

- [ ] **Step 1: Confirm no test matchers are at risk**

`app/test/features/matching/my_matches_screen_test.dart` was checked this session via `grep` for `ElevatedButton|Card|byIcon|OutlinedButton|TextButton` — zero matches. No test file changes are needed.

- [ ] **Step 2: Add imports**

In `app/lib/features/matching/my_matches_screen.dart`, add:

```dart
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/brutalist_card.dart';
```

- [ ] **Step 3: Replace the card and button**

Replace:

```dart
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                  onTap: () => isMyListing
                      ? context.push('/requirement-board/${candidate.requirement.requirementId}')
                      : context.push('/property/${candidate.listing.listingId}'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${candidate.score}/100',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink),
                        ),
                        const SizedBox(height: 4),
                        if (isMyListing) ...[
                          Text(
                            RequirementFormatting.formatBudgetRange(
                              candidate.requirement.budgetMin,
                              candidate.requirement.budgetMax,
                              candidate.requirement.transactionType,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(candidate.requirement.area, style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 4),
                          Text(
                            '${candidate.requirementOwner.fullName} (REN: ${candidate.requirementOwner.renNumber})',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ] else ...[
                          Text(ListingFormatting.formatPrice(candidate.listing.price, candidate.listing.transactionType)),
                          const SizedBox(height: 4),
                          Text(candidate.listing.area, style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 4),
                          Text(
                            '${candidate.listingOwner.fullName} (REN: ${candidate.listingOwner.renNumber})',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => sendCobrokeRequest(context, ref, candidate.matchId),
                          child: Text('cobroke_request_send'.tr()),
                        ),
                      ],
                    ),
                  ),
                ),
              );
```

with:

```dart
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => isMyListing
                        ? context.push('/requirement-board/${candidate.requirement.requirementId}')
                        : context.push('/property/${candidate.listing.listingId}'),
                    child: BrutalistCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${candidate.score}/100',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink),
                          ),
                          const SizedBox(height: 4),
                          if (isMyListing) ...[
                            Text(
                              RequirementFormatting.formatBudgetRange(
                                candidate.requirement.budgetMin,
                                candidate.requirement.budgetMax,
                                candidate.requirement.transactionType,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(candidate.requirement.area, style: Theme.of(context).textTheme.labelSmall),
                            const SizedBox(height: 4),
                            Text(
                              '${candidate.requirementOwner.fullName} (REN: ${candidate.requirementOwner.renNumber})',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ] else ...[
                            Text(ListingFormatting.formatPrice(candidate.listing.price, candidate.listing.transactionType)),
                            const SizedBox(height: 4),
                            Text(candidate.listing.area, style: Theme.of(context).textTheme.labelSmall),
                            const SizedBox(height: 4),
                            Text(
                              '${candidate.listingOwner.fullName} (REN: ${candidate.listingOwner.renNumber})',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                          const SizedBox(height: 8),
                          BrutalistButton(
                            label: 'cobroke_request_send'.tr(),
                            onPressed: () => sendCobrokeRequest(context, ref, candidate.matchId),
                            icon: PhosphorIcons.handshake(PhosphorIconsStyle.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
```

The `isMyListing` branch logic is preserved exactly — only the outer `Card`/`InkWell`/`Padding` wrapper and the trailing button change.

- [ ] **Step 4: Add the empty-state illustration**

Replace:

```dart
          if (matches.isEmpty) {
            return Center(child: Text('matching_empty'.tr()));
          }
```

with:

```dart
          if (matches.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/illustrations/matching_empty.png',
                    height: 160,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 16),
                  Text('matching_empty'.tr()),
                ],
              ),
            );
          }
```

- [ ] **Step 5: Run tests and analyze**

Run: `cd app && flutter test test/features/matching/my_matches_screen_test.dart && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/matching/my_matches_screen.dart
git commit -m "feat: restyle MyMatchesScreen with BrutalistCard and BrutalistButton"
```

---

### Task 5: Restyle `MyRequestsScreen`

**Files:**
- Modify: `app/lib/features/collaboration/my_requests_screen.dart`
- Test: `app/test/features/collaboration/my_requests_screen_test.dart` (verified this session, full 564-line file read: every assertion is `find.text(...)`-based, including the `Submit`/`Accept`/`Decline`/`Chat`/`Rate`/`Edit rating` buttons and the embedded `ProposeAgreementDialog` interaction test — no `ElevatedButton`/`OutlinedButton`/`Card` type matcher anywhere. No test file changes are needed this task.)

**Interfaces:**
- Consumes: `BrutalistButton` (Task 1), `BrutalistCard` (Phase 1).

This is the largest task: 1 card wrapper + 5 distinct button call sites across `_RequestList`, `_AgreementSection` (3 states), and `_RatingSection` (2 states).

- [ ] **Step 1: Confirm no test matchers are at risk**

Already verified above — no changes to `my_requests_screen_test.dart` needed.

- [ ] **Step 2: Add imports**

In `app/lib/features/collaboration/my_requests_screen.dart`, add:

```dart
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/brutalist_card.dart';
```

- [ ] **Step 3: Replace the card wrapper and add the empty-state illustration in `_RequestList`**

Replace:

```dart
        if (requests.isEmpty) {
          return Center(child: Text('cobroke_request_empty'.tr()));
        }
```

with:

```dart
        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/illustrations/cobroke_request_empty.png',
                  height: 160,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),
                Text('cobroke_request_empty'.tr()),
              ],
            ),
          );
        }
```

Replace:

```dart
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
```

with:

```dart
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: BrutalistCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
```

`Card(margin:, child: Padding(padding:, child: Column(...)))` and `Padding(padding:, child: BrutalistCard(child: Column(...)))` both wrap `Column` two levels deep — the closing braces after `Column`'s children list (`],),),);`) need no change, only these three opening lines shown above.

This card has no `onTap` (unlike Tasks 2-4's tappable match cards) — `MyRequestsScreen`'s rows are not navigable by tapping the card itself, only via their inner buttons, so no `InkWell`/`Material` wrapper is needed here, matching Phase 2A's `MyInventoryScreen`/`MyRequirementsScreen` precedent for non-tappable-card rows.

- [ ] **Step 4: Replace the Accept/Decline button pair**

Replace:

```dart
                        Row(
                          children: [
                            ElevatedButton(
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(cobrokeRequestRepositoryProvider)
                                      .acceptRequest(candidate.request.requestId);
                                  ref.invalidate(receivedRequestsProvider);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('listing_error_generic'.tr())),
                                    );
                                  }
                                }
                              },
                              child: Text('cobroke_request_accept'.tr()),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(cobrokeRequestRepositoryProvider)
                                      .declineRequest(candidate.request.requestId);
                                  ref.invalidate(receivedRequestsProvider);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('listing_error_generic'.tr())),
                                    );
                                  }
                                }
                              },
                              child: Text('cobroke_request_decline'.tr()),
                            ),
                          ],
                        ),
```

with:

```dart
                        Row(
                          children: [
                            BrutalistButton(
                              label: 'cobroke_request_accept'.tr(),
                              fullWidth: false,
                              icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(cobrokeRequestRepositoryProvider)
                                      .acceptRequest(candidate.request.requestId);
                                  ref.invalidate(receivedRequestsProvider);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('listing_error_generic'.tr())),
                                    );
                                  }
                                }
                              },
                            ),
                            const SizedBox(width: 12),
                            BrutalistButton(
                              label: 'cobroke_request_decline'.tr(),
                              variant: BrutalistButtonVariant.secondary,
                              fullWidth: false,
                              icon: PhosphorIcons.x(PhosphorIconsStyle.bold),
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(cobrokeRequestRepositoryProvider)
                                      .declineRequest(candidate.request.requestId);
                                  ref.invalidate(receivedRequestsProvider);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('listing_error_generic'.tr())),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
```

- [ ] **Step 5: Replace the Chat button**

Replace:

```dart
                        OutlinedButton(
                          onPressed: () => context.push('/messages/${candidate.request.requestId}'),
                          child: Text('cobroke_request_chat_button'.tr()),
                        ),
```

with:

```dart
                        BrutalistButton(
                          label: 'cobroke_request_chat_button'.tr(),
                          variant: BrutalistButtonVariant.secondary,
                          icon: PhosphorIcons.chatCircle(PhosphorIconsStyle.bold),
                          onPressed: () => context.push('/messages/${candidate.request.requestId}'),
                        ),
```

- [ ] **Step 6: Replace the Propose Agreement button**

Replace:

```dart
              OutlinedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => ProposeAgreementDialog(
                    requestId: requestId,
                    initiatorId: currentNegotiatorId!,
                  ),
                ),
                child: Text('agreement_propose_button'.tr()),
              ),
```

with:

```dart
              BrutalistButton(
                label: 'agreement_propose_button'.tr(),
                variant: BrutalistButtonVariant.secondary,
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => ProposeAgreementDialog(
                    requestId: requestId,
                    initiatorId: currentNegotiatorId!,
                  ),
                ),
              ),
```

- [ ] **Step 7: Replace the Agreement Accept/Decline button pair**

Replace:

```dart
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        await ref.read(agreementRepositoryProvider).acceptAgreement(agreement.agreementId);
                        ref.invalidate(agreementForRequestProvider(requestId));
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('listing_error_generic'.tr())),
                          );
                        }
                      }
                    },
                    child: Text('agreement_accept'.tr()),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () async {
                      try {
                        await ref.read(agreementRepositoryProvider).declineAgreement(agreement.agreementId);
                        ref.invalidate(agreementForRequestProvider(requestId));
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('listing_error_generic'.tr())),
                          );
                        }
                      }
                    },
                    child: Text('agreement_decline'.tr()),
                  ),
                ],
              ),
```

with:

```dart
              Row(
                children: [
                  BrutalistButton(
                    label: 'agreement_accept'.tr(),
                    fullWidth: false,
                    icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
                    onPressed: () async {
                      try {
                        await ref.read(agreementRepositoryProvider).acceptAgreement(agreement.agreementId);
                        ref.invalidate(agreementForRequestProvider(requestId));
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('listing_error_generic'.tr())),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  BrutalistButton(
                    label: 'agreement_decline'.tr(),
                    variant: BrutalistButtonVariant.secondary,
                    fullWidth: false,
                    icon: PhosphorIcons.x(PhosphorIconsStyle.bold),
                    onPressed: () async {
                      try {
                        await ref.read(agreementRepositoryProvider).declineAgreement(agreement.agreementId);
                        ref.invalidate(agreementForRequestProvider(requestId));
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('listing_error_generic'.tr())),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
```

- [ ] **Step 8: Replace both Rate/Edit-rating button call sites in `_RatingSection`**

Replace:

```dart
        if (rating == null) {
          return OutlinedButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RateDialog(agreementId: agreementId, raterId: raterId, ratedId: ratedId),
            ),
            child: Text('rating_rate_button'.tr()),
          );
        }

        final withinEditWindow = DateTime.now().difference(rating.createdAt) < const Duration(hours: 24);
        if (withinEditWindow) {
          return OutlinedButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RateDialog(
                agreementId: agreementId,
                raterId: raterId,
                ratedId: ratedId,
                existingRating: rating,
              ),
            ),
            child: Text('rating_edit_button'.tr()),
          );
        }
```

with:

```dart
        if (rating == null) {
          return BrutalistButton(
            label: 'rating_rate_button'.tr(),
            variant: BrutalistButtonVariant.secondary,
            icon: PhosphorIcons.star(PhosphorIconsStyle.bold),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RateDialog(agreementId: agreementId, raterId: raterId, ratedId: ratedId),
            ),
          );
        }

        final withinEditWindow = DateTime.now().difference(rating.createdAt) < const Duration(hours: 24);
        if (withinEditWindow) {
          return BrutalistButton(
            label: 'rating_edit_button'.tr(),
            variant: BrutalistButtonVariant.secondary,
            icon: PhosphorIcons.star(PhosphorIconsStyle.bold),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => RateDialog(
                agreementId: agreementId,
                raterId: raterId,
                ratedId: ratedId,
                existingRating: rating,
              ),
            ),
          );
        }
```

- [ ] **Step 9: Confirm the error-state Retry `TextButton` is untouched**

`_AgreementSection`'s error branch (`TextButton(onPressed: () => ref.invalidate(...), child: Text('agreement_retry'.tr()))`) is out of scope per the design doc — verify after Steps 3-8 that this block still reads exactly as it did before editing, with no accidental change.

- [ ] **Step 10: Run tests and analyze**

Run: `cd app && flutter test test/features/collaboration/my_requests_screen_test.dart && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 11: Commit**

```bash
git add app/lib/features/collaboration/my_requests_screen.dart
git commit -m "feat: restyle MyRequestsScreen with BrutalistCard and BrutalistButton"
```

---

### Task 6: Restyle `ProposeAgreementDialog`

**Files:**
- Modify: `app/lib/features/collaboration/propose_agreement_dialog.dart`
- Test: `app/test/features/collaboration/propose_agreement_dialog_test.dart` — **confirmed this session: this file does not exist.** `ProposeAgreementDialog` is exercised only indirectly, inside `my_requests_screen_test.dart`'s `propose dialog validates that shares sum to 100` test (already confirmed text-based, no changes needed).

**Interfaces:**
- Consumes: `BrutalistButton` (Task 1).

- [ ] **Step 1: Add imports**

In `app/lib/features/collaboration/propose_agreement_dialog.dart`, add:

```dart
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';
```

- [ ] **Step 2: Replace the dialog actions**

Replace:

```dart
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('agreement_cancel'.tr()),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: Text('agreement_submit'.tr()),
        ),
      ],
```

with:

```dart
      actions: [
        BrutalistButton(
          label: 'agreement_cancel'.tr(),
          variant: BrutalistButtonVariant.secondary,
          fullWidth: false,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        BrutalistButton(
          label: 'agreement_submit'.tr(),
          fullWidth: false,
          icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
          onPressed: _submitting ? null : _submit,
        ),
      ],
```

`AlertDialog.actions` lays out its children in a right-aligned `Row` automatically — no manual wrapper needed.

- [ ] **Step 3: Run tests and analyze**

Run: `cd app && flutter test test/features/collaboration/my_requests_screen_test.dart && flutter analyze`
Expected: All PASS, no analyzer issues. (`my_requests_screen_test.dart` is the only test exercising this dialog, per Step 1's finding above — its `Submit` button is still found via `find.text('Submit')`, which still matches since `BrutalistButton` renders `Text(label)` internally.)

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/collaboration/propose_agreement_dialog.dart
git commit -m "feat: restyle ProposeAgreementDialog with BrutalistButton"
```

---

### Task 7: Restyle `RateDialog` with a new star picker

**Files:**
- Modify: `app/lib/features/ratings/rate_dialog.dart`
- Test: `app/test/features/ratings/rate_dialog_test.dart` — **confirmed this session: this file does not exist.** No existing widget test exercises this dialog directly.

**Interfaces:**
- Consumes: `BrutalistButton` (Task 1).
- Produces: a private `_BrutalistStar` widget local to this file (no other file references it).

- [ ] **Step 1: Add imports**

In `app/lib/features/ratings/rate_dialog.dart`, add:

```dart
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';
```

- [ ] **Step 2: Replace the star picker row**

Replace:

```dart
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starValue = index + 1;
              return IconButton(
                icon: Icon(starValue <= _stars ? Icons.star : Icons.star_border),
                onPressed: _submitting ? null : () => setState(() => _stars = starValue),
              );
            }),
          ),
```

with:

```dart
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starValue = index + 1;
              return _BrutalistStar(
                selected: starValue <= _stars,
                onTap: _submitting ? null : () => setState(() => _stars = starValue),
              );
            }),
          ),
```

- [ ] **Step 3: Add the `_BrutalistStar` widget**

Add this class at the end of `rate_dialog.dart`, after the closing brace of `_RateDialogState`:

```dart
class _BrutalistStar extends StatelessWidget {
  const _BrutalistStar({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          PhosphorIcons.star(selected ? PhosphorIconsStyle.bold : PhosphorIconsStyle.regular),
          color: AppColors.ink,
          size: 32,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Replace the dialog actions**

Replace:

```dart
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('rating_cancel'.tr()),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: Text('rating_submit'.tr()),
        ),
      ],
```

with:

```dart
      actions: [
        BrutalistButton(
          label: 'rating_cancel'.tr(),
          variant: BrutalistButtonVariant.secondary,
          fullWidth: false,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        BrutalistButton(
          label: 'rating_submit'.tr(),
          fullWidth: false,
          icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
          onPressed: _submitting ? null : _submit,
        ),
      ],
```

- [ ] **Step 5: Write a new test for `_BrutalistStar`'s selected/unselected icon**

`_BrutalistStar` is private, so it cannot be imported and tested standalone from a separate test file — verify it indirectly through `RateDialog`'s own public surface. Create `app/test/features/ratings/rate_dialog_test.dart`:

```dart
// app/test/features/ratings/rate_dialog_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/ratings/rate_dialog.dart';

Widget _wrap({required Widget child}) {
  return ProviderScope(
    child: EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ms')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: Builder(
        builder: (context) => MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    rootBundle.clear();
  });

  testWidgets('defaults to 5 filled stars, tapping the 2nd star selects only the first 2', (tester) async {
    await tester.pumpWidget(_wrap(
      child: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const RateDialog(agreementId: 'agr-1', raterId: 'n-1', ratedId: 'n-2'),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.bold)),
      findsNWidgets(5),
    );

    await tester.tap(find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.bold)).at(1));
    await tester.pumpAndSettle();

    expect(find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.bold)), findsNWidgets(2));
    expect(find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.regular)), findsNWidgets(3));
  });
}
```

- [ ] **Step 6: Run the new test to verify it passes**

Run: `cd app && flutter test test/features/ratings/rate_dialog_test.dart`
Expected: PASS.

- [ ] **Step 7: Run the full suite and analyze**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/ratings/rate_dialog.dart app/test/features/ratings/rate_dialog_test.dart
git commit -m "feat: restyle RateDialog with BrutalistButton and a Phosphor star picker"
```

---

### Task 8: Restyle `ChatScreen`'s send button

**Files:**
- Modify: `app/lib/features/collaboration/chat_screen.dart`
- Test: `app/test/features/collaboration/chat_screen_test.dart` (verified this session: all 3 tests use `find.text(...)`/`find.widgetWithText(TextField, ...)` — no `ElevatedButton` type matcher — no test changes needed)

**Interfaces:**
- Consumes: `BrutalistButton` (Task 1).

- [ ] **Step 1: Confirm no test matchers are at risk**

`app/test/features/collaboration/chat_screen_test.dart` was read in full this session: the `send button is present with input hint` test asserts `find.text('Send')` and `find.widgetWithText(TextField, 'Type a message...')` — no widget-type matcher on the button. No test file changes are needed.

- [ ] **Step 2: Add imports**

In `app/lib/features/collaboration/chat_screen.dart`, add:

```dart
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';
```

- [ ] **Step 3: Replace the send button**

Replace:

```dart
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _sending
                          ? null
                          : () => _send(currentNegotiatorId),
                      child: Text('message_send'.tr()),
                    ),
```

with:

```dart
                    const SizedBox(width: 8),
                    BrutalistButton(
                      label: 'message_send'.tr(),
                      fullWidth: false,
                      icon: PhosphorIcons.paperPlaneRight(PhosphorIconsStyle.bold),
                      onPressed: _sending
                          ? null
                          : () => _send(currentNegotiatorId),
                    ),
```

- [ ] **Step 4: Run tests and analyze**

Run: `cd app && flutter test test/features/collaboration/chat_screen_test.dart && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/collaboration/chat_screen.dart
git commit -m "feat: restyle ChatScreen send button with BrutalistButton"
```

---

## After this plan

Sub-phase 2C (Profile/Settings/Subscription) is a separate future design cycle. Real illustration artwork for the 9 empty-state slots now reserved app-wide (2 Phase 1 + 4 Phase 2A + 3 this phase — `matching_empty.png`, `cobroke_request_empty.png`) still needs to be produced/sourced separately.
