# renly Flutter Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a working Flutter project for renly — scaffolded, themed from the Lumina Prime design system, localized (Bahasa Melayu + English), and wired to Supabase — as a running app a first-time Flutter developer can `flutter run` and see themed, localized output on a device.

**Architecture:** Flutter project lives in `app/` inside the existing `RENLY` repo root (kept separate from `docs/` and `stitch_renly_property_agent_network/`). State management is Riverpod (`ProviderScope` at the root). Design tokens are ported once into `lib/core/theme/` and consumed everywhere else — no screen should hardcode a color or font. Localization strings live in flat JSON files loaded by `easy_localization`; every UI string added later must go through `tr()`, never a literal.

**Tech Stack:** Flutter (stable channel, installed at `~/development/flutter`), Dart, `flutter_riverpod`, `supabase_flutter`, `easy_localization`, `google_fonts`, `go_router`, `flutter_dotenv`.

## Global Constraints

- Flutter SDK is installed at `~/development/flutter/bin` but is **not on PATH** in the current shell — every `flutter`/`dart` command in this plan must either use the full path or PATH must be fixed first (Task 1, Step 1).
- Android is the target platform for this pass; iOS is same-codebase but untested (per design doc — out of scope here).
- State management: Riverpod only. Do not introduce Bloc, GetX, or Provider-without-Riverpod.
- Design tokens must come from `stitch_renly_property_agent_network/lumina_prime/DESIGN.md` — no invented colors/fonts.
- Localization: `easy_localization`, JSON string tables, two locales — `en` and `ms`. Every key must exist in both files (structural parity enforced by test).
- Supabase credentials are secrets: they live in `app/.env` (git-ignored, already covered by the repo's `.gitignore`), never hardcoded, never committed. `app/.env.example` documents the required keys with placeholder values.
- No table/RLS/screen work in this plan — that starts in the next plan (auth + verification module per the design doc's build order). This plan stops once the app boots themed and localized with a Supabase client instance ready to use.

---

### Task 1: Verify toolchain and scaffold the Flutter project

**Files:**
- Create: `app/` (entire `flutter create` output — `lib/`, `test/`, `android/`, `ios/`, `pubspec.yaml`, etc.)

**Interfaces:**
- Produces: a Flutter project at `app/` with package name `renly`, default `app/lib/main.dart`, default `app/test/widget_test.dart` — later tasks modify these.

- [ ] **Step 1: Fix PATH for this shell**

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter --version
```
Expected: prints `Flutter 3.41.3 • channel stable ...` (no "command not found").

If this needs to persist across sessions, append to `~/.zshrc`:
```bash
echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.zshrc
```

- [ ] **Step 2: Run flutter doctor**

```bash
flutter doctor
```
Expected: Android toolchain shows a checkmark or a specific fixable issue (e.g. missing Android licenses — run `flutter doctor --android-licenses` if so). Do not proceed to Step 3 with a red ✗ on Android toolchain.

- [ ] **Step 3: Scaffold the project**

Run from `RENLY` repo root:
```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
flutter create --org com.renly --project-name renly app
```
Expected: `app/` directory created with standard Flutter project structure, ending output line `All done!`.

- [ ] **Step 4: Verify the default scaffold test passes**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test
```
Expected: `00:0X +1: All tests passed!` (the stock counter-app widget test).

- [ ] **Step 5: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/
git commit -m "feat: scaffold renly Flutter project"
```

---

### Task 2: Add project dependencies

**Files:**
- Modify: `app/pubspec.yaml`

**Interfaces:**
- Produces: `flutter_riverpod`, `supabase_flutter`, `easy_localization`, `google_fonts`, `go_router`, `flutter_dotenv` available as imports for every later task.

- [ ] **Step 1: Edit `app/pubspec.yaml` dependencies section**

Find the `dependencies:` block (contains `flutter:` and `cupertino_icons:`) and add:

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_riverpod: ^2.6.1
  supabase_flutter: ^2.8.0
  easy_localization: ^3.0.7
  google_fonts: ^6.2.1
  go_router: ^14.6.2
  flutter_dotenv: ^5.2.1
```

- [ ] **Step 2: Fetch packages**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter pub get
```
Expected: `Got dependencies!` with no version-resolution errors. If a version conflict appears, remove the caret pin on the conflicting package (use `flutter pub add <package>` instead to let pub pick a compatible version).

- [ ] **Step 3: Verify no analyzer errors**

```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/pubspec.yaml app/pubspec.lock
git commit -m "feat: add core dependencies (riverpod, supabase, easy_localization, go_router)"
```

---

### Task 3: Port Lumina Prime design tokens into AppColors + AppTheme

**Files:**
- Create: `app/lib/core/theme/app_colors.dart`
- Create: `app/lib/core/theme/app_theme.dart`
- Test: `app/test/core/theme/app_theme_test.dart`

**Interfaces:**
- Consumes: nothing from prior tasks (pure Dart/Flutter).
- Produces: `AppColors` (static `Color` constants), `AppTheme.light` (a `ThemeData` getter) — every later screen imports `AppTheme.light` via `MaterialApp(theme: ...)`, never builds its own `ThemeData`.

Known source conflict (document, don't silently pick): `DESIGN.md`'s YAML frontmatter lists `on-primary: '#ffffff'`, but its prose "Color Roles" section states `On-Primary: #000000 (Text/Icons on Lime buttons)`. White text on Vibrant Lime (`#d4ff00`/`#536600`) fails contrast; black text on lime is the only one that's actually legible. This plan uses **black** (`#000000`) for `onPrimary` and notes the discrepancy in a code comment — flag it to the user if the mockups (`code.html`) show otherwise.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/core/theme/app_theme_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/theme/app_colors.dart';
import 'package:renly/core/theme/app_theme.dart';

void main() {
  group('AppColors', () {
    test('primary matches Lumina Prime token #536600', () {
      expect(AppColors.primary, const Color(0xFF536600));
    });

    test('primaryContainer matches Lumina Prime token #d4ff00', () {
      expect(AppColors.primaryContainer, const Color(0xFFD4FF00));
    });

    test('onPrimary is black for contrast on Vibrant Lime', () {
      expect(AppColors.onPrimary, const Color(0xFF000000));
    });

    test('background matches Lumina Prime token #f9faf7', () {
      expect(AppColors.background, const Color(0xFFF9FAF7));
    });
  });

  group('AppTheme.light', () {
    final theme = AppTheme.light;

    test('colorScheme.primary matches AppColors.primary', () {
      expect(theme.colorScheme.primary, AppColors.primary);
    });

    test('uses Material 3', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('headlineLarge uses Syne font family', () {
      expect(theme.textTheme.headlineLarge?.fontFamily, contains('Syne'));
    });

    test('bodyMedium uses Hanken Grotesk font family', () {
      expect(theme.textTheme.bodyMedium?.fontFamily, contains('Hanken'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/core/theme/app_theme_test.dart
```
Expected: FAIL — `Error: Error when reading 'lib/core/theme/app_colors.dart': No such file or directory` (or equivalent "package:renly/core/theme/... not found").

- [ ] **Step 3: Implement AppColors**

```dart
// app/lib/core/theme/app_colors.dart

/// Color tokens ported from stitch_renly_property_agent_network/lumina_prime/DESIGN.md.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF536600);
  // DESIGN.md frontmatter says on-primary #ffffff, but the prose "Color
  // Roles" section says #000000 (text/icons on Lime buttons). White-on-lime
  // fails contrast; using black per the prose section.
  static const Color onPrimary = Color(0xFF000000);
  static const Color primaryContainer = Color(0xFFD4FF00);
  static const Color onPrimaryContainer = Color(0xFF5F7400);

  static const Color secondary = Color(0xFF5F5E5E);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFE5E2E1);
  static const Color onSecondaryContainer = Color(0xFF656464);

  static const Color tertiary = Color(0xFF732EE4);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFF4EAFF);
  static const Color onTertiaryContainer = Color(0xFF8140F2);

  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);

  static const Color background = Color(0xFFF9FAF7);
  static const Color onBackground = Color(0xFF191C1B);
  static const Color surface = Color(0xFFF9FAF7);
  static const Color onSurface = Color(0xFF191C1B);
  static const Color surfaceVariant = Color(0xFFE2E3E0);
  static const Color outline = Color(0xFF757A60);
}
```

Add the required import at the top of that file:
```dart
import 'package:flutter/material.dart';
```

- [ ] **Step 4: Implement AppTheme**

```dart
// app/lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Theme ported from stitch_renly_property_agent_network/lumina_prime/DESIGN.md.
/// Typography: Syne (headlines), Hanken Grotesk (body), JetBrains Mono (data labels).
/// Shape: 8px standard elements, 16px containers, 24px feature elements.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.onSecondaryContainer,
      tertiary: AppColors.tertiary,
      onTertiary: AppColors.onTertiary,
      tertiaryContainer: AppColors.tertiaryContainer,
      onTertiaryContainer: AppColors.onTertiaryContainer,
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      surfaceVariant: AppColors.surfaceVariant,
      outline: AppColors.outline,
    );

    final baseTextTheme = TextTheme(
      headlineLarge: GoogleFonts.syne(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 40 / 32,
        letterSpacing: -0.01 * 32,
        color: AppColors.onBackground,
      ),
      titleMedium: GoogleFonts.hankenGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 28 / 20,
        color: AppColors.onBackground,
      ),
      bodyLarge: GoogleFonts.hankenGrotesk(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 26 / 18,
        color: AppColors.onBackground,
      ),
      bodyMedium: GoogleFonts.hankenGrotesk(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 24 / 16,
        color: AppColors.onBackground,
      ),
      labelSmall: GoogleFonts.jetBrainsMono(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 16 / 12,
        letterSpacing: 0.05 * 12,
        color: AppColors.onSurface,
      ),
      labelLarge: GoogleFonts.hankenGrotesk(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 20 / 16,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: baseTextTheme,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: baseTextTheme.labelLarge,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.secondary, width: 2),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/core/theme/app_theme_test.dart
```
Expected: `00:0X +9: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/core/theme/ app/test/core/theme/
git commit -m "feat: port Lumina Prime design tokens into AppColors/AppTheme"
```

---

### Task 4: Set up localization JSON assets (Bahasa Melayu + English)

**Files:**
- Create: `app/assets/translations/en.json`
- Create: `app/assets/translations/ms.json`
- Test: `app/test/l10n/translations_test.dart`
- Modify: `app/pubspec.yaml` (add `assets:` entry)

**Interfaces:**
- Produces: two JSON translation tables consumed by `easy_localization` in Task 5's `main.dart`. Every future screen must add its strings to *both* files with matching keys.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/l10n/translations_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('en.json and ms.json exist, parse, and have matching key sets', () {
    final enFile = File('assets/translations/en.json');
    final msFile = File('assets/translations/ms.json');

    expect(enFile.existsSync(), isTrue, reason: 'assets/translations/en.json missing');
    expect(msFile.existsSync(), isTrue, reason: 'assets/translations/ms.json missing');

    final en = jsonDecode(enFile.readAsStringSync()) as Map<String, dynamic>;
    final ms = jsonDecode(msFile.readAsStringSync()) as Map<String, dynamic>;

    expect(en.keys.toSet(), equals(ms.keys.toSet()),
        reason: 'en.json and ms.json must have identical keys');
    expect(en.containsKey('app_name'), isTrue);
    expect(en['app_name'], equals('renly'));
    expect(ms['app_name'], equals('renly'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/l10n/translations_test.dart
```
Expected: FAIL — `assets/translations/en.json missing`.

- [ ] **Step 3: Create the translation files**

```json
// app/assets/translations/en.json
{
  "app_name": "renly",
  "verification_pending": "Verification pending",
  "verification_pending_body": "Your registration is being checked against the public register. You'll be notified once it's approved."
}
```

```json
// app/assets/translations/ms.json
{
  "app_name": "renly",
  "verification_pending": "Pengesahan sedang diproses",
  "verification_pending_body": "Pendaftaran anda sedang disemak dengan daftar awam. Anda akan dimaklumkan sebaik sahaja ia diluluskan."
}
```

- [ ] **Step 4: Register the assets folder in pubspec.yaml**

In `app/pubspec.yaml`, under the `flutter:` section, add:
```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/translations/
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/l10n/translations_test.dart
```
Expected: `00:0X +1: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/assets/translations/ app/test/l10n/ app/pubspec.yaml
git commit -m "feat: add en/ms translation tables"
```

---

### Task 5: Supabase config loader (env-driven, testable without network)

**Files:**
- Create: `app/lib/core/config/supabase_config.dart`
- Test: `app/test/core/config/supabase_config_test.dart`
- Create: `app/.env.example`

**Interfaces:**
- Consumes: nothing from prior tasks.
- Produces: `SupabaseConfig.fromEnvironment(Map<String, String> env)` — a pure factory (no `dotenv` singleton reads inside it, so it's unit-testable) returning a `SupabaseConfig` with `url` and `anonKey` fields. Task 6's `main.dart` calls this with `dotenv.env` after loading the `.env` file.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/core/config/supabase_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/config/supabase_config.dart';

void main() {
  group('SupabaseConfig.fromEnvironment', () {
    test('returns config when both keys present', () {
      final config = SupabaseConfig.fromEnvironment({
        'SUPABASE_URL': 'https://example.supabase.co',
        'SUPABASE_ANON_KEY': 'test-anon-key',
      });

      expect(config.url, 'https://example.supabase.co');
      expect(config.anonKey, 'test-anon-key');
    });

    test('throws ArgumentError when SUPABASE_URL missing', () {
      expect(
        () => SupabaseConfig.fromEnvironment({'SUPABASE_ANON_KEY': 'x'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when SUPABASE_ANON_KEY missing', () {
      expect(
        () => SupabaseConfig.fromEnvironment({'SUPABASE_URL': 'https://x.supabase.co'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/core/config/supabase_config_test.dart
```
Expected: FAIL — `package:renly/core/config/supabase_config.dart` not found.

- [ ] **Step 3: Implement SupabaseConfig**

```dart
// app/lib/core/config/supabase_config.dart

/// Reads Supabase connection details out of an environment map (normally
/// `dotenv.env` after `.env` has been loaded). Kept as a pure factory so it
/// can be unit-tested without touching flutter_dotenv or the network.
class SupabaseConfig {
  final String url;
  final String anonKey;

  const SupabaseConfig({required this.url, required this.anonKey});

  factory SupabaseConfig.fromEnvironment(Map<String, String> env) {
    final url = env['SUPABASE_URL'];
    final anonKey = env['SUPABASE_ANON_KEY'];

    if (url == null || url.isEmpty) {
      throw ArgumentError(
        'SUPABASE_URL missing. Copy app/.env.example to app/.env and fill in your Supabase project values.',
      );
    }
    if (anonKey == null || anonKey.isEmpty) {
      throw ArgumentError(
        'SUPABASE_ANON_KEY missing. Copy app/.env.example to app/.env and fill in your Supabase project values.',
      );
    }

    return SupabaseConfig(url: url, anonKey: anonKey);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/core/config/supabase_config_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 5: Create the .env.example template**

```bash
# app/.env.example
# Copy this file to app/.env and fill in your actual Supabase project values.
# app/.env is git-ignored — never commit real credentials.
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
```

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/core/config/ app/test/core/config/ app/.env.example
git commit -m "feat: add testable SupabaseConfig env loader"
```

---

### Task 6: Wire main.dart — Riverpod, EasyLocalization, Supabase, themed placeholder screen

**Files:**
- Modify: `app/lib/main.dart`
- Modify: `app/pubspec.yaml` (add `.env` to `assets:`)
- Create: `app/lib/core/router/app_router.dart`
- Create: `app/lib/features/verification/verification_pending_screen.dart`
- Test: `app/test/features/verification/verification_pending_screen_test.dart`

**Interfaces:**
- Consumes: `AppTheme.light` (Task 3), `en.json`/`ms.json` keys `app_name`/`verification_pending`/`verification_pending_body` (Task 4), `SupabaseConfig.fromEnvironment` (Task 5).
- Produces: a running app. `app_router.dart` exposes `appRouter` (a `GoRouter`) — later feature tasks add routes here rather than each screen managing its own navigation.

- [ ] **Step 1: Write the failing widget test**

```dart
// app/test/features/verification/verification_pending_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/verification/verification_pending_screen.dart';

void main() {
  setUpAll(() async {
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('renders localized verification pending copy', (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
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
            home: const VerificationPendingScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Verification pending'), findsOneWidget);
    expect(
      find.text("Your registration is being checked against the public register. You'll be notified once it's approved."),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/verification/verification_pending_screen_test.dart
```
Expected: FAIL — `package:renly/features/verification/verification_pending_screen.dart` not found.

- [ ] **Step 3: Implement the placeholder screen**

```dart
// app/lib/features/verification/verification_pending_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Milestone-1 placeholder proving theme + localization wiring works end to
/// end. Gets replaced by the real onboarding/verification flow in the next
/// plan (auth + verification module).
class VerificationPendingScreen extends StatelessWidget {
  const VerificationPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'verification_pending'.tr(),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 24),
              Text(
                'verification_pending_body'.tr(),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/verification/verification_pending_screen_test.dart
```
Expected: `00:0X +1: All tests passed!`

- [ ] **Step 5: Create the router**

```dart
// app/lib/core/router/app_router.dart
import 'package:go_router/go_router.dart';

import '../../features/verification/verification_pending_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const VerificationPendingScreen(),
    ),
  ],
);
```

- [ ] **Step 6: Add `.env` to pubspec assets**

In `app/pubspec.yaml`:
```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/translations/
    - .env
```

- [ ] **Step 7: Replace main.dart**

```dart
// app/lib/main.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final supabaseConfig = SupabaseConfig.fromEnvironment(dotenv.env);
  await Supabase.initialize(
    url: supabaseConfig.url,
    anonKey: supabaseConfig.anonKey,
  );

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ms')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const ProviderScope(child: RenlyApp()),
    ),
  );
}

class RenlyApp extends StatelessWidget {
  const RenlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'renly',
      theme: AppTheme.light,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      routerConfig: appRouter,
    );
  }
}
```

- [ ] **Step 8: Delete the stock counter test (it references removed code)**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
rm -f test/widget_test.dart
```

- [ ] **Step 9: Run the full test suite**

```bash
flutter test
```
Expected: all tests across `test/core/`, `test/l10n/`, `test/features/` pass, e.g. `00:0X +16: All tests passed!` (no failures, no skips).

- [ ] **Step 10: Static analysis check**

```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 11: Create the real `.env` (manual, not committed)**

```bash
cp .env.example .env
```
Then edit `app/.env` and replace the placeholders with the actual Supabase project URL and anon key (Project Settings → API in the Supabase dashboard). Confirm it's ignored:
```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git status
```
Expected: `app/.env` does **not** appear in the output (already covered by the root `.gitignore`'s `.env` rule).

- [ ] **Step 12: Manual verification on device/emulator**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter devices
flutter run
```
Expected: app launches on the selected Android device/emulator, shows the "Verification pending" screen in the Lumina Prime theme (off-white background, Syne headline) with no red error screen — this confirms the Supabase client initialized without throwing.

- [ ] **Step 13: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/main.dart app/lib/core/router/ app/lib/features/verification/ app/test/features/ app/pubspec.yaml
git rm app/test/widget_test.dart
git commit -m "feat: wire Riverpod, EasyLocalization, Supabase, and router in main.dart"
```

---

## Definition of Done

- `flutter test` (run from `app/`) passes with zero failures.
- `flutter analyze` reports no issues.
- `flutter run` on a real Android device shows the themed, localized placeholder screen and does not crash on startup (proves Supabase connected).
- `app/.env` holds real credentials and is confirmed absent from `git status`.
- All 6 tasks committed individually (6+ commits, not one giant commit).

## Explicitly not in this plan

Auth/registration UI, camera tag-scan, database schema/RLS, listing/requirement/matching/collaboration/subscription features, converting the remaining 12 Stitch mockups. These start in the next plan per the design doc's build order (Step 2 onward).
