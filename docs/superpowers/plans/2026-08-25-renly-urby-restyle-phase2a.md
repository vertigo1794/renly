# Urby-Inspired Visual Restyle, Phase 2A (Listing/Requirement) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the 8 Listing/Requirement screens with Phase 1's neo-brutalist design system (`BrutalistButton`, `BrutalistCard`, palette, typography) and add a new `StatusBadge` widget (first real use of `AppColors.accent`).

**Architecture:** A new standalone `StatusBadge` widget, then 8 screen-restyle tasks that swap plain `Card()`/`ElevatedButton`/`OutlinedButton` for their Brutalist equivalents and place `StatusBadge` on the 2 detail screens only.

**Tech Stack:** Flutter/Dart, reuses Phase 1's `BrutalistButton`/`BrutalistCard`/`AppColors`/`AppTheme` (no new dependencies).

## Global Constraints

- No functionality, data model, business logic, or navigation change on any of the 8 screens -- restyle only.
- `StatusBadge` appears ONLY on `PropertyDetailScreen`/`RequirementDetailScreen` -- NOT on the 4 list screens' cards (each list screen shows only one status per view already, via RLS scoping or tab filtering, so a per-card badge would be redundant).
- The "Add Photo" buttons in `PostListingScreen`/`PostRequirementScreen` (icon+label stacked in a `Column`, not a horizontal text CTA) are OUT OF SCOPE for the `BrutalistButton` swap -- structurally incompatible with `BrutalistButton`'s fixed full-width/text-only/56px shape. Leave them as plain `OutlinedButton`.
- `BrutalistCard` wrapped in `InkWell` for tappable list items loses the Material ripple animation on tap (a known Flutter limitation: `InkWell`'s splash paints under an opaque `Container`'s own decoration, since `BrutalistCard` uses `Container` not `Ink`). Tap still fully works (`onTap` fires normally); only the visual ripple feedback is absent. This is an accepted, documented trade-off for this phase, not a bug to fix.
- No golden-image tests. `flutter analyze` + `flutter test` must stay clean after every task. Each task's own Step 1 must search for and read that screen's existing test file (all 8 screens have one) before touching it -- `find.byType`/`find.byIcon` matchers are a real, repeated risk (per Phase 1's own execution history).
- Illustration assets for the 4 new empty-state slots are code-path-only, no real art (no image-generation tool available this session) -- same `errorBuilder` fallback pattern Phase 1 established.
- Reuse existing l10n keys for status labels (`inventory_tab_active`/`inventory_tab_sold`/`inventory_tab_withdrawn`/`requirement_tab_open`/`requirement_tab_fulfilled`, already used by the tab `SegmentedButton`s) -- do not add new translation keys for `StatusBadge`'s label text.

---

### Task 1: `StatusBadge` widget

**Files:**
- Create: `app/lib/core/widgets/status_badge.dart`
- Test: `app/test/core/widgets/status_badge_test.dart`

**Interfaces:**
- Consumes: `AppColors.accent`/`AppColors.ink` (Phase 1).
- Produces: `StatusBadge({required String label})`. Tasks 8-9 consume this exact constructor shape.

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/core/widgets/status_badge_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/theme/app_colors.dart';
import 'package:renly/core/widgets/status_badge.dart';

void main() {
  group('StatusBadge', () {
    testWidgets('renders the given label', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: StatusBadge(label: 'Active')));
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('uses the brand accent color as its fill', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: StatusBadge(label: 'Sold')));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.accent);
    });

    testWidgets('has an ink border', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: StatusBadge(label: 'Withdrawn')));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/core/widgets/status_badge_test.dart`
Expected: FAIL -- file doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// app/lib/core/widgets/status_badge.dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A small pill showing a listing's or requirement's current status --
/// see docs/superpowers/specs/2026-08-25-renly-urby-restyle-phase2a-design.md.
/// Takes the already-localized label directly rather than a raw status
/// string, so it stays domain-agnostic (works for both listing and
/// requirement status vocabularies without knowing either).
class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent,
        border: Border.all(color: AppColors.ink, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/core/widgets/status_badge_test.dart`
