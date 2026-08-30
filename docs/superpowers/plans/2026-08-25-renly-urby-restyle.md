# Urby-Inspired Visual Restyle (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace renly's unused Lumina Prime design system with a new neo-brutalist visual identity (lime/black/white/purple, hard shadows, bold outlines, Space Grotesk typography) across the shared theme and 3 flagship screens (AuthSelectionScreen, LoginScreen, HomePlaceholderScreen).

**Architecture:** A palette/typography rewrite in the existing `app_colors.dart`/`app_theme.dart` source-of-truth files (value changes only, no field renames, so all ~20 untouched screens keep compiling and inherit the new base colors automatically), plus two new reusable widgets (`BrutalistButton`, `BrutalistCard`) that carry the signature hard-shadow effect Flutter's theme system can't express on its own, adopted explicitly in the 3 phase-1 screens.

**Tech Stack:** Flutter/Dart, `google_fonts` (already a dependency, adds Space Grotesk), `phosphor_flutter` (new dependency, Bold-weight functional icons).

## Global Constraints

- No `AppColors` field may be renamed or removed -- 10 files elsewhere in `app/lib` reference its fields directly; only values change, and only for fields this phase's design doc calls for (`primary`, `background`, `surface`) plus two new additive fields (`ink`, `accent`).
- Hard shadow spec, exact: `BoxShadow(color: AppColors.ink, offset: Offset(4, 4), blurRadius: 0)`.
- `BrutalistButton` must preserve the existing 56px-tall full-width touch target convention already used by `AuthSelectionScreen`'s buttons, and must support `onPressed: null` as its disabled state (existing call sites like `LoginScreen` rely on this).
- No golden-image/screenshot tests. `flutter analyze` and `flutter test` must stay clean after every task. Manual visual check is the acceptance bar beyond that.
- Illustration assets (`auth_hero.png`, `home_hero.png`) are out of scope to actually produce in these tasks -- wire the code path (`Image.asset` call + `pubspec.yaml` asset declaration) so it's ready to receive real artwork, but do not invent placeholder "art" and do not block the rest of the plan on final artwork existing.

---

### Task 1: Palette and theme rewrite

**Files:**
- Modify: `app/lib/core/theme/app_colors.dart`
- Modify: `app/lib/core/theme/app_theme.dart`

**Interfaces:**
- Produces: `AppColors.ink` (`Color(0xFF0A0A0A)`), `AppColors.accent` (`Color(0xFF7C3AED)`) -- new constants Tasks 2-6 consume. `AppColors.primary` now `0xFFD2FF00`; `AppColors.background`/`AppColors.surface` now `0xFFFFFFFF`. `AppTheme.light`'s `elevatedButtonTheme`/`cardTheme` now carry an ink border and 12px radius -- Tasks 4-6 rely on this being the new baseline for any plain `ElevatedButton`/`Card` they don't explicitly swap to the Brutalist widgets.

- [ ] **Step 1: No test-first step**

This task changes constant values and `ThemeData` construction -- there's no unit-testable behavior here beyond "the app still compiles and renders," which the existing widget test suite already exercises indirectly (screens that render text/buttons through this theme). Modify directly.

- [ ] **Step 2: Update `app_colors.dart`**

Change these 3 existing lines:
```dart
  static const Color primary = Color(0xFFD2FF00);
```
```dart
  static const Color background = Color(0xFFFFFFFF);
  static const Color onBackground = Color(0xFF191C1B);
  static const Color surface = Color(0xFFFFFFFF);
```
(Only the `primary`, `background`, and `surface` hex values change -- `onPrimary`, `onBackground`, `onSurface`, and every other existing field stay exactly as they are today.)

Add 2 new constants at the end of the class, right before the closing `}`:
```dart

  // Urby-inspired neo-brutalist tokens (2026-08-25-renly-urby-restyle-design.md).
  static const Color ink = Color(0xFF0A0A0A);
  static const Color accent = Color(0xFF7C3AED);
```

