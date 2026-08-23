# Settings Sub-Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the 4 settings sub-pages (Notification, Account, Privacy, Help) from the `profile_settings` mockup, reachable from a new "App Settings" section on `ProfileScreen`.

**Architecture:** A new `features/settings/` module with one repository (`SettingsRepository`, direct Supabase touchpoint, no composition) and 4 screens. Notification preferences are 3 real, DB-persisted boolean columns on `negotiator` — functionally inert since this app has no push notification delivery yet, but real enough not to need rebuilding later. Account adds a password-change form (Supabase Auth) plus an on-demand identity-info read (IC/phone/REN) that is deliberately kept separate from `ProfileScreen`'s existing minimized profile query. Privacy and Help are pure static content, no backend at all.

**Tech Stack:** Flutter, Riverpod, supabase_flutter, easy_localization (EN/MS), go_router. No new dependencies, no Realtime, no new RLS policies.

## Global Constraints

- `0012_settings.sql` must NEVER include a `revoke update on negotiator` statement. The 3 new columns are granted additively on top of the existing 7-column grant from `0010_profile.sql` (`full_name, ic_number, phone_number, ren_number, agency_id, territory, property_specialisation`). Postgres `GRANT` is additive — it does not reset prior privileges, only `REVOKE` does. A bare revoke+narrower-regrant here would repeat Profile Management's Critical bug (which silently stripped 5 pre-existing UPDATE columns). Any future migration touching this table's UPDATE grant must either stay additive-only or restate the full column list — never a bare revoke+narrow-regrant.
- `SettingsRepository` is untested directly (Supabase-calling code) — established project convention. `NotificationPreferences.fromJson`/`IdentityInfo.fromJson` get real unit tests. Widget-tested UI (`NotificationSettingsScreen`, `AccountSettingsScreen`, `PrivacyScreen`, `HelpScreen`, `ProfileScreen`'s new settings section) all get widget tests via provider override.
- `currentNegotiatorIdProvider`: add another own copy in `settings_providers.dart`, same per-feature-file duplication convention as every sibling feature (`rating_providers.dart`, `agreement_providers.dart`, etc.).
- `notificationPreferencesProvider` and `identityInfoProvider` must both be `.autoDispose` — not bare `FutureProvider` — this project's pinned Riverpod 2.6.1 does not default providers to autoDispose.
- Every `.when()` error branch added in this plan must render visible text (and, where a provider can be retried, a retry action) — never `SizedBox.shrink()`. Ratings' final review flagged silent-error-swallowing as a recurring Minor issue; this plan does not repeat it.
- The Account password form's validation MUST reuse `AuthValidation.isValidPassword`/`AuthValidation.passwordsMatch` (`app/lib/features/auth/auth_validation.dart`) and the existing `validation_password_too_short`/`validation_password_mismatch` l10n keys — do not invent new validation logic or new keys for the same checks.
- l10n: every new user-facing string needs both an `en.json` and `ms.json` entry.

---

### Task 1: Supabase Migration SQL (0012_settings.sql)

**Files:**
- Create: `supabase/migrations/0012_settings.sql`
- Modify: `app/README.md` (append a "Milestone 11 setup (settings)" section after the Milestone 10 section)

**Interfaces:**
- Consumes: `negotiator` table (from `0001_auth_verification.sql`, column grant most recently touched by `0010_profile.sql`).
- Produces: `negotiator.notify_match`, `negotiator.notify_message`, `negotiator.notify_cobroke_request` (all `boolean not null default true`), used by Task 3's `SettingsRepository`.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0012_settings.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0011.
--
-- Written to be re-runnable from the start, same pattern as every prior
-- migration.

alter table negotiator add column if not exists notify_match boolean not null default true;
alter table negotiator add column if not exists notify_message boolean not null default true;
alter table negotiator add column if not exists notify_cobroke_request boolean not null default true;

-- Additive only -- deliberately NO preceding `revoke update on negotiator`.
-- Postgres GRANT is additive (it does not replace or reset prior column
-- grants); only REVOKE resets a privilege set. 0010_profile.sql's own
-- migration comment documents exactly why a revoke+narrower-regrant pair
-- is dangerous on this table: it silently stripped 5 pre-existing UPDATE
-- columns in that milestone's Critical bug (revoking UPDATE revokes ALL
-- existing column-level UPDATE privileges, not just the ones a subsequent
-- narrower grant re-covers). This migration sidesteps the entire bug class
-- by never revoking at all -- the existing 7-column UPDATE grant
-- (full_name, ic_number, phone_number, ren_number, agency_id, territory,
-- property_specialisation) from 0010_profile.sql is left untouched, and
-- these 3 columns are simply added on top of it. No RLS policy change is
-- needed either: negotiator_update_own/negotiator_select_own (from 0001)
-- already gate which ROW can be touched (auth.uid() = negotiator_id) --
-- this grant only controls which COLUMNS, same division of labour as
-- every prior grant on this table.
grant update (notify_match, notify_message, notify_cobroke_request) on negotiator to authenticated;
```

- [ ] **Step 2: Append README setup section**

Read `app/README.md`, find the "Milestone 10 setup (rating)" section, and append immediately after it:

```markdown
## Milestone 11 setup (settings)

