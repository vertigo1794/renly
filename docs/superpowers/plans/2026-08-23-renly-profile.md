# Profile Management (Core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a negotiator view their own profile (registration number, agency, territory, specialisation, verification status, active-listing and closed-deal counts), edit territory and property specialisation, switch the app's language, and sign out — all from one new screen reached via an icon on `HomePlaceholderScreen`'s app bar.

**Architecture:** A new `profile` feature composing a `negotiator` row read plus a follow-up `agency` name lookup, with no new RLS policies (only a new column and a column-scoped UPDATE grant). No new external tech, no Realtime — plain fetch/update, matching every pre-Messaging module.

**Tech Stack:** Flutter, Riverpod, supabase_flutter, easy_localization (EN/MS), go_router. No new dependencies.

## Global Constraints

- Only `territory` and `property_specialisation` are ever client-writable on `negotiator` — `ren_number`, `agency_id`, `full_name`, `verification_status`, `subscription_tier` stay read-only in this milestone, matching the RLS grant added in Task 1.
- `ProfileRepository` is untested directly (Supabase-calling code) — established project convention. `Profile.fromJson` gets a real unit test. `ProfileScreen` gets widget tests via provider override.
- `currentNegotiatorIdProvider`: add another own copy in `profile_providers.dart`, same per-feature-file duplication convention as every sibling feature.
- `myProfileProvider` and `profileCountsProvider` must be `.autoDispose` (no `.family` needed — there is only ever one "my profile" per session).
- Do NOT modify `AuthRepository.fetchOwnNegotiator`, the `Negotiator` model, or `app_router.dart`'s redirect logic — this feature is additive only.
- l10n: every new user-facing string needs both an `en.json` and `ms.json` entry, same `easy_localization` key-based pattern as every prior milestone.

---

### Task 1: Supabase Migration SQL (0010_profile.sql)

**Files:**
- Create: `supabase/migrations/0010_profile.sql`
- Modify: `app/README.md` (append a "Milestone 9 setup (profile)" section after the Milestone 8 section)

**Interfaces:**
- Consumes: `negotiator` table (from `0001_auth_verification.sql`), its existing `negotiator_select_own`/`negotiator_update_own` RLS policies.
- Produces: `negotiator.property_specialisation` column, and a column-scoped UPDATE grant covering `(territory, property_specialisation)` — used by Task 3's `ProfileRepository`.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0010_profile.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0009.
--
-- Written to be re-runnable from the start, same pattern as every prior
-- migration.

alter table negotiator add column if not exists property_specialisation text;

-- Territory and property_specialisation are the only user-editable fields
-- on this table. UPDATE was fully revoked from negotiator during
-- Auth+Verification's Critical self-approval fix (0002_rls_hardening.sql)
-- -- this is the first UPDATE access the client has had on this table
-- since, and it's scoped to exactly these two columns. No RLS policy
-- change is needed: negotiator_update_own (from 0001) already gates which
-- ROW can be touched (auth.uid() = negotiator_id); this grant is what
-- makes any UPDATE possible at all again, restricted to which COLUMNS.
revoke update on negotiator from authenticated;
grant update (territory, property_specialisation) on negotiator to authenticated;
```

- [ ] **Step 2: Append README setup section**

Read `app/README.md`, find the "Milestone 8 setup (agreement)" section, and append immediately after it:

```markdown
### Milestone 9 setup (profile)

Run `supabase/migrations/0010_profile.sql` in the Supabase SQL Editor after 0001-0009. This adds `negotiator.property_specialisation` and grants authenticated users UPDATE on exactly `(territory, property_specialisation)` -- no other manual dashboard step.
```

- [ ] **Step 3: Verify with grep**

Run:
```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
grep -c "alter table negotiator add column" supabase/migrations/0010_profile.sql
grep -c "grant update (territory, property_specialisation)" supabase/migrations/0010_profile.sql
```
Expected: `1`, `1`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0010_profile.sql app/README.md
git commit -m "feat: add profile Supabase migration - property_specialisation column and UPDATE grant"
```

---

### Task 2: Profile model + unit test

**Files:**
- Create: `app/lib/features/profile/models/profile.dart`
- Test: `app/test/features/profile/models/profile_test.dart`