Expected: All 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/widgets/status_badge.dart app/test/core/widgets/status_badge_test.dart
git commit -m "feat: add StatusBadge widget"
```

---

### Task 2: Restyle `MarketplaceScreen`

**Files:**
- Modify: `app/lib/features/listing/marketplace_screen.dart`
- Modify: `app/pubspec.yaml`
- Test: `app/test/features/listing/marketplace_screen_test.dart`

**Interfaces:**
- Consumes: `BrutalistCard` (Phase 1).

- [ ] **Step 1: Read the existing test file**

Read `app/test/features/listing/marketplace_screen_test.dart` in full. Note any `find.byType(Card)` assertion (will break once `Card` becomes `BrutalistCard`) or any assertion tied to the exact widget tree structure around the list-item card (e.g. `find.byType(InkWell)` at a specific position) -- fix in Step 4.

- [ ] **Step 2: Add the empty-state illustration asset declaration**

In `app/pubspec.yaml`, the `assets:` list already includes `assets/illustrations/` (added in Phase 1) -- no change needed here. Confirm this by reading the file; if it's somehow missing, add it back exactly as Phase 1 did:
```yaml
  assets:
    - assets/translations/
    - assets/illustrations/
    - .env
```

- [ ] **Step 3: Replace the list-item card and empty state**

In `app/lib/features/listing/marketplace_screen.dart`, add the import:
```dart
import '../../core/widgets/brutalist_card.dart';
```

Replace the empty-state branch:
```dart
                if (filtered.isEmpty) {
                  return Center(child: Text('marketplace_empty'.tr()));
                }
```
with:
```dart
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/illustrations/marketplace_empty.png',
                          height: 160,
                          errorBuilder: (context, error, stackTrace) => const SizedBox(height: 160),
                        ),
                        const SizedBox(height: 16),
                        Text('marketplace_empty'.tr()),
                      ],
                    ),
                  );
                }