Run `supabase/migrations/0012_settings.sql` in the Supabase SQL Editor after 0001-0011. This adds 3 notification-preference boolean columns to `negotiator` (all default `true`) and an additive-only UPDATE grant for them -- no RLS policy change, no new table, no `revoke` statement. No manual dashboard step beyond running the SQL, and no sequence-sensitive verification needed (unlike Ratings) since nothing here depends on cross-user visibility.

A normal smoke test after running is sufficient: open Settings > Notification and confirm all 3 toggles show as ON by default, flip one off and confirm it persists across an app restart.
```

- [ ] **Step 3: Verify with grep**

Run:
```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
grep -c "^alter table negotiator add column" supabase/migrations/0012_settings.sql
grep -c "revoke update on negotiator" supabase/migrations/0012_settings.sql
grep -c "^grant update" supabase/migrations/0012_settings.sql
```
Expected: `3`, `0`, `1` (the `0` on the middle command is the whole point of this task).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0012_settings.sql app/README.md
git commit -m "feat: add settings migration with additive-only notification preference grant"
```

---

### Task 2: NotificationPreferences + IdentityInfo models + unit tests

**Files:**
- Create: `app/lib/features/settings/models/notification_preferences.dart`
- Create: `app/lib/features/settings/models/identity_info.dart`
- Test: `app/test/features/settings/models/notification_preferences_test.dart`
- Test: `app/test/features/settings/models/identity_info_test.dart`

**Interfaces:**
- Consumes: nothing (plain data classes).
- Produces: `NotificationPreferences` class with `notifyMatch, notifyMessage, notifyCobrokeRequest` (all `bool`) and `NotificationPreferences.fromJson(Map<String, dynamic>)`; `IdentityInfo` class with `icNumber, phoneNumber, renNumber` (all `String?`) and `IdentityInfo.fromJson(Map<String, dynamic>)` — both used by Task 3's `SettingsRepository`, Task 3's providers, and Tasks 4/5's screens.

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/features/settings/models/notification_preferences_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/settings/models/notification_preferences.dart';

void main() {
  group('NotificationPreferences.fromJson', () {
    test('parses all three flags', () {
      final prefs = NotificationPreferences.fromJson({
        'notify_match': true,
        'notify_message': false,
        'notify_cobroke_request': true,
      });

      expect(prefs.notifyMatch, isTrue);
      expect(prefs.notifyMessage, isFalse);
      expect(prefs.notifyCobrokeRequest, isTrue);
    });
  });
}
```

```dart
// app/test/features/settings/models/identity_info_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/settings/models/identity_info.dart';