- [ ] **Step 3: Update `app_theme.dart`'s text theme**

Replace the entire `baseTextTheme` definition with:
```dart
    final baseTextTheme = TextTheme(
      headlineLarge: GoogleFonts.spaceGrotesk(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        height: 40 / 32,
        letterSpacing: -0.01 * 32,
        color: AppColors.onBackground,
      ),
      titleMedium: GoogleFonts.spaceGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 28 / 20,
        color: AppColors.onBackground,
      ),
      bodyLarge: GoogleFonts.spaceGrotesk(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        height: 26 / 18,
        color: AppColors.onBackground,
      ),
      bodyMedium: GoogleFonts.spaceGrotesk(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 24 / 16,
        color: AppColors.onBackground,
      ),
      labelSmall: GoogleFonts.spaceGrotesk(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 16 / 12,
        letterSpacing: 0.05 * 12,
        color: AppColors.onSurface,
      ),
      labelLarge: GoogleFonts.spaceGrotesk(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 20 / 16,
      ),
    );
```

- [ ] **Step 4: Update `app_theme.dart`'s button and card themes**

Replace the `elevatedButtonTheme` block with:
```dart
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppColors.ink, width: 2.5),
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: baseTextTheme.labelLarge,
        ),
      ),
```

Replace the `cardTheme` block with:
```dart
      cardTheme: CardThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.ink, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
```

Leave `inputDecorationTheme` exactly as it is -- out of scope for this phase.

- [ ] **Step 5: Update the file header comment**

Replace:
```dart
/// Theme ported from stitch_renly_property_agent_network/lumina_prime/DESIGN.md.
/// Typography: Syne (headlines), Hanken Grotesk (body), JetBrains Mono (data labels).
/// Shape: 8px standard elements, 16px containers, 24px feature elements.
```
with:
```dart
/// Urby-inspired neo-brutalist theme (docs/superpowers/specs/2026-08-25-renly-urby-restyle-design.md),
/// replacing the never-implemented Lumina Prime system.
/// Typography: Space Grotesk throughout (headings 700-800, body 500-600).
/// Shape: 12px radius, 2-2.5px ink borders on buttons/cards.
```

- [ ] **Step 6: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues. Some existing widget tests may assert on exact color/font values used by these 2 files -- if any fail, read the failure, confirm it's asserting the OLD Lumina Prime value (not some unrelated behavior), and update that specific assertion to the new value. Do not change any test whose failure isn't traceable to this task's value changes.

- [ ] **Step 7: Commit**

```bash
git add app/lib/core/theme/app_colors.dart app/lib/core/theme/app_theme.dart
git commit -m "feat: rewrite theme palette and typography for Urby-inspired restyle"
```

---

### Task 2: `BrutalistButton` widget

**Files:**
- Create: `app/lib/core/widgets/brutalist_button.dart`
- Test: `app/test/core/widgets/brutalist_button_test.dart`

**Interfaces:**
- Consumes: `AppColors.primary`/`AppColors.ink` (Task 1).
- Produces: `BrutalistButton({required String label, required VoidCallback? onPressed, BrutalistButtonVariant variant = BrutalistButtonVariant.primary})`, `enum BrutalistButtonVariant { primary, secondary }`. Tasks 4-6 consume this exact constructor shape.

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/core/widgets/brutalist_button_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/widgets/brutalist_button.dart';