```

Replace the `itemBuilder`'s returned `Card(...)` (the whole block from `return Card(` through its matching closing `);`) with:
```dart
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => context.push('/property/${listing.listingId}'),
                            borderRadius: BorderRadius.circular(12),
                            child: BrutalistCard(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (listing.photoUrls.isNotEmpty) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 72,
                                        height: 72,
                                        child: ListingPhoto(path: listing.photoUrls.first),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(listing.title,
                                            style: Theme.of(context).textTheme.titleMedium),
                                        const SizedBox(height: 4),
                                        Text(
                                          ListingFormatting.formatPrice(
                                              listing.price, listing.transactionType),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(color: AppColors.ink),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            if (listing.bedrooms != null) ...[
                                              const Icon(Icons.bed, size: 16),
                                              const SizedBox(width: 4),
                                              Text('${listing.bedrooms}'),
                                              const SizedBox(width: 12),
                                            ],
                                            if (listing.bathrooms != null) ...[
                                              const Icon(Icons.bathtub, size: 16),
                                              const SizedBox(width: 4),
                                              Text('${listing.bathrooms}'),
                                              const SizedBox(width: 12),
                                            ],
                                            Flexible(
                                              child: Text(
                                                listing.area,
                                                style: Theme.of(context).textTheme.labelSmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
```

(Note: `BrutalistCard`'s own default `padding: EdgeInsets.all(16)` replaces the original's manual inner `Padding(padding: const EdgeInsets.all(16), ...)` -- do not add a second Padding layer inside `BrutalistCard`'s child.)

- [ ] **Step 4: Fix any broken test matchers found in Step 1**

If Step 1 found a `find.byType(Card)` assertion, change it to `find.byType(BrutalistCard)`. If it found a tap-target assertion via `find.byType(InkWell)`, verify it still resolves correctly (there is still exactly one `InkWell` per list item, just now wrapping `BrutalistCard` instead of the old inner `Padding`) -- adjust only if it genuinely breaks, don't change a passing assertion speculatively.

- [ ] **Step 5: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/listing/marketplace_screen.dart app/pubspec.yaml
# Also add the test file if modified in Step 4
git commit -m "feat: restyle MarketplaceScreen with BrutalistCard"
```

---

### Task 3: Restyle `MyInventoryScreen`

**Files:**
- Modify: `app/lib/features/listing/my_inventory_screen.dart`
- Test: `app/test/features/listing/my_inventory_screen_test.dart`

**Interfaces:**
- Consumes: `BrutalistCard`, `BrutalistButton` (Phase 1).

- [ ] **Step 1: Read the existing test file**

Read `app/test/features/listing/my_inventory_screen_test.dart` in full. Note any `find.byType(Card)`/`find.byType(ElevatedButton)` assertion -- fix in Step 3.

- [ ] **Step 2: Replace the list-item card, empty state, and post-new button**

In `app/lib/features/listing/my_inventory_screen.dart`, add the imports:
```dart
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/brutalist_card.dart';
```

Replace the empty-state branch:
```dart
                          if (filtered.isEmpty) {
                            return Center(child: Text('inventory_empty'.tr()));
                          }
```
with:
```dart
                          if (filtered.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/illustrations/my_inventory_empty.png',
                                    height: 160,
                                    errorBuilder: (context, error, stackTrace) => const SizedBox(height: 160),
                                  ),
                                  const SizedBox(height: 16),
                                  Text('inventory_empty'.tr()),
                                ],
                              ),
                            );
                          }
```

Replace the `itemBuilder`'s returned `Card(...)` block with:
```dart
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => context.push('/property/${listing.listingId}'),
                                      borderRadius: BorderRadius.circular(12),
                                      child: BrutalistCard(
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(listing.title),
                                          subtitle: Text(
                                            ListingFormatting.formatPrice(
                                                listing.price, listing.transactionType),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
```

(The `ListTile` loses its own `onTap` -- the outer `InkWell` now owns the tap, same navigation target. `contentPadding: EdgeInsets.zero` avoids double-padding since `BrutalistCard` already pads its child by 16px.)

Replace:
```dart
            child: ElevatedButton(
              onPressed: () => context.push('/post-listing'),
              child: Text('inventory_post_new'.tr()),
            ),
```
with:
```dart
            child: BrutalistButton(
              label: 'inventory_post_new'.tr(),
              onPressed: () => context.push('/post-listing'),
            ),
```

- [ ] **Step 3: Fix any broken test matchers found in Step 1**

Same substitution pattern as Task 2 for `Card`. For the post-new button, replace `find.byType(ElevatedButton)` with `find.widgetWithText(BrutalistButton, 'inventory_post_new'.tr())` if such an assertion exists.

- [ ] **Step 4: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/listing/my_inventory_screen.dart
# Also add the test file if modified in Step 3
git commit -m "feat: restyle MyInventoryScreen with BrutalistCard and BrutalistButton"
```

---

### Task 4: Restyle `RequirementBoardScreen`

**Files:**
- Modify: `app/lib/features/requirement/requirement_board_screen.dart`
- Test: `app/test/features/requirement/requirement_board_screen_test.dart`

**Interfaces:**
- Consumes: `BrutalistCard` (Phase 1).

- [ ] **Step 1: Read the existing test file**

Read `app/test/features/requirement/requirement_board_screen_test.dart` in full. Note any `find.byType(Card)` assertion -- fix in Step 3.

- [ ] **Step 2: Replace the list-item card and empty state**

In `app/lib/features/requirement/requirement_board_screen.dart`, add the import:
```dart
import '../../core/widgets/brutalist_card.dart';
```

Replace the empty-state branch:
```dart
                if (filtered.isEmpty) {
                  return Center(child: Text('requirement_board_empty'.tr()));
                }
```
with:
```dart
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/illustrations/requirement_board_empty.png',
                          height: 160,
                          errorBuilder: (context, error, stackTrace) => const SizedBox(height: 160),
                        ),
                        const SizedBox(height: 16),
                        Text('requirement_board_empty'.tr()),
                      ],
                    ),
                  );
                }