void main() {
  group('IdentityInfo.fromJson', () {
    test('parses all three fields when present', () {
      final info = IdentityInfo.fromJson({
        'ic_number': '900101-14-1234',
        'phone_number': '012-3456789',
        'ren_number': '12345',
      });

      expect(info.icNumber, '900101-14-1234');
      expect(info.phoneNumber, '012-3456789');
      expect(info.renNumber, '12345');
    });

    test('parses null fields as null', () {
      final info = IdentityInfo.fromJson({
        'ic_number': null,
        'phone_number': null,
        'ren_number': null,
      });

      expect(info.icNumber, isNull);
      expect(info.phoneNumber, isNull);
      expect(info.renNumber, isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/settings/models/ -v`
Expected: FAIL — `Error: Couldn't resolve the package 'renly'` / files not found.

- [ ] **Step 3: Write the models**

```dart
// app/lib/features/settings/models/notification_preferences.dart
/// Real, DB-persisted notification preference flags -- functionally inert
/// today since this app has no push notification delivery (no FCM wired
/// in anywhere). Kept as genuine columns rather than a client-only toggle
/// so nothing needs rebuilding once push delivery exists.
class NotificationPreferences {
  final bool notifyMatch;
  final bool notifyMessage;
  final bool notifyCobrokeRequest;

  const NotificationPreferences({
    required this.notifyMatch,
    required this.notifyMessage,
    required this.notifyCobrokeRequest,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      notifyMatch: json['notify_match'] as bool,
      notifyMessage: json['notify_message'] as bool,
      notifyCobrokeRequest: json['notify_cobroke_request'] as bool,
    );
  }
}
```

```dart
// app/lib/features/settings/models/identity_info.dart
/// A narrower, on-demand read of the negotiator row's identity columns --
/// deliberately separate from the Profile feature's own fetchMyProfile,
/// which excludes ic_number/phone_number to avoid pulling PII into memory
/// on every Profile screen view. This model exists only for the Account
/// settings screen, fetched only when that screen is opened.
class IdentityInfo {
  final String? icNumber;
  final String? phoneNumber;
  final String? renNumber;

  const IdentityInfo({this.icNumber, this.phoneNumber, this.renNumber});

  factory IdentityInfo.fromJson(Map<String, dynamic> json) {
    return IdentityInfo(
      icNumber: json['ic_number'] as String?,
      phoneNumber: json['phone_number'] as String?,
      renNumber: json['ren_number'] as String?,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/settings/models/ -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/settings/models/ app/test/features/settings/models/
git commit -m "feat: add NotificationPreferences and IdentityInfo models"
```

---

### Task 3: SettingsRepository + settings_providers.dart

**Files:**
- Create: `app/lib/features/settings/settings_repository.dart`
- Create: `app/lib/features/settings/settings_providers.dart`

**Interfaces:**
- Consumes: `NotificationPreferences`/`IdentityInfo` (Task 2), `authStateProvider` (`app/lib/features/auth/auth_providers.dart`).
- Produces: `SettingsRepository` with `fetchNotificationPreferences`, `updateNotificationPreferences`, `fetchIdentityInfo`, `updatePassword`; `settingsRepositoryProvider`, `currentNegotiatorIdProvider` (this file's own copy), `notificationPreferencesProvider = FutureProvider.autoDispose<NotificationPreferences>`, `identityInfoProvider = FutureProvider.autoDispose<IdentityInfo>` — used by Tasks 4 and 5's screens.

- [ ] **Step 1: Write the repository**

```dart
// app/lib/features/settings/settings_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/identity_info.dart';
import 'models/notification_preferences.dart';

/// The only file in this app that talks to Supabase for the settings
/// feature. Composes nothing -- every method is a direct read/write on
/// `negotiator` or a call into Supabase Auth, same shallow shape as
/// ProfileRepository.
class SettingsRepository {
  SettingsRepository(this._client);

  final SupabaseClient _client;

  Future<NotificationPreferences> fetchNotificationPreferences(String negotiatorId) async {
    final row = await _client
        .from('negotiator')
        .select('notify_match, notify_message, notify_cobroke_request')
        .eq('negotiator_id', negotiatorId)
        .single();
    return NotificationPreferences.fromJson(row);
  }

  Future<void> updateNotificationPreferences({
    required String negotiatorId,
    required bool notifyMatch,
    required bool notifyMessage,
    required bool notifyCobrokeRequest,
  }) {
    return _client.from('negotiator').update({
      'notify_match': notifyMatch,
      'notify_message': notifyMessage,
      'notify_cobroke_request': notifyCobrokeRequest,
    }).eq('negotiator_id', negotiatorId);
  }

  /// Deliberately separate from ProfileRepository.fetchMyProfile, which
  /// excludes ic_number/phone_number to avoid pulling PII into memory on
  /// every Profile screen view. This query only runs when the Account
  /// settings screen is opened.
  Future<IdentityInfo> fetchIdentityInfo(String negotiatorId) async {
    final row = await _client
        .from('negotiator')
        .select('ic_number, phone_number, ren_number')
        .eq('negotiator_id', negotiatorId)
        .single();
    return IdentityInfo.fromJson(row);
  }

  /// No current-password argument -- Supabase Auth's updateUser call has
  /// no such parameter, since it operates on the already-authenticated
  /// session, not a re-authentication flow.
  Future<void> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }
}
```

- [ ] **Step 2: Write the providers**

```dart
// app/lib/features/settings/settings_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import 'models/identity_info.dart';
import 'models/notification_preferences.dart';
import 'settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(Supabase.instance.client);
});

/// Same session-state read as the copies in every sibling feature's own
/// providers file -- duplicated here rather than imported, same
/// established reasoning as those files.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// autoDispose is REQUIRED, not the default, in this project's pinned
/// Riverpod version (2.6.1).
final notificationPreferencesProvider = FutureProvider.autoDispose<NotificationPreferences>((ref) {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) {
    return Future.error(StateError('No authenticated negotiator.'));
  }
  return ref.watch(settingsRepositoryProvider).fetchNotificationPreferences(negotiatorId);
});

final identityInfoProvider = FutureProvider.autoDispose<IdentityInfo>((ref) {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) {
    return Future.error(StateError('No authenticated negotiator.'));
  }
  return ref.watch(settingsRepositoryProvider).fetchIdentityInfo(negotiatorId);
});
```

- [ ] **Step 3: Verify it compiles**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter analyze lib/features/settings/`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/settings/settings_repository.dart app/lib/features/settings/settings_providers.dart
git commit -m "feat: add SettingsRepository and settings providers"
```

---

### Task 4: NotificationSettingsScreen + widget tests

**Files:**
- Create: `app/lib/features/settings/notification_settings_screen.dart`
- Test: `app/test/features/settings/notification_settings_screen_test.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `notificationPreferencesProvider`, `currentNegotiatorIdProvider`, `settingsRepositoryProvider` (Task 3).
- Produces: `NotificationSettingsScreen` widget, used by Task 7's router wiring.

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`, find the line `"profile_status_rejected": "Not Verified"` (currently the last key before the closing `}`) and change it to add a trailing comma, then insert these keys after it, before the closing `}`:

```json
  "profile_status_rejected": "Not Verified",
  "notification_settings_title": "Notification",
  "notification_settings_match_label": "New matches",
  "notification_settings_message_label": "New messages",
  "notification_settings_cobroke_request_label": "New co-broke requests"
```

In `app/assets/translations/ms.json`, find the line `"profile_status_rejected": "Tidak Disahkan"` (currently the last key before the closing `}`) and change it to add a trailing comma, then insert these keys after it, before the closing `}`:

```json
  "profile_status_rejected": "Tidak Disahkan",
  "notification_settings_title": "Notifikasi",
  "notification_settings_match_label": "Padanan baharu",
  "notification_settings_message_label": "Mesej baharu",
  "notification_settings_cobroke_request_label": "Permintaan co-broke baharu"
```

- [ ] **Step 2: Write the failing test**

```dart
// app/test/features/settings/notification_settings_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/settings/models/notification_preferences.dart';
import 'package:renly/features/settings/notification_settings_screen.dart';
import 'package:renly/features/settings/settings_providers.dart';

Widget _wrap(GoRouter router, {NotificationPreferences? prefs, Object? error}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      if (error != null)
        notificationPreferencesProvider.overrideWith((ref) async => throw error)
      else
        notificationPreferencesProvider.overrideWith(
          (ref) async =>
              prefs ??
              const NotificationPreferences(notifyMatch: true, notifyMessage: false, notifyCobrokeRequest: true),
        ),
    ],
    child: EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ms')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: Builder(
        builder: (context) => MaterialApp.router(
          theme: AppTheme.light,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          routerConfig: router,
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

  testWidgets('renders three toggles with the provider-supplied initial state', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const NotificationSettingsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('New matches'), findsOneWidget);
    expect(find.text('New messages'), findsOneWidget);
    expect(find.text('New co-broke requests'), findsOneWidget);

    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    expect(switches[0].value, isTrue);
    expect(switches[1].value, isFalse);
    expect(switches[2].value, isTrue);
  });

  testWidgets('shows visible error text on load failure, not a blank screen', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const NotificationSettingsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, error: StateError('boom')));
    await tester.pumpAndSettle();

    expect(find.text('listing_error_generic'.tr()), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/settings/notification_settings_screen_test.dart -v`
Expected: FAIL — `notification_settings_screen.dart` not found.

- [ ] **Step 4: Write the screen**

```dart
// app/lib/features/settings/notification_settings_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/notification_preferences.dart';
import 'settings_providers.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences current, {
    bool? notifyMatch,
    bool? notifyMessage,
    bool? notifyCobrokeRequest,
  }) async {
    final negotiatorId = ref.read(currentNegotiatorIdProvider);
    if (negotiatorId == null) return;
    try {
      await ref.read(settingsRepositoryProvider).updateNotificationPreferences(
            negotiatorId: negotiatorId,
            notifyMatch: notifyMatch ?? current.notifyMatch,
            notifyMessage: notifyMessage ?? current.notifyMessage,
            notifyCobrokeRequest: notifyCobrokeRequest ?? current.notifyCobrokeRequest,
          );
      ref.invalidate(notificationPreferencesProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('listing_error_generic'.tr())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: Text('notification_settings_title'.tr())),
      body: prefsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('listing_error_generic'.tr()),
              TextButton(
                onPressed: () => ref.invalidate(notificationPreferencesProvider),
                child: Text('agreement_retry'.tr()),
              ),
            ],
          ),
        ),
        data: (prefs) => ListView(
          children: [
            SwitchListTile(
              title: Text('notification_settings_match_label'.tr()),
              value: prefs.notifyMatch,
              onChanged: (value) => _toggle(context, ref, prefs, notifyMatch: value),
            ),
            SwitchListTile(
              title: Text('notification_settings_message_label'.tr()),
              value: prefs.notifyMessage,
              onChanged: (value) => _toggle(context, ref, prefs, notifyMessage: value),
            ),
            SwitchListTile(
              title: Text('notification_settings_cobroke_request_label'.tr()),
              value: prefs.notifyCobrokeRequest,
              onChanged: (value) => _toggle(context, ref, prefs, notifyCobrokeRequest: value),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/settings/notification_settings_screen_test.dart -v`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/settings/notification_settings_screen.dart app/test/features/settings/notification_settings_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add NotificationSettingsScreen"
```

---

### Task 5: AccountSettingsScreen (identity display + password form) + widget tests

**Files:**
- Create: `app/lib/features/settings/account_settings_screen.dart`
- Test: `app/test/features/settings/account_settings_screen_test.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `identityInfoProvider`, `settingsRepositoryProvider` (Task 3), `AuthValidation.isValidPassword`/`AuthValidation.passwordsMatch` (`app/lib/features/auth/auth_validation.dart`), existing `validation_password_too_short`/`validation_password_mismatch` l10n keys.
- Produces: `AccountSettingsScreen` widget, used by Task 7's router wiring.

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`, after the `notification_settings_cobroke_request_label` key added in Task 4 (now the last key before the closing `}`), add a trailing comma and insert:

```json
  "notification_settings_cobroke_request_label": "New co-broke requests",
  "account_settings_title": "Account",
  "account_settings_ic_label": "IC Number",
  "account_settings_phone_label": "Phone Number",
  "account_settings_password_section_title": "Change Password",
  "account_settings_new_password_label": "New Password",
  "account_settings_confirm_password_label": "Confirm New Password",
  "account_settings_submit": "Update Password",
  "account_settings_password_success": "Password updated"
```

In `app/assets/translations/ms.json`, after the `notification_settings_cobroke_request_label` key added in Task 4, add a trailing comma and insert:

```json
  "notification_settings_cobroke_request_label": "Permintaan co-broke baharu",
  "account_settings_title": "Akaun",
  "account_settings_ic_label": "Nombor IC",
  "account_settings_phone_label": "Nombor Telefon",
  "account_settings_password_section_title": "Tukar Kata Laluan",
  "account_settings_new_password_label": "Kata Laluan Baharu",
  "account_settings_confirm_password_label": "Sahkan Kata Laluan Baharu",
  "account_settings_submit": "Kemas Kini Kata Laluan",
  "account_settings_password_success": "Kata laluan dikemas kini"
```

- [ ] **Step 2: Write the failing test**

```dart
// app/test/features/settings/account_settings_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/settings/account_settings_screen.dart';
import 'package:renly/features/settings/models/identity_info.dart';
import 'package:renly/features/settings/settings_providers.dart';

Widget _wrap(GoRouter router, {IdentityInfo? info}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      identityInfoProvider.overrideWith(
        (ref) async =>
            info ?? const IdentityInfo(icNumber: '900101-14-1234', phoneNumber: '012-3456789', renNumber: '12345'),
      ),
    ],
    child: EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ms')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: Builder(
        builder: (context) => MaterialApp.router(
          theme: AppTheme.light,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          routerConfig: router,
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

  testWidgets('renders identity info from the provider', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const AccountSettingsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('IC Number: 900101-14-1234'), findsOneWidget);
    expect(find.text('Phone Number: 012-3456789'), findsOneWidget);
    expect(find.text('Registration Number: 12345'), findsOneWidget);
  });

  testWidgets('shows a fallback dash for null identity fields', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const AccountSettingsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, info: const IdentityInfo()));
    await tester.pumpAndSettle();

    expect(find.text('IC Number: -'), findsOneWidget);
    expect(find.text('Phone Number: -'), findsOneWidget);
    expect(find.text('Registration Number: -'), findsOneWidget);
  });

  testWidgets('blocks submit and shows an error when passwords do not match', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const AccountSettingsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'New Password'), 'password123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm New Password'), 'different123');
    await tester.tap(find.text('Update Password'));
    await tester.pumpAndSettle();

    expect(find.text('validation_password_mismatch'.tr()), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/settings/account_settings_screen_test.dart -v`
Expected: FAIL — `account_settings_screen.dart` not found.

- [ ] **Step 4: Write the screen**

```dart
// app/lib/features/settings/account_settings_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_validation.dart';
import 'settings_providers.dart';

class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(identityInfoProvider);

    return Scaffold(
      appBar: AppBar(title: Text('account_settings_title'.tr())),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            infoAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('listing_error_generic'.tr()),
                  TextButton(
                    onPressed: () => ref.invalidate(identityInfoProvider),
                    child: Text('agreement_retry'.tr()),
                  ),
                ],
              ),
              data: (info) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${'account_settings_ic_label'.tr()}: ${info.icNumber ?? '-'}'),
                  const SizedBox(height: 4),
                  Text('${'account_settings_phone_label'.tr()}: ${info.phoneNumber ?? '-'}'),
                  const SizedBox(height: 4),
                  Text('${'profile_ren_number_label'.tr()}: ${info.renNumber ?? '-'}'),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text('account_settings_password_section_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const _PasswordForm(),
          ],
        ),
      ),
    );
  }
}