void main() {
  group('BrutalistButton', () {
    testWidgets('renders the given label', (tester) async {
      await tester.pumpWidget(MaterialApp(home: BrutalistButton(label: 'Tap me', onPressed: () {})));
      expect(find.text('Tap me'), findsOneWidget);
    });

    testWidgets('primary variant applies a hard shadow', (tester) async {
      await tester.pumpWidget(MaterialApp(home: BrutalistButton(label: 'Primary', onPressed: () {})));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.boxShadow, isNotNull);
      expect(decoration.boxShadow!.single.blurRadius, 0);
      expect(decoration.boxShadow!.single.offset, const Offset(4, 4));
    });

    testWidgets('secondary variant has no shadow and a transparent fill', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: BrutalistButton(label: 'Secondary', onPressed: () {}, variant: BrutalistButtonVariant.secondary),
      ));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.boxShadow, isNull);
      expect(decoration.color, Colors.transparent);
    });

    testWidgets('calls onPressed when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(home: BrutalistButton(label: 'Tap', onPressed: () => tapped = true)));
      await tester.tap(find.byType(BrutalistButton));
      expect(tapped, isTrue);
    });

    testWidgets('renders without error when onPressed is null (disabled)', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BrutalistButton(label: 'Disabled', onPressed: null)));
      expect(find.text('Disabled'), findsOneWidget);
      await tester.tap(find.byType(BrutalistButton));
      // No exception thrown, no state to assert -- InkWell(onTap: null) is
      // Flutter's own disabled-tap contract, not reimplemented here.
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/core/widgets/brutalist_button_test.dart`
Expected: FAIL -- `package:renly/core/widgets/brutalist_button.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// app/lib/core/widgets/brutalist_button.dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum BrutalistButtonVariant { primary, secondary }

/// A button matching this app's neo-brutalist visual identity
/// (docs/superpowers/specs/2026-08-25-renly-urby-restyle-design.md):
/// primary is lime-filled with a solid offset "hard shadow" and an ink
/// border; secondary is outline-only with no shadow, visually
/// lighter-weight for less prominent actions. Both use the same 56px-tall
/// full-width touch target this app's auth buttons already established.
class BrutalistButton extends StatelessWidget {
  const BrutalistButton({
    required this.label,
    required this.onPressed,
    this.variant = BrutalistButtonVariant.primary,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final BrutalistButtonVariant variant;

  bool get _isPrimary => variant == BrutalistButtonVariant.primary;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final backgroundColor = _isPrimary ? AppColors.primary : Colors.transparent;
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.ink);

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.5,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: backgroundColor,
                border: Border.all(color: AppColors.ink, width: 2.5),
                borderRadius: BorderRadius.circular(12),
                boxShadow: _isPrimary
                    ? const [BoxShadow(color: AppColors.ink, offset: Offset(4, 4), blurRadius: 0)]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(label, style: textStyle),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/core/widgets/brutalist_button_test.dart`
Expected: All 5 PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/widgets/brutalist_button.dart app/test/core/widgets/brutalist_button_test.dart
git commit -m "feat: add BrutalistButton widget"
```

---

### Task 3: `BrutalistCard` widget

**Files:**
- Create: `app/lib/core/widgets/brutalist_card.dart`
- Test: `app/test/core/widgets/brutalist_card_test.dart`

**Interfaces:**
- Consumes: `AppColors.surface`/`AppColors.ink` (Task 1).
- Produces: `BrutalistCard({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(16)})`. No phase-1 screen adopts this yet (none currently has a card to restyle) -- built now, standalone-tested, as the reusable primitive future phases adopt, per the design doc's component-pattern section.

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/core/widgets/brutalist_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/widgets/brutalist_card.dart';

void main() {
  group('BrutalistCard', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BrutalistCard(child: Text('Inside'))));
      expect(find.text('Inside'), findsOneWidget);
    });

    testWidgets('applies a hard shadow decoration', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BrutalistCard(child: Text('x'))));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.boxShadow, isNotNull);
      expect(decoration.boxShadow!.single.blurRadius, 0);
      expect(decoration.boxShadow!.single.offset, const Offset(4, 4));
    });

    testWidgets('uses 16px default padding', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BrutalistCard(child: Text('x'))));
      final container = tester.widget<Container>(find.byType(Container));
      expect(container.padding, const EdgeInsets.all(16));
    });

    testWidgets('accepts a custom padding override', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: BrutalistCard(padding: EdgeInsets.all(8), child: Text('x')),
      ));
      final container = tester.widget<Container>(find.byType(Container));
      expect(container.padding, const EdgeInsets.all(8));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/core/widgets/brutalist_card_test.dart`
Expected: FAIL -- file doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// app/lib/core/widgets/brutalist_card.dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A card matching this app's neo-brutalist visual identity -- white
/// fill, an ink border, and the same hard-shadow effect BrutalistButton's
/// primary variant uses. See
/// docs/superpowers/specs/2026-08-25-renly-urby-restyle-design.md.
class BrutalistCard extends StatelessWidget {
  const BrutalistCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.ink, width: 2),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(4, 4), blurRadius: 0)],
      ),
      child: child,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/core/widgets/brutalist_card_test.dart`