```

Replace the `itemBuilder`'s returned `Card(...)` block with:
```dart
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => context.push('/requirement-board/${requirement.requirementId}'),
                            borderRadius: BorderRadius.circular(12),
                            child: BrutalistCard(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (requirement.photoUrls.isNotEmpty) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 72,
                                        height: 72,
                                        child: SignedPhoto(
                                          path: requirement.photoUrls.first,
                                          signedUrlFetcher: ref.read(requirementRepositoryProvider).createSignedUrl,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          RequirementFormatting.formatBudgetRange(
                                            requirement.budgetMin,
                                            requirement.budgetMax,
                                            requirement.transactionType,
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(color: AppColors.ink),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${'listing_property_type_${requirement.propertyType}'.tr()} · '
                                          '${'listing_transaction_type_${requirement.transactionType}'.tr()}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            if (requirement.bedrooms != null) ...[
                                              const Icon(Icons.bed, size: 16),
                                              const SizedBox(width: 4),
                                              Text('${requirement.bedrooms}'),
                                              const SizedBox(width: 12),
                                            ],
                                            Flexible(
                                              child: Text(
                                                requirement.area,
                                                style: Theme.of(context).textTheme.labelSmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Builder(builder: (context) {
                                          final ownerAsync =
                                              ref.watch(requirementOwnerProvider(requirement.negotiatorId));
                                          return ownerAsync.when(
                                            loading: () => const SizedBox.shrink(),
                                            error: (error, stack) => const SizedBox.shrink(),
                                            data: (owner) => Text(
                                              '${owner.fullName} (REN: ${owner.renNumber})',
                                              style: Theme.of(context).textTheme.labelSmall,
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
```

- [ ] **Step 3: Fix any broken test matchers found in Step 1**

Same substitution pattern as Task 2.

- [ ] **Step 4: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/requirement/requirement_board_screen.dart
# Also add the test file if modified in Step 3
git commit -m "feat: restyle RequirementBoardScreen with BrutalistCard"
```

---

### Task 5: Restyle `MyRequirementsScreen`

**Files:**
- Modify: `app/lib/features/requirement/my_requirements_screen.dart`
- Test: `app/test/features/requirement/my_requirements_screen_test.dart`

**Interfaces:**
- Consumes: `BrutalistCard`, `BrutalistButton` (Phase 1).

- [ ] **Step 1: Read the existing test file**

Read `app/test/features/requirement/my_requirements_screen_test.dart` in full. Note any `find.byType(Card)`/`find.byType(ElevatedButton)` assertion -- fix in Step 3.

- [ ] **Step 2: Replace the list-item card, empty state, and post-new button**

In `app/lib/features/requirement/my_requirements_screen.dart`, add the imports:
```dart
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/brutalist_card.dart';
```

Replace the empty-state branch:
```dart
                          if (filtered.isEmpty) {
                            return Center(child: Text('requirement_my_empty'.tr()));
                          }
```
with:
```dart
                          if (filtered.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/illustrations/my_requirements_empty.png',
                                    height: 160,
                                    errorBuilder: (context, error, stackTrace) => const SizedBox(height: 160),
                                  ),
                                  const SizedBox(height: 16),
                                  Text('requirement_my_empty'.tr()),
                                ],
                              ),
                            );
                          }
```

Replace the `itemBuilder`'s returned `Card(...)` block with:
```dart
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => context.push('/requirement-board/${requirement.requirementId}'),
                                      borderRadius: BorderRadius.circular(12),
                                      child: BrutalistCard(
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(
                                            RequirementFormatting.formatBudgetRange(
                                              requirement.budgetMin,
                                              requirement.budgetMax,
                                              requirement.transactionType,
                                            ),
                                          ),
                                          subtitle: Text('${requirement.area}, ${requirement.state}'),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
```

Replace:
```dart
            child: ElevatedButton(
              onPressed: () => context.push('/post-requirement'),
              child: Text('requirement_post_new'.tr()),
            ),
```
with:
```dart
            child: BrutalistButton(
              label: 'requirement_post_new'.tr(),
              onPressed: () => context.push('/post-requirement'),
            ),
```

- [ ] **Step 3: Fix any broken test matchers found in Step 1**

Same substitution pattern as Task 3.

- [ ] **Step 4: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/requirement/my_requirements_screen.dart
# Also add the test file if modified in Step 3
git commit -m "feat: restyle MyRequirementsScreen with BrutalistCard and BrutalistButton"
```

---

### Task 6: Restyle `PostListingScreen`

**Files:**
- Modify: `app/lib/features/listing/post_listing_screen.dart`
- Test: `app/test/features/listing/post_listing_screen_test.dart`

**Interfaces:**
- Consumes: `BrutalistButton` (Phase 1).

- [ ] **Step 1: Read the existing test file**

Read `app/test/features/listing/post_listing_screen_test.dart` in full. Note any `find.byType(ElevatedButton)` assertion targeting the submit button (NOT the "Add Photo" `OutlinedButton`, which stays untouched per this plan's Global Constraints) -- fix in Step 3.

- [ ] **Step 2: Swap the submit button only**

In `app/lib/features/listing/post_listing_screen.dart`, add the import:
```dart
import '../../core/widgets/brutalist_button.dart';
```

Replace:
```dart
                ElevatedButton(
                  onPressed: (_submitting || atCap) ? null : _submit,
                  child: Text('listing_post_now'.tr()),
                ),
```
with:
```dart
                BrutalistButton(
                  label: 'listing_post_now'.tr(),
                  onPressed: (_submitting || atCap) ? null : _submit,
                ),
```

Do NOT touch the "Add Photo" `OutlinedButton` (its icon+`Column` child shape is incompatible with `BrutalistButton` -- see this plan's Global Constraints) or any other part of the file.

- [ ] **Step 3: Fix any broken test matchers found in Step 1**

Replace `find.byType(ElevatedButton)` (if targeting the submit button specifically) with `find.widgetWithText(BrutalistButton, 'listing_post_now'.tr())`.

- [ ] **Step 4: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/listing/post_listing_screen.dart
# Also add the test file if modified in Step 3
git commit -m "feat: restyle PostListingScreen submit button with BrutalistButton"
```

---

### Task 7: Restyle `PostRequirementScreen`

**Files:**
- Modify: `app/lib/features/requirement/post_requirement_screen.dart`
- Test: `app/test/features/requirement/post_requirement_screen_test.dart`

**Interfaces:**
- Consumes: `BrutalistButton` (Phase 1).

- [ ] **Step 1: Read the existing test file**

Read `app/test/features/requirement/post_requirement_screen_test.dart` in full. Note any `find.byType(ElevatedButton)` assertion targeting the submit button -- fix in Step 3.

- [ ] **Step 2: Swap the submit button only**

In `app/lib/features/requirement/post_requirement_screen.dart`, add the import:
```dart
import '../../core/widgets/brutalist_button.dart';
```

Replace:
```dart
                ElevatedButton(
                  onPressed: (_submitting || atCap) ? null : _submit,
                  child: Text('requirement_post_now'.tr()),
                ),
```
with:
```dart
                BrutalistButton(
                  label: 'requirement_post_now'.tr(),
                  onPressed: (_submitting || atCap) ? null : _submit,
                ),
```

Do NOT touch the "Add Photo" `OutlinedButton` or any other part of the file.

- [ ] **Step 3: Fix any broken test matchers found in Step 1**

Replace `find.byType(ElevatedButton)` (if targeting the submit button) with `find.widgetWithText(BrutalistButton, 'requirement_post_now'.tr())`.

- [ ] **Step 4: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/requirement/post_requirement_screen.dart
# Also add the test file if modified in Step 3
git commit -m "feat: restyle PostRequirementScreen submit button with BrutalistButton"
```

---

### Task 8: Restyle `PropertyDetailScreen`

**Files:**
- Modify: `app/lib/features/listing/property_detail_screen.dart`
- Test: `app/test/features/listing/property_detail_screen_test.dart`

**Interfaces:**
- Consumes: `BrutalistButton`, `BrutalistButtonVariant`, `StatusBadge` (Task 1).

- [ ] **Step 1: Read the existing test file**

Read `app/test/features/listing/property_detail_screen_test.dart` in full. Note any `find.byType(OutlinedButton)` assertion (there are 4 possible buttons: View Matches, Mark Sold, Withdraw, Reactivate) -- fix in Step 3.

- [ ] **Step 2: Add StatusBadge and swap all 4 OutlinedButtons**

In `app/lib/features/listing/property_detail_screen.dart`, add the imports:
```dart
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/status_badge.dart';
```

Add a private helper method to `_PropertyDetailScreenState` (place it near the existing `_changeStatus` method):
```dart
  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'inventory_tab_active'.tr();
      case 'sold':
        return 'inventory_tab_sold'.tr();
      default:
        return 'inventory_tab_withdrawn'.tr();
    }
  }
```

Insert the badge right after the title, before the price line:
```dart
                  Text(listing.title, style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  StatusBadge(label: _statusLabel(listing.status)),
                  const SizedBox(height: 8),
                  Text(
                    ListingFormatting.formatPrice(listing.price, listing.transactionType),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
```

Replace the 4 conditional `OutlinedButton`s (the whole `if (isOwner) ...[` block's button contents) with:
```dart
                  if (isOwner) ...[
                    BrutalistButton(
                      label: 'matching_view_matches'.tr(),
                      onPressed: () => context.push('/property/${widget.listingId}/matches'),
                      variant: BrutalistButtonVariant.secondary,
                    ),
                    const SizedBox(height: 8),
                    if (listing.status != 'sold') ...[
                      BrutalistButton(
                        label: 'property_mark_sold'.tr(),
                        onPressed: () => _changeStatus(listing, 'sold'),
                        variant: BrutalistButtonVariant.secondary,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (listing.status != 'withdrawn') ...[
                      BrutalistButton(
                        label: 'property_withdraw'.tr(),
                        onPressed: () => _changeStatus(listing, 'withdrawn'),
                        variant: BrutalistButtonVariant.secondary,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (listing.status != 'active') ...[
                      if (atCap) ...[
                        Text(
                          'listing_cap_reached_message'.tr(),
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                        const SizedBox(height: 8),
                      ],
                      BrutalistButton(
                        label: 'property_reactivate'.tr(),
                        onPressed: atCap ? null : () => _changeStatus(listing, 'active'),
                        variant: BrutalistButtonVariant.secondary,
                      ),
                    ],
                  ],
```

(This adds a `SizedBox(height: 8)` after each conditionally-rendered button so multiple visible buttons in a row get consistent spacing -- the original only had spacing after the first, unconditional "View Matches" button, leaving no gap when e.g. both "Mark Sold" and "Withdraw" render together. This is a small, in-scope visual fix, not a functional change.)

- [ ] **Step 3: Fix any broken test matchers found in Step 1**

Replace any `find.byType(OutlinedButton)` assertion with `find.widgetWithText(BrutalistButton, '<the exact label text that assertion targets>')`.

- [ ] **Step 4: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/listing/property_detail_screen.dart
# Also add the test file if modified in Step 3
git commit -m "feat: restyle PropertyDetailScreen with BrutalistButton and StatusBadge"
```

---

### Task 9: Restyle `RequirementDetailScreen`

**Files:**
- Modify: `app/lib/features/requirement/requirement_detail_screen.dart`
- Test: `app/test/features/requirement/requirement_detail_screen_test.dart`

**Interfaces:**
- Consumes: `BrutalistButton`, `BrutalistButtonVariant`, `StatusBadge` (Task 1).

- [ ] **Step 1: Read the existing test file**

Read `app/test/features/requirement/requirement_detail_screen_test.dart` in full. Note any `find.byType(OutlinedButton)` assertion -- fix in Step 3.

- [ ] **Step 2: Add StatusBadge and swap all 4 OutlinedButtons**

In `app/lib/features/requirement/requirement_detail_screen.dart`, add the imports:
```dart
import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/status_badge.dart';
```

Add a private helper method to `_RequirementDetailScreenState`:
```dart
  String _statusLabel(String status) {
    switch (status) {
      case 'open':
        return 'requirement_tab_open'.tr();
      case 'fulfilled':
        return 'requirement_tab_fulfilled'.tr();
      default:
        return 'inventory_tab_withdrawn'.tr();
    }
  }
```

Insert the badge right after the budget-range headline text (this screen's equivalent of a "title"), before the property/transaction-type line:
```dart
                  Text(
                    RequirementFormatting.formatBudgetRange(
                      requirement.budgetMin,
                      requirement.budgetMax,
                      requirement.transactionType,
                    ),
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  StatusBadge(label: _statusLabel(requirement.status)),
                  const SizedBox(height: 8),
                  Text(
                    '${'listing_property_type_${requirement.propertyType}'.tr()} · '
                    '${'listing_transaction_type_${requirement.transactionType}'.tr()}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
```

Replace the 4 conditional `OutlinedButton`s with:
```dart
                  if (isOwner) ...[
                    BrutalistButton(
                      label: 'matching_view_matches'.tr(),
                      onPressed: () => context.push('/requirement-board/${widget.requirementId}/matches'),
                      variant: BrutalistButtonVariant.secondary,
                    ),
                    const SizedBox(height: 8),
                    if (requirement.status != 'fulfilled') ...[
                      BrutalistButton(
                        label: 'requirement_mark_fulfilled'.tr(),
                        onPressed: () => _changeStatus(requirement, 'fulfilled'),
                        variant: BrutalistButtonVariant.secondary,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (requirement.status != 'withdrawn') ...[
                      BrutalistButton(
                        label: 'requirement_withdraw'.tr(),
                        onPressed: () => _changeStatus(requirement, 'withdrawn'),
                        variant: BrutalistButtonVariant.secondary,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (requirement.status != 'open') ...[
                      if (atCap) ...[
                        Text(
                          'requirement_cap_reached_message'.tr(),
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                        const SizedBox(height: 8),
                      ],
                      BrutalistButton(
                        label: 'requirement_reactivate'.tr(),
                        onPressed: atCap ? null : () => _changeStatus(requirement, 'open'),
                        variant: BrutalistButtonVariant.secondary,
                      ),
                    ],
                  ],
```

(Same added-spacing rationale as Task 8.)

- [ ] **Step 3: Fix any broken test matchers found in Step 1**

Same substitution pattern as Task 8.

- [ ] **Step 4: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/requirement/requirement_detail_screen.dart
# Also add the test file if modified in Step 3
git commit -m "feat: restyle RequirementDetailScreen with BrutalistButton and StatusBadge"
```

---

## After this plan

Sub-phases 2B (Matching/Collaboration) and 2C (Profile/Settings/Subscription) are separate future design cycles. Real illustration artwork for the 4 new empty-state slots this plan wires (`marketplace_empty.png`, `my_inventory_empty.png`, `requirement_board_empty.png`, `my_requirements_empty.png`) still needs to be produced/sourced separately.