class _PasswordForm extends ConsumerStatefulWidget {
  const _PasswordForm();

  @override
  ConsumerState<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends ConsumerState<_PasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref.read(settingsRepositoryProvider).updatePassword(_newPasswordController.text);
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('account_settings_password_success'.tr())),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _submitError = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _newPasswordController,
            obscureText: true,
            decoration: InputDecoration(labelText: 'account_settings_new_password_label'.tr()),
            validator: (value) =>
                AuthValidation.isValidPassword(value ?? '') ? null : 'validation_password_too_short'.tr(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: true,
            decoration: InputDecoration(labelText: 'account_settings_confirm_password_label'.tr()),
            validator: (value) => AuthValidation.passwordsMatch(_newPasswordController.text, value ?? '')
                ? null
                : 'validation_password_mismatch'.tr(),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 8),
            Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: Text('account_settings_submit'.tr()),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/settings/account_settings_screen_test.dart -v`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/settings/account_settings_screen.dart app/test/features/settings/account_settings_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add AccountSettingsScreen with identity display and password change"
```

---

### Task 6: PrivacyScreen + HelpScreen + smoke tests

**Files:**
- Create: `app/lib/features/settings/privacy_screen.dart`
- Create: `app/lib/features/settings/help_screen.dart`
- Test: `app/test/features/settings/privacy_screen_test.dart`
- Test: `app/test/features/settings/help_screen_test.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: nothing (no provider, no repository, no state).
- Produces: `PrivacyScreen`, `HelpScreen` widgets, used by Task 7's router wiring.

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`, after the `account_settings_password_success` key added in Task 5 (now the last key before the closing `}`), add a trailing comma and insert:

```json
  "account_settings_password_success": "Password updated",
  "privacy_title": "Privacy",
  "privacy_body": "Renly collects your name, IC number, phone number, REN number, and agency to verify you as a licensed real estate negotiator. Your name and REN number are visible to other negotiators when you list a property, post a requirement, or receive a match -- this is required for the co-broking process to work. Your IC number and phone number are never shown to other negotiators; they are used only for verification. Ratings and reviews you receive are visible to any verified negotiator using the app, as a trust signal for potential collaborators.",
  "help_title": "Help",
  "help_faq_title": "Frequently Asked Questions",
  "help_faq_q1": "How do I get verified?",
  "help_faq_a1": "Complete registration with your IC and REN number, then wait for an administrator to approve your account. You'll see a Verification Pending screen until this happens.",
  "help_faq_q2": "Why can't I see a listing or requirement I used to see?",
  "help_faq_a2": "Listings and requirements only stay visible while active or open. Once marked sold, fulfilled, or withdrawn, they're hidden from everyone except their owner.",
  "help_faq_q3": "Can I edit a rating after I submit it?",
  "help_faq_a3": "Yes, within 24 hours of submitting it. After that, the rating becomes permanent.",
  "help_contact_title": "Contact Support",
  "help_contact_body": "For help with your account or verification, email support@renly.app."
```