Expected: All 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/widgets/brutalist_card.dart app/test/core/widgets/brutalist_card_test.dart
git commit -m "feat: add BrutalistCard widget"
```

---

### Task 4: Restyle `AuthSelectionScreen`

**Files:**
- Modify: `app/lib/features/auth/auth_selection_screen.dart`
- Modify: `app/pubspec.yaml`
- Test: `app/test/features/auth/auth_selection_screen_test.dart` (if it exists -- search first, see Step 1)

**Interfaces:**
- Consumes: `BrutalistButton`/`BrutalistButtonVariant` (Task 2), `AppColors.surface`/`AppColors.ink` (Task 1).

- [ ] **Step 1: Check for an existing test file and its button-matching style**

Run: `find app/test -iname "*auth_selection*"`

If a file exists, read it and identify any assertion that finds a widget by TYPE (`find.byType(ElevatedButton)`, `find.byType(OutlinedButton)`) rather than by text/key -- those will break once this task swaps both buttons to `BrutalistButton`. Note the exact lines; you'll fix them in Step 5.

- [ ] **Step 2: Replace the screen's body**

Replace the entire file content with:
```dart
// app/lib/features/auth/auth_selection_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/brutalist_button.dart';

/// Ports stitch_renly_property_agent_network/login_register_selection_english_official_style,
/// restyled per docs/superpowers/specs/2026-08-25-renly-urby-restyle-design.md.
class AuthSelectionScreen extends StatelessWidget {
  const AuthSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'app_name'.tr(),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: 12),
              Text(
                'auth_tagline'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.ink),
              ),
              const SizedBox(height: 32),
              Image.asset('assets/illustrations/auth_hero.png', height: 200),
              const SizedBox(height: 32),
              BrutalistButton(
                label: 'auth_create_account'.tr(),
                onPressed: () => context.push('/register/personal'),
              ),
              const SizedBox(height: 12),
              BrutalistButton(
                label: 'auth_log_in'.tr(),
                onPressed: () => context.push('/login'),
                variant: BrutalistButtonVariant.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Declare the illustrations asset directory**

In `app/pubspec.yaml`, change:
```yaml
  assets:
    - assets/translations/
    - .env
```
to:
```yaml
  assets:
    - assets/translations/
    - assets/illustrations/
    - .env
```

- [ ] **Step 4: Create the illustrations directory placeholder**

The actual `auth_hero.png` artwork is NOT produced by this task (see this plan's Global Constraints -- no image-generation tool confirmed available this session). Create the directory so the asset declaration and `Image.asset` call don't reference a nonexistent path structure:

```bash
mkdir -p app/assets/illustrations
touch app/assets/illustrations/.gitkeep
```

Do not add a placeholder image file. `Image.asset('assets/illustrations/auth_hero.png', ...)` will render Flutter's built-in "broken image" icon at runtime until real artwork is dropped in at `app/assets/illustrations/auth_hero.png` -- this is expected and correct for this task; it is not a bug to fix here.

- [ ] **Step 5: Fix any broken widget-type test matchers found in Step 1**

If Step 1 found a test file with `find.byType(ElevatedButton)`/`find.byType(OutlinedButton)` assertions targeting these 2 buttons, change them to match by text instead, e.g.:
```dart
// Before: expect(find.byType(ElevatedButton), findsOneWidget);
// After:
expect(find.widgetWithText(BrutalistButton, 'auth_create_account'.tr()), findsOneWidget);
```
Apply the equivalent substitution for every such assertion found, preserving what each test is actually verifying (that the button exists and is tappable) rather than which underlying widget type renders it.

If no such test file exists, skip this step -- do not create one (this phase's testing approach is manual visual verification for screen-level appearance; only the new shared widgets get dedicated unit tests, per this plan's Task 2/3).

- [ ] **Step 6: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/auth/auth_selection_screen.dart app/pubspec.yaml app/assets/illustrations/.gitkeep
# Also add any test file modified in Step 5
git commit -m "feat: restyle AuthSelectionScreen with BrutalistButton"
```

---

### Task 5: Restyle `LoginScreen`

**Files:**
- Modify: `app/lib/features/auth/login_screen.dart`
- Test: `app/test/features/auth/login_screen_test.dart` (if it exists -- search first, see Step 1)

**Interfaces:**
- Consumes: `BrutalistButton` (Task 2).

- [ ] **Step 1: Check for an existing test file and its button-matching style**

Run: `find app/test -iname "*login_screen*"`

If a file exists, read it and identify any `find.byType(ElevatedButton)` assertion targeting the submit button -- it will break once this task swaps it to `BrutalistButton`. Note the exact lines; fix in Step 3.

- [ ] **Step 2: Swap the submit button**

In `app/lib/features/auth/login_screen.dart`, add the import:
```dart
import '../../core/widgets/brutalist_button.dart';
```

Replace:
```dart
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text('auth_log_in'.tr()),
                ),
```
with:
```dart
                BrutalistButton(
                  label: 'auth_log_in'.tr(),
                  onPressed: _submitting ? null : _submit,
                ),
```

Nothing else in this file changes -- the form fields, the `TextButton`, and all logic in `_submit` stay exactly as they are.

- [ ] **Step 3: Fix any broken widget-type test matchers found in Step 1**

Same substitution pattern as Task 4 Step 5: replace `find.byType(ElevatedButton)` with a text-based match against `BrutalistButton`, e.g. `find.widgetWithText(BrutalistButton, 'auth_log_in'.tr())`. If the existing test taps the button via `find.byKey`/`find.text`/`find.byType(Form)` rather than `find.byType(ElevatedButton)` directly, no change is needed -- verify by reading the actual assertion, don't assume.

If no such test file exists, skip this step.

- [ ] **Step 4: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/auth/login_screen.dart
# Also add any test file modified in Step 3
git commit -m "feat: restyle LoginScreen submit button with BrutalistButton"
```

---

### Task 6: Restyle `HomePlaceholderScreen`

**Files:**
- Modify: `app/lib/features/auth/home_placeholder_screen.dart`
- Modify: `app/pubspec.yaml`
- Test: `app/test/features/auth/home_placeholder_screen_test.dart` (if it exists -- search first, see Step 1)

**Interfaces:**
- Consumes: `BrutalistButton`/`BrutalistButtonVariant` (Task 2).

- [ ] **Step 1: Check for an existing test file and its matcher style**

Run: `find app/test -iname "*home_placeholder*"`

If a file exists, read it. Note any `find.byIcon(Icons.person)` assertion (breaks once the AppBar icon becomes a Phosphor icon) and any `find.byType(ElevatedButton)`/`find.byType(OutlinedButton)` assertion targeting the 6 navigation buttons (breaks once they become `BrutalistButton`). Fix both classes in Step 5.

- [ ] **Step 2: Add the `phosphor_flutter` dependency**

```bash
cd app && flutter pub add phosphor_flutter
```

- [ ] **Step 3: Declare the illustrations asset directory (if Task 4 hasn't already)**

If Task 4 already ran, `app/pubspec.yaml`'s `assets:` list already includes `assets/illustrations/` and `app/assets/illustrations/` already exists -- skip this step. Otherwise, repeat Task 4's Step 3 and Step 4 exactly (add the `assets/illustrations/` line, create the directory with a `.gitkeep`).

- [ ] **Step 4: Replace the screen's body**

Replace the entire file content with:
```dart
// app/lib/features/auth/home_placeholder_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';

class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(PhosphorIcons.user(PhosphorIconsStyle.bold)),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('home_placeholder_title'.tr(), style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 12),
                Text('home_placeholder_body'.tr(), style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 24),
                Image.asset('assets/illustrations/home_hero.png', height: 160),
                const SizedBox(height: 24),
                BrutalistButton(
                  label: 'marketplace_title_placeholder_link'.tr(),
                  onPressed: () => context.push('/marketplace'),
                ),
                const SizedBox(height: 12),
                BrutalistButton(
                  label: 'inventory_title_placeholder_link'.tr(),
                  onPressed: () => context.push('/my-inventory'),
                  variant: BrutalistButtonVariant.secondary,
                ),
                const SizedBox(height: 12),
                BrutalistButton(
                  label: 'requirement_board_title_placeholder_link'.tr(),
                  onPressed: () => context.push('/requirement-board'),
                ),
                const SizedBox(height: 12),
                BrutalistButton(
                  label: 'my_requirements_title_placeholder_link'.tr(),
                  onPressed: () => context.push('/my-requirements'),
                  variant: BrutalistButtonVariant.secondary,
                ),
                const SizedBox(height: 12),
                BrutalistButton(
                  label: 'matching_my_matches_link'.tr(),
                  onPressed: () => context.push('/my-matches'),
                  variant: BrutalistButtonVariant.secondary,
                ),
                const SizedBox(height: 12),
                BrutalistButton(
                  label: 'cobroke_request_my_requests_link'.tr(),
                  onPressed: () => context.push('/my-requests'),
                  variant: BrutalistButtonVariant.secondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

(Button-to-variant mapping preserves the original file's primary/secondary roles exactly: Marketplace and Requirement Board were `ElevatedButton` -> primary; My Inventory, My Requirements, My Matches, My Requests were `OutlinedButton` -> secondary.)

- [ ] **Step 5: Fix any broken widget-type/icon test matchers found in Step 1**

For a broken `find.byIcon(Icons.person)`, replace with `find.byIcon(PhosphorIcons.user(PhosphorIconsStyle.bold))` or, if the test only needs to confirm the profile button exists and is tappable, `find.byType(IconButton)` (there's only one in this screen).

For broken `find.byType(ElevatedButton)`/`find.byType(OutlinedButton)` assertions against the 6 nav buttons, replace with `find.widgetWithText(BrutalistButton, '<the exact tr() string used>')`, matching the label text each assertion was originally targeting.

If no such test file exists, skip this step.

- [ ] **Step 6: Run the full suite**

Run: `cd app && flutter test && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/auth/home_placeholder_screen.dart app/pubspec.yaml app/pubspec.lock
# Also add app/assets/illustrations/.gitkeep if Task 4 hasn't already, and any test file modified in Step 5
git commit -m "feat: restyle HomePlaceholderScreen with BrutalistButton and Phosphor icons"
```

---

## After this plan

Real illustration artwork (`auth_hero.png`, `home_hero.png`) still needs to be generated or sourced and dropped into `app/assets/illustrations/` -- not part of this plan's completion criteria (see Global Constraints). The remaining ~17 screens' restyle is future-phase work, reusing `BrutalistButton`/`BrutalistCard` established here.