**Interfaces:**
- Consumes: nothing (leaf model).
- Produces: `Profile` class with `negotiatorId`, `fullName`, `renNumber` (`String?`), `agencyName` (`String?`), `territory` (`String?`), `propertySpecialisation` (`String?`), `verificationStatus` fields and `Profile.fromJson(Map<String, dynamic> json, {String? agencyName})` factory — used by Task 3's `ProfileRepository`, Task 4's providers, and Task 5's `ProfileScreen`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/profile/models/profile_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/profile/models/profile.dart';

void main() {
  group('Profile.fromJson', () {
    test('parses negotiator columns with no agency name provided', () {
      final profile = Profile.fromJson({
        'negotiator_id': 'n-1',
        'full_name': 'Aiman Yusof',
        'ren_number': '12345',
        'territory': 'Petaling Jaya',
        'property_specialisation': 'Residential',
        'verification_status': 'approved',
      });

      expect(profile.negotiatorId, 'n-1');
      expect(profile.fullName, 'Aiman Yusof');
      expect(profile.renNumber, '12345');
      expect(profile.agencyName, isNull);
      expect(profile.territory, 'Petaling Jaya');
      expect(profile.propertySpecialisation, 'Residential');
      expect(profile.verificationStatus, 'approved');
    });

    test('takes agencyName as a separate named parameter, not from json', () {
      final profile = Profile.fromJson(
        {
          'negotiator_id': 'n-2',
          'full_name': 'Siti Noraini',
          'ren_number': null,
          'territory': null,
          'property_specialisation': null,
          'verification_status': 'pending',
        },
        agencyName: 'Prestige Property Group',
      );

      expect(profile.agencyName, 'Prestige Property Group');
      expect(profile.renNumber, isNull);
      expect(profile.territory, isNull);
      expect(profile.propertySpecialisation, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/profile/models/profile_test.dart`
Expected: FAIL — `Profile` is not defined (file doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/features/profile/models/profile.dart

/// The current negotiator's own full profile -- composed from `negotiator`
/// plus a follow-up `agency` lookup for the firm name. Deliberately
/// separate from the auth feature's own scoped-down `Negotiator` model
/// (which only carries the 3 fields the router redirect needs).
class Profile {
  final String negotiatorId;
  final String fullName;
  final String? renNumber;
  final String? agencyName;
  final String? territory;
  final String? propertySpecialisation;
  final String verificationStatus;

  const Profile({
    required this.negotiatorId,
    required this.fullName,
    this.renNumber,
    this.agencyName,
    this.territory,
    this.propertySpecialisation,
    required this.verificationStatus,
  });

  /// [agencyName] is passed separately because it comes from a second
  /// composed query (the `agency` table), not a column on `negotiator`
  /// itself -- there is no `agency_name` key in [json].
  factory Profile.fromJson(Map<String, dynamic> json, {String? agencyName}) {
    return Profile(
      negotiatorId: json['negotiator_id'] as String,
      fullName: json['full_name'] as String,
      renNumber: json['ren_number'] as String?,
      agencyName: agencyName,
      territory: json['territory'] as String?,
      propertySpecialisation: json['property_specialisation'] as String?,
      verificationStatus: json['verification_status'] as String,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/profile/models/profile_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/profile/models/profile.dart app/test/features/profile/models/profile_test.dart
git commit -m "feat: add Profile model"
```

---

### Task 3: ProfileRepository

**Files:**
- Create: `app/lib/features/profile/profile_repository.dart`

**Interfaces:**
- Consumes: `Profile`/`Profile.fromJson` (Task 2).
- Produces: `ProfileRepository` with `fetchMyProfile(String negotiatorId) -> Future<Profile>`, `updateProfile({required String negotiatorId, required String? territory, required String? propertySpecialisation}) -> Future<void>`, `countActiveListings(String negotiatorId) -> Future<int>`, `countDealsClosed() -> Future<int>` — used by Task 4's providers.

This repository is NOT unit-tested directly — same established convention as every prior repository (Supabase-calling code). No test file for this task.

- [ ] **Step 1: Write the repository**

```dart
// app/lib/features/profile/profile_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/profile.dart';

/// The only file in this app that talks to Supabase for the profile
/// feature. Composes a follow-up `agency` lookup rather than a join or
/// RPC -- `agency_select_all` already lets any authenticated user read
/// agency rows, so a plain second query is simplest.
class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<Profile> fetchMyProfile(String negotiatorId) async {
    final row = await _client
        .from('negotiator')
        .select()
        .eq('negotiator_id', negotiatorId)
        .single();
    final agencyId = row['agency_id'] as String?;
    String? agencyName;
    if (agencyId != null) {
      final agencyRow = await _client
          .from('agency')
          .select('firm_name')
          .eq('agency_id', agencyId)
          .maybeSingle();
      agencyName = agencyRow?['firm_name'] as String?;
    }
    return Profile.fromJson(row, agencyName: agencyName);
  }

  Future<void> updateProfile({
    required String negotiatorId,
    required String? territory,
    required String? propertySpecialisation,
  }) {
    return _client.from('negotiator').update({
      'territory': territory,
      'property_specialisation': propertySpecialisation,
    }).eq('negotiator_id', negotiatorId);
  }

  Future<int> countActiveListings(String negotiatorId) async {
    final response = await _client
        .from('listing')
        .select('listing_id')
        .eq('negotiator_id', negotiatorId)
        .eq('status', 'active')
        .count(CountOption.exact);
    return response.count;
  }

  /// No negotiator_id filter needed -- agreement_select's RLS already
  /// scopes every visible row to one where the current user is a party
  /// (initiator, or owner of the underlying match's listing/requirement),
  /// so a plain count under that policy is already "my deals."
  Future<int> countDealsClosed() async {
    final response = await _client
        .from('agreement')
        .select('agreement_id')
        .eq('status', 'accepted')
        .count(CountOption.exact);
    return response.count;
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/features/profile/profile_repository.dart
git commit -m "feat: add ProfileRepository"
```

---

### Task 4: profile_providers.dart

**Files:**
- Create: `app/lib/features/profile/profile_providers.dart`

**Interfaces:**
- Consumes: `ProfileRepository` (Task 3); `authStateProvider` (`app/lib/features/auth/auth_providers.dart`, same as every other feature's own `currentNegotiatorIdProvider` copy).
- Produces: `profileRepositoryProvider`, `currentNegotiatorIdProvider` (this feature's own copy), `myProfileProvider = FutureProvider.autoDispose<Profile>`, `profileCountsProvider = FutureProvider.autoDispose<(int, int)>` (a `(activeListings, dealsClosed)` record) — used by Task 5's `ProfileScreen`.

- [ ] **Step 1: Write the providers**

```dart
// app/lib/features/profile/profile_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import 'profile_repository.dart';
import 'models/profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(Supabase.instance.client);
});

/// Same session-state read as the copies in every sibling feature's own
/// providers file -- duplicated here rather than imported, same
/// established reasoning as those files.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// The current negotiator's own profile. autoDispose (not .family -- there
/// is only ever one "my profile" per session, no key needed): a fresh
/// fetch on every ProfileScreen visit is correct here, not a lingering
/// cached value from a prior session.
final myProfileProvider = FutureProvider.autoDispose<Profile>((ref) {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) {
    throw StateError('myProfileProvider watched with no active session');
  }
  return ref.watch(profileRepositoryProvider).fetchMyProfile(negotiatorId);
});

/// (activeListings, dealsClosed) -- both counts fetched concurrently via
/// Future.wait, not sequential awaits, same concurrent-resolution pattern
/// established across every prior milestone's repository code.
final profileCountsProvider = FutureProvider.autoDispose<(int, int)>((ref) async {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) {
    throw StateError('profileCountsProvider watched with no active session');
  }
  final repository = ref.watch(profileRepositoryProvider);
  final results = await Future.wait([
    repository.countActiveListings(negotiatorId),
    repository.countDealsClosed(),
  ]);
  return (results[0], results[1]);
});
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/features/profile/profile_providers.dart
git commit -m "feat: add profile Riverpod providers"
```

---

### Task 5: ProfileScreen + l10n keys

**Files:**
- Create: `app/lib/features/profile/profile_screen.dart`
- Test: `app/test/features/profile/profile_screen_test.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json` (add new keys, see Step 1)

**Interfaces:**
- Consumes: `myProfileProvider`, `profileCountsProvider`, `profileRepositoryProvider`, `currentNegotiatorIdProvider` (Task 4); `Profile` (Task 2).
- Produces: `ProfileScreen` widget — used by Task 6's router wiring.

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`, find the line `"agreement_retry": "Retry"` (the last key in the file) and add a comma after it, then add these new keys immediately after:

```json
  "profile_title": "Profile",
  "profile_ren_number_label": "Registration Number",
  "profile_agency_label": "Agency",
  "profile_territory_label": "Territory",
  "profile_specialisation_label": "Property Specialisation",
  "profile_save": "Save",
  "profile_active_listings_label": "Active Listings",
  "profile_deals_closed_label": "Deals Closed",
  "profile_language_label": "Language",
  "profile_language_en": "English",
  "profile_language_ms": "Bahasa Melayu",
  "profile_sign_out": "Sign Out",
  "profile_status_approved": "Verified",
  "profile_status_pending": "Verification Pending",
  "profile_status_rejected": "Not Verified"
```

In `app/assets/translations/ms.json`, same position (after `"agreement_retry": "Cuba lagi"`), add:

```json
  "profile_title": "Profil",
  "profile_ren_number_label": "Nombor Pendaftaran",
  "profile_agency_label": "Agensi",
  "profile_territory_label": "Kawasan Operasi",
  "profile_specialisation_label": "Kepakaran Hartanah",
  "profile_save": "Simpan",
  "profile_active_listings_label": "Penyenaraian Aktif",
  "profile_deals_closed_label": "Deal Selesai",
  "profile_language_label": "Bahasa",
  "profile_language_en": "English",
  "profile_language_ms": "Bahasa Melayu",
  "profile_sign_out": "Log Keluar",
  "profile_status_approved": "Disahkan",
  "profile_status_pending": "Menunggu Pengesahan",
  "profile_status_rejected": "Tidak Disahkan"
```

- [ ] **Step 2: Write the screen**

```dart
// app/lib/features/profile/profile_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/profile.dart';
import 'profile_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'profile_status_approved'.tr();
      case 'rejected':
        return 'profile_status_rejected'.tr();
      default:
        return 'profile_status_pending'.tr();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final countsAsync = ref.watch(profileCountsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('profile_title'.tr())),
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(child: Text('listing_error_generic'.tr())),
          data: (profile) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.fullName, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Chip(label: Text(_statusLabel(profile.verificationStatus))),
                const SizedBox(height: 12),
                Text('${'profile_ren_number_label'.tr()}: ${profile.renNumber ?? '-'}'),
                const SizedBox(height: 4),
                Text('${'profile_agency_label'.tr()}: ${profile.agencyName ?? '-'}'),
                const SizedBox(height: 20),
                countsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (error, stack) => const SizedBox.shrink(),
                  data: (counts) => Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text('${counts.$1}', style: Theme.of(context).textTheme.headlineSmall),
                                Text('profile_active_listings_label'.tr()),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text('${counts.$2}', style: Theme.of(context).textTheme.headlineSmall),
                                Text('profile_deals_closed_label'.tr()),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _EditForm(profile: profile),
                const SizedBox(height: 20),
                Text('profile_language_label'.tr(), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'en', label: Text('profile_language_en'.tr())),
                    ButtonSegment(value: 'ms', label: Text('profile_language_ms'.tr())),
                  ],
                  selected: {context.locale.languageCode},
                  onSelectionChanged: (selection) => context.setLocale(Locale(selection.first)),
                ),
                const SizedBox(height: 32),
                OutlinedButton(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  child: Text('profile_sign_out'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  late final TextEditingController _territoryController;
  late final TextEditingController _specialisationController;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _territoryController = TextEditingController(text: widget.profile.territory ?? '');
    _specialisationController = TextEditingController(text: widget.profile.propertySpecialisation ?? '');
  }

  @override
  void dispose() {
    _territoryController.dispose();
    _specialisationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final negotiatorId = ref.read(currentNegotiatorIdProvider);
    if (negotiatorId == null) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            negotiatorId: negotiatorId,
            territory: _territoryController.text.trim().isEmpty ? null : _territoryController.text.trim(),
            propertySpecialisation:
                _specialisationController.text.trim().isEmpty ? null : _specialisationController.text.trim(),
          );
      ref.invalidate(myProfileProvider);
    } catch (_) {
      if (mounted) setState(() => _submitError = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _territoryController,
          decoration: InputDecoration(labelText: 'profile_territory_label'.tr()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _specialisationController,
          decoration: InputDecoration(labelText: 'profile_specialisation_label'.tr()),
        ),
        if (_submitError != null) ...[
          const SizedBox(height: 8),
          Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _submitting ? null : _save,
          child: Text('profile_save'.tr()),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Write the widget test**

```dart
// app/test/features/profile/profile_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/profile/models/profile.dart';
import 'package:renly/features/profile/profile_providers.dart';
import 'package:renly/features/profile/profile_screen.dart';

const _fixtureProfile = Profile(
  negotiatorId: 'n-1',
  fullName: 'Aiman Yusof',
  renNumber: '12345',
  agencyName: 'Prestige Property Group',
  territory: 'Petaling Jaya',
  propertySpecialisation: 'Residential',
  verificationStatus: 'approved',
);

Widget _wrap(GoRouter router, {Profile? profile, (int, int)? counts}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      myProfileProvider.overrideWith((ref) async => profile ?? _fixtureProfile),
      profileCountsProvider.overrideWith((ref) async => counts ?? (5, 3)),
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

  testWidgets('renders profile fields and counts', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Aiman Yusof'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Registration Number: 12345'), findsOneWidget);
    expect(find.text('Agency: Prestige Property Group'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('language switcher and sign out button are present', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('English'), findsOneWidget);
    expect(find.text('Bahasa Melayu'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
  });

  testWidgets('shows pending status label for a pending profile', (tester) async {
    const pendingProfile = Profile(
      negotiatorId: 'n-1',
      fullName: 'Aiman Yusof',
      verificationStatus: 'pending',
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, profile: pendingProfile));
    await tester.pumpAndSettle();

    expect(find.text('Verification Pending'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run the tests**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/profile/profile_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/profile/profile_screen.dart app/test/features/profile/profile_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add ProfileScreen with widget tests and l10n keys"
```

---

### Task 6: Wire access icon into HomePlaceholderScreen + router

**Files:**
- Modify: `app/lib/features/auth/home_placeholder_screen.dart`
- Modify: `app/lib/core/router/app_router.dart`
- Modify: `app/test/features/auth/home_placeholder_screen_test.dart`

**Interfaces:**
- Consumes: `ProfileScreen` (Task 5); existing `HomePlaceholderScreen` structure (unchanged body).
- Produces: nothing new consumed by later tasks — this is the last task.

- [ ] **Step 1: Add the import and route to app_router.dart**

In `app/lib/core/router/app_router.dart`, insert this import after the `matching/my_matches_screen.dart` import and before the `requirement/my_requirements_screen.dart` import (alphabetical: `profile/` sorts after `matching/`, before `requirement/`):

```dart
import '../../features/profile/profile_screen.dart';
```

Then add this route as the new last entry in the `routes:` list, immediately after the existing `GoRoute(path: '/messages/:requestId', ...)` route:

```dart
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
```

- [ ] **Step 2: Add the profile icon to HomePlaceholderScreen**

In `app/lib/features/auth/home_placeholder_screen.dart`, `package:go_router/go_router.dart` is already imported (it's used by the existing link buttons' `context.push(...)` calls) — no new import needed for this step.

Change the `Scaffold(` opening to add an `appBar:`:

```dart
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: SafeArea(
```

Nothing else in the file changes — the body's `Column` of 6 link buttons stays exactly as-is.

- [ ] **Step 3: Add a widget test for the profile icon**

In `app/test/features/auth/home_placeholder_screen_test.dart`, add this test inside `main()`, after the existing tests. Add `/profile` to this test's own router (the existing tests' routers don't need `/profile` added, since they never tap the icon):

```dart
  testWidgets('tapping the profile icon navigates to /profile', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePlaceholderScreen()),
      GoRoute(path: '/marketplace', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-inventory', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/requirement-board', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requirements', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-matches', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/my-requests', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/profile', builder: (context, state) => const Text('profile-screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();

    expect(find.text('profile-screen'), findsOneWidget);
  });
```

- [ ] **Step 4: Run the tests**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/auth/home_placeholder_screen_test.dart`
Expected: PASS (8 tests — the 7 existing plus 1 new).

- [ ] **Step 5: Run the full suite to confirm zero regression**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test`
Expected: all tests pass (prior suite count 144 + this plan's new tests: Task 2's 2 + Task 5's 3 + Task 6's 1 = 6 new tests = 150 total).

- [ ] **Step 6: Run flutter analyze**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter analyze`
Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/auth/home_placeholder_screen.dart app/lib/core/router/app_router.dart app/test/features/auth/home_placeholder_screen_test.dart
git commit -m "feat: add profile icon to HomePlaceholderScreen and /profile route"
```