In `app/assets/translations/ms.json`, after the `account_settings_password_success` key added in Task 5, add a trailing comma and insert:

```json
  "account_settings_password_success": "Kata laluan dikemas kini",
  "privacy_title": "Privasi",
  "privacy_body": "Renly mengumpul nama, nombor IC, nombor telefon, nombor REN, dan agensi anda untuk mengesahkan anda sebagai negotiator hartanah berlesen. Nama dan nombor REN anda kelihatan kepada negotiator lain apabila anda menyenaraikan hartanah, memuat naik keperluan, atau menerima padanan -- ini diperlukan untuk proses co-broking berfungsi. Nombor IC dan nombor telefon anda tidak pernah ditunjukkan kepada negotiator lain; ia digunakan hanya untuk pengesahan. Penilaian dan ulasan yang anda terima kelihatan kepada mana-mana negotiator yang disahkan menggunakan aplikasi ini, sebagai isyarat kepercayaan untuk bakal rakan kerjasama.",
  "help_title": "Bantuan",
  "help_faq_title": "Soalan Lazim",
  "help_faq_q1": "Bagaimana saya boleh disahkan?",
  "help_faq_a1": "Lengkapkan pendaftaran dengan nombor IC dan REN anda, kemudian tunggu pentadbir meluluskan akaun anda. Anda akan melihat skrin Menunggu Pengesahan sehingga ini berlaku.",
  "help_faq_q2": "Kenapa saya tak boleh nampak penyenaraian atau keperluan yang saya pernah nampak?",
  "help_faq_a2": "Penyenaraian dan keperluan hanya kekal kelihatan semasa aktif atau terbuka. Selepas ditanda terjual, dipenuhi, atau ditarik balik, ia disembunyikan daripada semua orang kecuali pemiliknya.",
  "help_faq_q3": "Boleh saya edit penilaian selepas hantar?",
  "help_faq_a3": "Boleh, dalam masa 24 jam selepas menghantarnya. Selepas itu, penilaian menjadi kekal.",
  "help_contact_title": "Hubungi Sokongan",
  "help_contact_body": "Untuk bantuan berkaitan akaun atau pengesahan, e-mel support@renly.app."
```

- [ ] **Step 2: Write the failing tests**

```dart
// app/test/features/settings/privacy_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/settings/privacy_screen.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    rootBundle.clear();
  });

  testWidgets('renders without error', (tester) async {
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
            home: const PrivacyScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Privacy'), findsOneWidget);
  });
}
```

```dart
// app/test/features/settings/help_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/settings/help_screen.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    rootBundle.clear();
  });

  testWidgets('renders FAQ and contact sections without error', (tester) async {
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
            home: const HelpScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Frequently Asked Questions'), findsOneWidget);
    expect(find.text('Contact Support'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/settings/privacy_screen_test.dart test/features/settings/help_screen_test.dart -v`
Expected: FAIL — `privacy_screen.dart`/`help_screen.dart` not found.

- [ ] **Step 4: Write the screens**

```dart
// app/lib/features/settings/privacy_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('privacy_title'.tr())),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text('privacy_body'.tr()),
      ),
    );
  }
}
```

```dart
// app/lib/features/settings/help_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  Widget _faqEntry(BuildContext context, String question, String answer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(answer),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('help_title'.tr())),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('help_faq_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _faqEntry(context, 'help_faq_q1'.tr(), 'help_faq_a1'.tr()),
            _faqEntry(context, 'help_faq_q2'.tr(), 'help_faq_a2'.tr()),
            _faqEntry(context, 'help_faq_q3'.tr(), 'help_faq_a3'.tr()),
            const SizedBox(height: 20),
            Text('help_contact_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('help_contact_body'.tr()),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/settings/privacy_screen_test.dart test/features/settings/help_screen_test.dart -v`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/settings/privacy_screen.dart app/lib/features/settings/help_screen.dart app/test/features/settings/privacy_screen_test.dart app/test/features/settings/help_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add static PrivacyScreen and HelpScreen"
```

---

### Task 7: Wire Settings list into ProfileScreen + router + l10n + tests

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart`
- Modify: `app/lib/core/router/app_router.dart`
- Modify: `app/test/features/profile/profile_screen_test.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `NotificationSettingsScreen` (Task 4), `AccountSettingsScreen` (Task 5), `PrivacyScreen`/`HelpScreen` (Task 6).
- Produces: `/settings/notification`, `/settings/account`, `/settings/privacy`, `/settings/help` routes; a new "App Settings" section on `ProfileScreen`.

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`, after the `help_contact_body` key added in Task 6 (now the last key before the closing `}`), add a trailing comma and insert:

```json
  "help_contact_body": "For help with your account or verification, email support@renly.app.",
  "settings_section_title": "App Settings",
  "settings_notification_row_title": "Notification",
  "settings_notification_row_subtitle": "Manage alerts and sounds",
  "settings_account_row_title": "Account",
  "settings_account_row_subtitle": "Security, password, and identity",
  "settings_privacy_row_title": "Privacy",
  "settings_privacy_row_subtitle": "Data sharing and visibility",
  "settings_help_row_title": "Help",
  "settings_help_row_subtitle": "Support, FAQ, and contact"
```

In `app/assets/translations/ms.json`, after the `help_contact_body` key added in Task 6, add a trailing comma and insert:

```json
  "help_contact_body": "Untuk bantuan berkaitan akaun atau pengesahan, e-mel support@renly.app.",
  "settings_section_title": "Tetapan Aplikasi",
  "settings_notification_row_title": "Notifikasi",
  "settings_notification_row_subtitle": "Urus makluman dan bunyi",
  "settings_account_row_title": "Akaun",
  "settings_account_row_subtitle": "Keselamatan, kata laluan, dan identiti",
  "settings_privacy_row_title": "Privasi",
  "settings_privacy_row_subtitle": "Perkongsian data dan keterlihatan",
  "settings_help_row_title": "Bantuan",
  "settings_help_row_subtitle": "Sokongan, soalan lazim, dan hubungi"
```

- [ ] **Step 2: Write the failing test**

`app/test/features/profile/profile_screen_test.dart` already has this exact `_wrap` helper (confirmed by reading the file directly):

```dart
Widget _wrap(GoRouter router, {Profile? profile, (int, int)? counts, List<RatingCandidate>? ratings}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      myProfileProvider.overrideWith((ref) async => profile ?? _fixtureProfile),
      profileCountsProvider.overrideWith((ref) async => counts ?? (5, 3)),
      ratingsForNegotiatorProvider('n-1').overrideWith((ref) async => ratings ?? const []),
    ],
    child: EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ms')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: Builder(
        builder: (context) => MaterialApp.router(
          theme: AppTheme.light,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          routerConfig: router,
        ),
      ),
    ),
  );
}
```

It takes a `GoRouter` you build per-test — reuse it as-is, do not duplicate or modify it. Add this test inside the existing `main()` block, after the last `testWidgets` (`'shows "No ratings yet" ...'`), before the closing `}` of `main()`:

```dart
  testWidgets('renders the 4 settings rows and navigates to each on tap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/settings/notification', builder: (context, state) => const Text('notification screen')),
      GoRoute(path: '/settings/account', builder: (context, state) => const Text('account screen')),
      GoRoute(path: '/settings/privacy', builder: (context, state) => const Text('privacy screen')),
      GoRoute(path: '/settings/help', builder: (context, state) => const Text('help screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Notification'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);

    await tester.tap(find.text('Notification'));
    await tester.pumpAndSettle();
    expect(find.text('notification screen'), findsOneWidget);
  });
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/profile/profile_screen_test.dart -v`
Expected: FAIL — no widget with text 'Notification' found.

- [ ] **Step 4: Add the settings section to ProfileScreen**

In `app/lib/features/profile/profile_screen.dart`, `context.push` is already available (the file already imports `package:go_router/go_router.dart` at line 5 — no new import needed).

Find this exact existing block (currently lines 63-67):

```dart
                const SizedBox(height: 20),
                _EditForm(profile: profile),
                const SizedBox(height: 20),
                Text('profile_language_label'.tr(), style: Theme.of(context).textTheme.titleMedium),
```

Replace it with (unchanged first 3 lines, then the new `Card`, then a new `SizedBox` before the language `Text`):

```dart
                const SizedBox(height: 20),
                _EditForm(profile: profile),
                const SizedBox(height: 20),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.notifications_active),
                        title: Text('settings_notification_row_title'.tr()),
                        subtitle: Text('settings_notification_row_subtitle'.tr()),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/settings/notification'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.manage_accounts),
                        title: Text('settings_account_row_title'.tr()),
                        subtitle: Text('settings_account_row_subtitle'.tr()),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/settings/account'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.privacy_tip),
                        title: Text('settings_privacy_row_title'.tr()),
                        subtitle: Text('settings_privacy_row_subtitle'.tr()),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/settings/privacy'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.help_outline),
                        title: Text('settings_help_row_title'.tr()),
                        subtitle: Text('settings_help_row_subtitle'.tr()),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/settings/help'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
```

The `Text('profile_language_label'.tr(), ...)` line that originally followed stays exactly as-is, unchanged, right after this new block.

- [ ] **Step 5: Add the 4 routes to app_router.dart**

In `app/lib/core/router/app_router.dart`, add this import after the `requirement/requirement_detail_screen.dart` import (last in the alphabetically-ordered block, since "settings" sorts after "requirement"):

```dart
import '../../features/settings/account_settings_screen.dart';
import '../../features/settings/help_screen.dart';
import '../../features/settings/notification_settings_screen.dart';
import '../../features/settings/privacy_screen.dart';
```

After the `GoRoute(path: '/reviews', builder: (context, state) => const ReviewsScreen())` line, before the closing `],` of the `routes:` list, add:

```dart
      GoRoute(path: '/settings/notification', builder: (context, state) => const NotificationSettingsScreen()),
      GoRoute(path: '/settings/account', builder: (context, state) => const AccountSettingsScreen()),
      GoRoute(path: '/settings/privacy', builder: (context, state) => const PrivacyScreen()),
      GoRoute(path: '/settings/help', builder: (context, state) => const HelpScreen()),
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/profile/profile_screen_test.dart -v`
Expected: PASS (all existing tests plus the new one).

- [ ] **Step 7: Run full suite and analyze**

Run:
```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test
flutter analyze
```
Expected: all tests pass (real count — should be 158 existing + this plan's new tests: 3 model + 2 notification + 3 account + 2 static + 1 profile-wiring = 14 new, so 172 total, but confirm the real number from actual output rather than trusting this arithmetic), `No issues found!`.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/profile/profile_screen.dart app/lib/core/router/app_router.dart app/test/features/profile/profile_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: wire Settings list into ProfileScreen and router"
```

---

## Self-Review Notes

- **Spec coverage:** all 4 mockup rows covered (Task 4 Notification, Task 5 Account, Task 6 Privacy + Help), migration is additive-only per the design doc's constraint (Task 1), `ProfileScreen` insertion point matches the mockup's layout order (Task 7), l10n parity maintained across all 7 tasks.
- **Placeholder scan:** no TBD/TODO, every step has real code, every test has real assertions.
- **Type consistency:** `NotificationPreferences`/`IdentityInfo` field names and `fromJson` keys are identical between Task 2 (definition), Task 3 (repository/providers), Tasks 4/5 (screens) — verified by re-reading each task's code side by side while writing this plan.
