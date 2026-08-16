# renly Auth + Verification Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take a negotiator from "never opened renly" through account creation (email/password + personal + professional details) to "verification pending" — matching the Stitch mockups, backed by real Supabase tables/RLS/storage, with login routing an already-registered negotiator to the right screen.

**Architecture:** Screens under `lib/features/auth/` call a single `AuthRepository` for every Supabase read/write (no screen touches `Supabase.instance.client` directly). Form validation is pure, dependency-free Dart (`AuthValidation`) so it's unit-testable without a Supabase connection. `app_router.dart` becomes a `Provider<GoRouter>` gated by a pure `computeAuthRedirect` function, watching an `authStateProvider` stream so navigation reacts to sign-in/sign-out.

**Tech Stack:** Flutter/Dart, Riverpod, `supabase_flutter`, `go_router`, `easy_localization`, `google_fonts`, `image_picker` (new dependency, added in Task 9).

## Global Constraints

- No screen calls `Supabase.instance.client` directly — always through `AuthRepository`.
- Every new UI string goes into BOTH `app/assets/translations/en.json` and `app/assets/translations/ms.json` with matching keys — `app/test/l10n/translations_test.dart` (from Milestone 1) already asserts key-set parity across both files and will catch a mismatch.
- Field labels that already exist as Malay text in the Stitch mockups (`Nama Penuh`, `Nombor Kad Pengenalan (IC)`, `Nombor Telefon`, `Nombor REN`, `Nama Agensi`) are ported verbatim into BOTH locale files unchanged — the mockup's own design choice uses these as fixed official terms regardless of UI language, don't retranslate them.
- Colors/fonts/spacing come from `AppColors`/`AppTheme` (Milestone 1, already built) — no new hardcoded hex values except where a screen's background is literally `AppColors.primaryContainer` (the mockup's lime `#D4FF00`, already defined).
- Widget tests follow the Milestone-1 pattern exactly: `testWidgets` (not bare `test`) for anything touching `AppTheme`/`GoogleFonts`, `GoogleFonts.config.allowRuntimeFetching = false` and `SharedPreferences.setMockInitialValues({})` in `setUpAll`, wrapped in `EasyLocalization` + `MaterialApp`.
- No screen or test ever calls `Supabase.initialize` — Milestone 1 established this boundary (main() is untested; everything else is designed to not need a live Supabase connection to compile/test). `AuthRepository` takes a `SupabaseClient` via constructor injection so it's swappable, but this plan does not write Supabase-mocking tests for it (documented, accepted gap — same as Milestone 1's `main.dart`).
- SQL migration and two Supabase dashboard settings are manual, user-performed steps (Task 1) — this session has no DB credentials or dashboard access.
- Flutter is on PATH via `export PATH="$HOME/development/flutter/bin:$PATH"` — run first if `flutter` isn't found. All commands below assume this has been run and `cd` is `app/` unless stated otherwise.
- **Tasks 6, 7, 8, 9: do NOT run the full `flutter test` suite before committing.** Task 5 intentionally leaves `app/lib/core/router/app_router.dart` importing a now-moved file, so the whole-project suite fails from Task 5 until Task 10 fixes the router — this is expected, not a bug to chase. Only run the exact test file(s) each task's own steps name.

---

### Task 1: Supabase migration SQL + manual setup instructions

**Files:**
- Create: `supabase/migrations/0001_auth_verification.sql`
- Modify: `app/README.md` (append a "Milestone 2 setup" section)

**Interfaces:**
- Produces: the `negotiator`, `agency`, `verification_record` tables and `ren-tags` storage bucket that every later task's `AuthRepository` calls assume exist. No code depends on this at compile time — Flutter code compiles and tests pass without the SQL ever being run — but the app will get Postgrest errors on every write until the user runs it.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0001_auth_verification.sql
-- Run this once in the Supabase project's SQL Editor (Dashboard -> SQL Editor -> New query -> paste -> Run).

-- agency
create table agency (
  agency_id uuid primary key default gen_random_uuid(),
  firm_name text not null,
  registration_no text,
  address text,
  created_at timestamptz not null default now()
);
create unique index agency_firm_name_lower_idx on agency (lower(trim(firm_name)));

-- negotiator (negotiator_id IS the Supabase Auth user id -- 1:1 with auth.users)
create table negotiator (
  negotiator_id uuid primary key references auth.users(id) on delete cascade,
  agency_id uuid references agency(agency_id),
  full_name text not null,
  ic_number text not null,
  phone_number text not null,
  ren_number text,
  territory text,
  verification_status text not null default 'pending'
    check (verification_status in ('pending', 'approved', 'rejected')),
  subscription_tier text not null default 'free'
    check (subscription_tier in ('free', 'professional')),
  created_at timestamptz not null default now()
);

-- verification_record (immutable audit trail -- insert/select only, no update/delete policy)
create table verification_record (
  record_id uuid primary key default gen_random_uuid(),
  negotiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  method text not null default 'manual_registration',
  tag_photo_url text,
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  outcome text not null default 'pending'
    check (outcome in ('pending', 'approved', 'rejected'))
);

-- RLS: every table is deny-by-default the moment RLS is enabled; each gets an explicit policy.
alter table negotiator enable row level security;
create policy negotiator_select_own on negotiator for select using (auth.uid() = negotiator_id);
create policy negotiator_insert_own on negotiator for insert with check (auth.uid() = negotiator_id);
create policy negotiator_update_own on negotiator for update using (auth.uid() = negotiator_id);

alter table verification_record enable row level security;
create policy verification_record_select_own on verification_record for select using (auth.uid() = negotiator_id);
create policy verification_record_insert_own on verification_record for insert with check (auth.uid() = negotiator_id);

alter table agency enable row level security;
create policy agency_select_all on agency for select using (true);
create policy agency_insert_authenticated on agency for insert to authenticated with check (true);

-- Storage: private bucket for REN tag photos, path convention {auth.uid()}/tag.jpg
insert into storage.buckets (id, name, public) values ('ren-tags', 'ren-tags', false)
  on conflict (id) do nothing;

create policy ren_tags_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'ren-tags' and (storage.foldername(name))[1] = auth.uid()::text);
create policy ren_tags_select_own on storage.objects for select to authenticated
  using (bucket_id = 'ren-tags' and (storage.foldername(name))[1] = auth.uid()::text);
```

- [ ] **Step 2: Verify the file is well-formed**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
grep -c "^create table" supabase/migrations/0001_auth_verification.sql
grep -c "^create policy" supabase/migrations/0001_auth_verification.sql
```
Expected: `3` (agency, negotiator, verification_record) and `7` (negotiator x3, verification_record x2, agency x2 -- storage policies use `create policy` too so recount: negotiator_select_own, negotiator_insert_own, negotiator_update_own, verification_record_select_own, verification_record_insert_own, agency_select_all, agency_insert_authenticated, ren_tags_insert_own, ren_tags_select_own = 9). Adjust the expectation to `9` if your count differs from a miscount above -- the authoritative check is that every table referenced in a policy (`negotiator`, `verification_record`, `agency`, `storage.objects`) has at least one `select`-capable policy and `negotiator`/`verification_record`/`agency` each have an `insert`-capable policy, which a visual read of the file confirms.

- [ ] **Step 3: Append manual setup instructions to app/README.md**

Read the current `app/README.md` first (it has a Milestone-1 setup section from the scaffold plan). Append a new section after the existing content:

```markdown

## Milestone 2 setup (auth + verification)

Two one-time steps in the Supabase dashboard, in addition to the `.env` setup above:

1. **Run the migration.** Open the Supabase dashboard for this project -> SQL Editor -> New query. Paste the entire contents of `supabase/migrations/0001_auth_verification.sql` (repo root, not inside `app/`) and click Run. This creates the `negotiator`, `agency`, and `verification_record` tables, their Row-Level Security policies, and the `ren-tags` storage bucket.
2. **Disable email confirmation.** Dashboard -> Authentication -> Sign In / Providers -> Email -> turn off "Confirm email". Without this, `signUp()` requires the user to click a confirmation link in their inbox before a session is active, which would strand Step 1 of registration before Step 2 can run. This is fine for development; revisit before any real production launch.

Registration won't work (Postgrest errors on every insert) until step 1 is done. Login will hang waiting for email confirmation until step 2 is done.
```

- [ ] **Step 4: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add supabase/migrations/0001_auth_verification.sql app/README.md
git commit -m "feat: add auth+verification Supabase migration and setup docs"
```

---

### Task 2: AuthValidation + Negotiator model (pure, TDD)

**Files:**
- Create: `app/lib/features/auth/auth_validation.dart`
- Create: `app/lib/features/auth/models/negotiator.dart`
- Test: `app/test/features/auth/auth_validation_test.dart`
- Test: `app/test/features/auth/models/negotiator_test.dart`

**Interfaces:**
- Produces: `AuthValidation.isValidEmail(String)`, `.isValidPassword(String)`, `.passwordsMatch(String, String)`, `.isValidIcNumber(String)`, `.isValidPhoneNumber(String)` — all `static bool`, all pure. `Negotiator` class with `negotiatorId`, `fullName`, `verificationStatus` (all `String`, all `final`) and `Negotiator.fromJson(Map<String, dynamic>)`. Every later screen/repository task imports these.

- [ ] **Step 1: Write the failing validation test**

```dart
// app/test/features/auth/auth_validation_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/auth/auth_validation.dart';

void main() {
  group('AuthValidation.isValidEmail', () {
    test('accepts a normal email', () {
      expect(AuthValidation.isValidEmail('agent@renly.my'), isTrue);
    });
    test('rejects missing @', () {
      expect(AuthValidation.isValidEmail('agent.renly.my'), isFalse);
    });
    test('rejects missing domain dot', () {
      expect(AuthValidation.isValidEmail('agent@renly'), isFalse);
    });
  });

  group('AuthValidation.isValidPassword', () {
    test('accepts 8+ characters', () {
      expect(AuthValidation.isValidPassword('password1'), isTrue);
    });
    test('rejects under 8 characters', () {
      expect(AuthValidation.isValidPassword('short1'), isFalse);
    });
  });

  group('AuthValidation.passwordsMatch', () {
    test('true when identical and non-empty', () {
      expect(AuthValidation.passwordsMatch('password1', 'password1'), isTrue);
    });
    test('false when different', () {
      expect(AuthValidation.passwordsMatch('password1', 'password2'), isFalse);
    });
    test('false when both empty', () {
      expect(AuthValidation.passwordsMatch('', ''), isFalse);
    });
  });

  group('AuthValidation.isValidIcNumber', () {
    test('accepts NNNNNN-NN-NNNN format', () {
      expect(AuthValidation.isValidIcNumber('900101-14-5555'), isTrue);
    });
    test('rejects missing dashes', () {
      expect(AuthValidation.isValidIcNumber('900101145555'), isFalse);
    });
    test('rejects wrong segment lengths', () {
      expect(AuthValidation.isValidIcNumber('900101-1-5555'), isFalse);
    });
  });

  group('AuthValidation.isValidPhoneNumber', () {
    test('accepts 012-3456789 format', () {
      expect(AuthValidation.isValidPhoneNumber('012-3456789'), isTrue);
    });
    test('accepts 3-digit prefix', () {
      expect(AuthValidation.isValidPhoneNumber('016-3456789'), isTrue);
    });
    test('rejects missing dash', () {
      expect(AuthValidation.isValidPhoneNumber('0123456789'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/auth/auth_validation_test.dart
```
Expected: FAIL — `package:renly/features/auth/auth_validation.dart` not found.

- [ ] **Step 3: Implement AuthValidation**

```dart
// app/lib/features/auth/auth_validation.dart

/// Pure form-validation logic for the auth/registration screens. No
/// Flutter, no Supabase -- fully unit-testable.
class AuthValidation {
  AuthValidation._();

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _icPattern = RegExp(r'^\d{6}-\d{2}-\d{4}$');
  static final RegExp _phonePattern = RegExp(r'^\d{2,3}-\d{6,8}$');

  static bool isValidEmail(String email) => _emailPattern.hasMatch(email);

  static bool isValidPassword(String password) => password.length >= 8;

  static bool passwordsMatch(String password, String confirmPassword) =>
      password.isNotEmpty && password == confirmPassword;

  static bool isValidIcNumber(String icNumber) => _icPattern.hasMatch(icNumber);

  static bool isValidPhoneNumber(String phoneNumber) => _phonePattern.hasMatch(phoneNumber);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/features/auth/auth_validation_test.dart
```
Expected: `00:0X +14: All tests passed!`

- [ ] **Step 5: Write the failing Negotiator model test**

```dart
// app/test/features/auth/models/negotiator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/auth/models/negotiator.dart';

void main() {
  group('Negotiator.fromJson', () {
    test('parses a full row', () {
      final negotiator = Negotiator.fromJson({
        'negotiator_id': 'abc-123',
        'full_name': 'Aiman Yusof',
        'verification_status': 'pending',
      });

      expect(negotiator.negotiatorId, 'abc-123');
      expect(negotiator.fullName, 'Aiman Yusof');
      expect(negotiator.verificationStatus, 'pending');
    });
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

```bash
flutter test test/features/auth/models/negotiator_test.dart
```
Expected: FAIL — `package:renly/features/auth/models/negotiator.dart` not found.

- [ ] **Step 7: Implement Negotiator**

```dart
// app/lib/features/auth/models/negotiator.dart

/// A row from the `negotiator` table, scoped to fields this app's auth
/// flow needs (not every ERD column).
class Negotiator {
  final String negotiatorId;
  final String fullName;
  final String verificationStatus;

  const Negotiator({
    required this.negotiatorId,
    required this.fullName,
    required this.verificationStatus,
  });

  factory Negotiator.fromJson(Map<String, dynamic> json) {
    return Negotiator(
      negotiatorId: json['negotiator_id'] as String,
      fullName: json['full_name'] as String,
      verificationStatus: json['verification_status'] as String,
    );
  }
}
```

- [ ] **Step 8: Run test to verify it passes**

```bash
flutter test test/features/auth/models/negotiator_test.dart
```
Expected: `00:0X +1: All tests passed!`

- [ ] **Step 9: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/auth/auth_validation.dart app/lib/features/auth/models/negotiator.dart app/test/features/auth/auth_validation_test.dart app/test/features/auth/models/negotiator_test.dart
git commit -m "feat: add AuthValidation and Negotiator model"
```

---

### Task 3: AuthRepository (Supabase I/O layer)

**Files:**
- Create: `app/lib/features/auth/auth_repository.dart`

**Interfaces:**
- Consumes: `Negotiator` (Task 2, for `fetchOwnNegotiator`'s return type).
- Produces: `AuthRepository(SupabaseClient client)` with methods `signUp`, `insertNegotiator`, `findOrCreateAgency`, `uploadTagPhoto`, `completeProfessionalDetails`, `insertVerificationRecord`, `signIn`, `fetchOwnNegotiator` — every later screen task calls these, never `Supabase.instance.client` directly.

No TDD for this task (documented in Global Constraints: Supabase-calling code isn't unit-tested in this plan, same boundary Milestone 1 drew around `main.dart`). Verify with `flutter analyze` only.

- [ ] **Step 1: Implement AuthRepository**

```dart
// app/lib/features/auth/auth_repository.dart
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/negotiator.dart';

/// The only file in this app that talks to Supabase for auth/registration.
/// Screens call these methods; nothing else touches `SupabaseClient` for
/// this feature.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Future<User> signUp({required String email, required String password}) async {
    final response = await _client.auth.signUp(email: email, password: password);
    final user = response.user;
    if (user == null) {
      throw StateError('Sign up succeeded but no user was returned.');
    }
    return user;
  }

  Future<void> insertNegotiator({
    required String negotiatorId,
    required String fullName,
    required String icNumber,
    required String phoneNumber,
  }) {
    return _client.from('negotiator').insert({
      'negotiator_id': negotiatorId,
      'full_name': fullName,
      'ic_number': icNumber,
      'phone_number': phoneNumber,
    });
  }

  /// Finds an existing agency by case-insensitive name match, or creates
  /// one. Not atomic (select-then-insert) -- the DB's unique index on
  /// `lower(trim(firm_name))` is the backstop against a race between two
  /// concurrent registrations picking the same new agency name; a race
  /// surfaces as a Postgrest unique-violation the caller can ask the user
  /// to retry, which is an acceptable rare-edge-case for this milestone.
  Future<String> findOrCreateAgency(String firmName) async {
    final normalized = firmName.trim();
    final existing = await _client
        .from('agency')
        .select('agency_id')
        .ilike('firm_name', normalized)
        .maybeSingle();
    if (existing != null) {
      return existing['agency_id'] as String;
    }
    final inserted = await _client
        .from('agency')
        .insert({'firm_name': normalized})
        .select('agency_id')
        .single();
    return inserted['agency_id'] as String;
  }

  Future<String> uploadTagPhoto({
    required String negotiatorId,
    required Uint8List bytes,
  }) async {
    final path = '$negotiatorId/tag.jpg';
    await _client.storage.from('ren-tags').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }

  Future<void> completeProfessionalDetails({
    required String negotiatorId,
    required String renNumber,
    required String agencyId,
  }) {
    return _client.from('negotiator').update({
      'ren_number': renNumber,
      'agency_id': agencyId,
    }).eq('negotiator_id', negotiatorId);
  }

  Future<void> insertVerificationRecord({
    required String negotiatorId,
    required String tagPhotoUrl,
  }) {
    return _client.from('verification_record').insert({
      'negotiator_id': negotiatorId,
      'tag_photo_url': tagPhotoUrl,
    });
  }

  Future<AuthResponse> signIn({required String email, required String password}) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Returns null if the caller has an auth session but no `negotiator`
  /// row yet (e.g. the app was killed between signUp() and Task 8's
  /// insertNegotiator() call during a previous attempt).
  Future<Negotiator?> fetchOwnNegotiator(String negotiatorId) async {
    final row = await _client
        .from('negotiator')
        .select('negotiator_id, full_name, verification_status')
        .eq('negotiator_id', negotiatorId)
        .maybeSingle();
    if (row == null) return null;
    return Negotiator.fromJson(row);
  }
}
```

- [ ] **Step 2: Verify it compiles cleanly**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter analyze lib/features/auth/auth_repository.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/auth/auth_repository.dart
git commit -m "feat: add AuthRepository (Supabase I/O for auth/registration)"
```

---

### Task 4: auth_providers.dart (Riverpod wiring)

**Files:**
- Create: `app/lib/features/auth/auth_providers.dart`

**Interfaces:**
- Consumes: `AuthRepository` (Task 3), `Negotiator` (Task 2).
- Produces: `authRepositoryProvider` (`Provider<AuthRepository>`), `authStateProvider` (`StreamProvider<AuthState>`, wraps `Supabase.instance.client.auth.onAuthStateChange`) — Task 10's router watches this to gate navigation. `negotiatorProfileProvider` (`FutureProvider.family<Negotiator?, String>`, keyed by `negotiatorId`) — Task 7's `LoginScreen` uses this indirectly via `authRepositoryProvider` (screens call the repository method directly inside their submit handlers rather than watching this provider reactively, since the fetch only happens once right after a successful login, not continuously).

No TDD for this task — it's Riverpod provider wiring around Supabase singletons, same untestable-without-mocking boundary as Task 3. Verify with `flutter analyze`.

- [ ] **Step 1: Implement auth_providers.dart**

```dart
// app/lib/features/auth/auth_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';
import 'models/negotiator.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(Supabase.instance.client);
});

/// Emits on every sign-in/sign-out. `onAuthStateChange` emits the current
/// session state immediately on subscribe, so this has a value as soon as
/// the app starts (not stuck in "loading" until the first real event).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final negotiatorProfileProvider = FutureProvider.family<Negotiator?, String>((ref, negotiatorId) {
  return ref.watch(authRepositoryProvider).fetchOwnNegotiator(negotiatorId);
});
```

- [ ] **Step 2: Verify it compiles cleanly**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter analyze lib/features/auth/auth_providers.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/auth/auth_providers.dart
git commit -m "feat: add auth Riverpod providers"
```

---

### Task 5: Fold verification_pending_screen into features/auth/

**Files:**
- Modify (move): `app/lib/features/verification/verification_pending_screen.dart` → `app/lib/features/auth/verification_pending_screen.dart`
- Modify (move): `app/test/features/verification/verification_pending_screen_test.dart` → `app/test/features/auth/verification_pending_screen_test.dart`
- Delete: `app/lib/features/verification/` (now empty)
- Delete: `app/test/features/verification/` (now empty)

**Interfaces:**
- No signature changes — `VerificationPendingScreen` (class name, constructor, `build()`) stays identical. Only its file location and package-import path change. Task 10's router imports it from the new path.

This is a pure move (settles the design-doc drift the Milestone-1 review flagged), not a rewrite — the file's content is unchanged.

- [ ] **Step 1: Move the screen file**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
mkdir -p lib/features/auth
git mv lib/features/verification/verification_pending_screen.dart lib/features/auth/verification_pending_screen.dart
```

- [ ] **Step 2: Move the test file and fix its import**

```bash
mkdir -p test/features/auth
git mv test/features/verification/verification_pending_screen_test.dart test/features/auth/verification_pending_screen_test.dart
```

Edit `test/features/auth/verification_pending_screen_test.dart`: change the import line from
```dart
import 'package:renly/features/verification/verification_pending_screen.dart';
```
to
```dart
import 'package:renly/features/auth/verification_pending_screen.dart';
```

- [ ] **Step 3: Remove the now-empty verification directories**

```bash
rmdir lib/features/verification 2>/dev/null; rmdir test/features/verification 2>/dev/null
```
(If either `rmdir` fails because the directory still has files, stop and check what's left — this task should leave both directories empty and gone, nothing else should have been in them.)

- [ ] **Step 4: Run the moved test to confirm it still passes**

```bash
flutter test test/features/auth/verification_pending_screen_test.dart
```
Expected: `00:0X +1: All tests passed!` (same single test as Milestone 1, just relocated).

- [ ] **Step 5: Note — do not update app_router.dart or main.dart yet**

Task 10 rewires the router to import from the new path. Until then, `app/lib/core/router/app_router.dart` still imports the OLD path (`features/verification/...`), which no longer exists — this means `flutter analyze` on the whole project will show one error after this task, and `flutter run`/`flutter test` on the full suite will fail until Task 10. That's expected and fine: each task's own verification step here only runs the one test file above, not the whole suite. Do not attempt to fix the router in this task — that's Task 10's job, once `LoginScreen`/`AuthSelectionScreen`/etc. exist to route to.

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add -A
git commit -m "refactor: fold verification_pending_screen into features/auth/"
```

---

### Task 6: AuthSelectionScreen

**Files:**
- Create: `app/lib/features/auth/auth_selection_screen.dart`
- Test: `app/test/features/auth/auth_selection_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `AppColors`, `AppTheme` (Milestone 1). Navigates via `context.push('/register/personal')` and `context.push('/login')` — string routes only, no dependency on those screens' classes existing yet.
- Produces: `AuthSelectionScreen` (`StatelessWidget`, no constructor params beyond `key`) — Task 10's router uses it as the `/` route.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/auth/auth_selection_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/auth/auth_selection_screen.dart';

Widget _wrap(GoRouter router) {
  return EasyLocalization(
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
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('renders tagline and both action buttons', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthSelectionScreen()),
      GoRoute(path: '/register/personal', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/login', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Collaborate smarter, close faster.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Create account'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Log In'), findsOneWidget);
  });

  testWidgets('tapping Create account navigates to /register/personal', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthSelectionScreen()),
      GoRoute(path: '/register/personal', builder: (context, state) => const Text('personal-step')),
      GoRoute(path: '/login', builder: (context, state) => const Placeholder()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('personal-step'), findsOneWidget);
  });

  testWidgets('tapping Log In navigates to /login', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthSelectionScreen()),
      GoRoute(path: '/register/personal', builder: (context, state) => const Placeholder()),
      GoRoute(path: '/login', builder: (context, state) => const Text('login-screen')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Log In'));
    await tester.pumpAndSettle();

    expect(find.text('login-screen'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/auth/auth_selection_screen_test.dart
```
Expected: FAIL — `package:renly/features/auth/auth_selection_screen.dart` not found (and the translation keys don't exist yet either, but the missing-file compile error is what you'll see first).

- [ ] **Step 3: Add the translation keys**

In `app/assets/translations/en.json`, add (keep existing keys, add these):
```json
  "auth_tagline": "Collaborate smarter, close faster.",
  "auth_create_account": "Create account",
  "auth_log_in": "Log In"
```

In `app/assets/translations/ms.json`, add:
```json
  "auth_tagline": "Berkolaborasi lebih bijak, urus niaga lebih pantas.",
  "auth_create_account": "Cipta akaun",
  "auth_log_in": "Log Masuk"
```

- [ ] **Step 4: Implement AuthSelectionScreen**

```dart
// app/lib/features/auth/auth_selection_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

/// Ports stitch_renly_property_agent_network/login_register_selection_english_official_style.
class AuthSelectionScreen extends StatelessWidget {
  const AuthSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryContainer,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'app_name'.tr(),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: Colors.black),
              ),
              const SizedBox(height: 12),
              Text(
                'auth_tagline'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black),
              ),
              const SizedBox(height: 64),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => context.push('/register/personal'),
                  child: Text('auth_create_account'.tr()),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Colors.black, width: 2),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => context.push('/login'),
                  child: Text('auth_log_in'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/features/auth/auth_selection_screen_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/auth/auth_selection_screen.dart app/test/features/auth/auth_selection_screen_test.dart app/assets/translations/
git commit -m "feat: add AuthSelectionScreen"
```

---

### Task 7: LoginScreen

**Files:**
- Create: `app/lib/features/auth/login_screen.dart`
- Test: `app/test/features/auth/login_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `AuthValidation` (Task 2), `AuthRepository` via `authRepositoryProvider` (Task 4). Navigates to `/register/personal` (link), and on successful login to `/verification-pending`, `/home`, or shows an inline error — string routes only.
- Produces: `LoginScreen` (`ConsumerWidget`, no constructor params beyond `key`) — Task 10's router uses it as the `/login` route.

This screen is a `ConsumerStatefulWidget` (needs local form-field controllers and a submitting/error state) reading `authRepositoryProvider`. Because it calls `AuthRepository.signIn`/`fetchOwnNegotiator` (Supabase-backed, untestable without a live backend per this plan's boundary), the test only covers client-side validation (empty-field blocking) and rendering — not a real sign-in round trip.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/auth/login_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/auth/login_screen.dart';

Widget _wrap(GoRouter router) {
  return ProviderScope(
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

  testWidgets('renders email and password fields', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_email_field')), findsOneWidget);
    expect(find.byKey(const Key('login_password_field')), findsOneWidget);
  });

  testWidgets('submitting with empty fields shows validation errors and does not submit', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Log In'));
    await tester.pumpAndSettle();

    expect(find.text('This field is required'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/auth/login_screen_test.dart
```
Expected: FAIL — `package:renly/features/auth/login_screen.dart` not found.

- [ ] **Step 3: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "field_email": "Email",
  "field_password": "Password",
  "auth_login_no_account": "Don't have an account? Create one",
  "auth_login_error_no_profile": "Registration incomplete. Contact support to finish setup.",
  "auth_login_error_invalid": "Invalid email or password.",
  "validation_required": "This field is required",
  "validation_email_invalid": "Enter a valid email address"
```

`app/assets/translations/ms.json` additions:
```json
  "field_email": "E-mel",
  "field_password": "Kata Laluan",
  "auth_login_no_account": "Belum ada akaun? Cipta satu",
  "auth_login_error_no_profile": "Pendaftaran belum lengkap. Hubungi sokongan untuk selesaikan.",
  "auth_login_error_invalid": "E-mel atau kata laluan tidak sah.",
  "validation_required": "Ruangan ini wajib diisi",
  "validation_email_invalid": "Masukkan alamat e-mel yang sah"
```

- [ ] **Step 4: Implement LoginScreen**

```dart
// app/lib/features/auth/login_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_providers.dart';
import 'auth_validation.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final repository = ref.read(authRepositoryProvider);
    try {
      final response = await repository.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final userId = response.user?.id;
      if (userId == null) {
        setState(() => _errorMessage = 'auth_login_error_invalid'.tr());
        return;
      }
      final negotiator = await repository.fetchOwnNegotiator(userId);
      if (!mounted) return;
      if (negotiator == null) {
        setState(() => _errorMessage = 'auth_login_error_no_profile'.tr());
        return;
      }
      if (negotiator.verificationStatus == 'pending') {
        context.go('/verification-pending');
      } else {
        context.go('/home');
      }
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'auth_login_error_invalid'.tr());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('app_name'.tr(), style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('login_email_field'),
                  controller: _emailController,
                  decoration: InputDecoration(labelText: 'field_email'.tr()),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'validation_required'.tr();
                    if (!AuthValidation.isValidEmail(value.trim())) return 'validation_email_invalid'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('login_password_field'),
                  controller: _passwordController,
                  decoration: InputDecoration(labelText: 'field_password'.tr()),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'validation_required'.tr();
                    return null;
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text('auth_log_in'.tr()),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.push('/register/personal'),
                  child: Text('auth_login_no_account'.tr()),
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

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/features/auth/login_screen_test.dart
```
Expected: `00:0X +2: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/auth/login_screen.dart app/test/features/auth/login_screen_test.dart app/assets/translations/
git commit -m "feat: add LoginScreen"
```

---

### Task 8: RegistrationPersonalScreen (Step 1 of 2)

**Files:**
- Create: `app/lib/features/auth/registration_personal_screen.dart`
- Test: `app/test/features/auth/registration_personal_screen_test.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `AuthValidation` (Task 2), `AuthRepository` via `authRepositoryProvider` (Task 4).
- Produces: `RegistrationPersonalScreen` (`ConsumerStatefulWidget`) — on success, calls `context.push('/register/professional', extra: negotiatorId)` where `negotiatorId` is a `String`. Task 9's `RegistrationProfessionalScreen` reads that `extra` as its required input.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/auth/registration_personal_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/auth/registration_personal_screen.dart';

Widget _wrap(GoRouter router) {
  return ProviderScope(
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

  testWidgets('renders all six Step 1 fields', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RegistrationPersonalScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reg_email_field')), findsOneWidget);
    expect(find.byKey(const Key('reg_password_field')), findsOneWidget);
    expect(find.byKey(const Key('reg_confirm_password_field')), findsOneWidget);
    expect(find.byKey(const Key('reg_full_name_field')), findsOneWidget);
    expect(find.byKey(const Key('reg_ic_number_field')), findsOneWidget);
    expect(find.byKey(const Key('reg_phone_number_field')), findsOneWidget);
  });

  testWidgets('mismatched passwords blocks submit with an inline error', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RegistrationPersonalScreen()),
      GoRoute(path: '/register/professional', builder: (context, state) => const Text('step-2')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.enterText(find.byKey(const Key('reg_email_field')), 'agent@renly.my');
    await tester.enterText(find.byKey(const Key('reg_password_field')), 'password1');
    await tester.enterText(find.byKey(const Key('reg_confirm_password_field')), 'password2');
    await tester.enterText(find.byKey(const Key('reg_full_name_field')), 'Aiman Yusof');
    await tester.enterText(find.byKey(const Key('reg_ic_number_field')), '900101-14-5555');
    await tester.enterText(find.byKey(const Key('reg_phone_number_field')), '012-3456789');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Next Step'));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(find.text('step-2'), findsNothing);
  });

  testWidgets('invalid IC format blocks submit', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RegistrationPersonalScreen()),
      GoRoute(path: '/register/professional', builder: (context, state) => const Text('step-2')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.enterText(find.byKey(const Key('reg_email_field')), 'agent@renly.my');
    await tester.enterText(find.byKey(const Key('reg_password_field')), 'password1');
    await tester.enterText(find.byKey(const Key('reg_confirm_password_field')), 'password1');
    await tester.enterText(find.byKey(const Key('reg_full_name_field')), 'Aiman Yusof');
    await tester.enterText(find.byKey(const Key('reg_ic_number_field')), 'not-an-ic');
    await tester.enterText(find.byKey(const Key('reg_phone_number_field')), '012-3456789');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Next Step'));
    await tester.pumpAndSettle();

    expect(find.text('Enter IC in format 900101-14-5555'), findsOneWidget);
    expect(find.text('step-2'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/features/auth/registration_personal_screen_test.dart
```
Expected: FAIL — `package:renly/features/auth/registration_personal_screen.dart` not found.

- [ ] **Step 3: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "registration_step1_title": "Create Account",
  "registration_step1_subtitle": "Join Renly to collaborate and manage your properties seamlessly.",
  "registration_personal_details_label": "Personal Details",
  "registration_step1_progress": "Step 1 of 2",
  "registration_next_step": "Next Step",
  "registration_cancel": "Cancel",
  "field_full_name": "Nama Penuh",
  "field_ic_number": "Nombor Kad Pengenalan (IC)",
  "field_phone_number": "Nombor Telefon",
  "field_confirm_password": "Confirm Password",
  "validation_password_too_short": "Password must be at least 8 characters",
  "validation_password_mismatch": "Passwords do not match",
  "validation_ic_invalid": "Enter IC in format 900101-14-5555",
  "validation_phone_invalid": "Enter phone in format 012-3456789"
```

`app/assets/translations/ms.json` additions:
```json
  "registration_step1_title": "Cipta Akaun",
  "registration_step1_subtitle": "Sertai Renly untuk berkolaborasi dan urus hartanah anda dengan lancar.",
  "registration_personal_details_label": "Personal Details",
  "registration_step1_progress": "Langkah 1 daripada 2",
  "registration_next_step": "Langkah Seterusnya",
  "registration_cancel": "Batal",
  "field_full_name": "Nama Penuh",
  "field_ic_number": "Nombor Kad Pengenalan (IC)",
  "field_phone_number": "Nombor Telefon",
  "field_confirm_password": "Sahkan Kata Laluan",
  "validation_password_too_short": "Kata laluan mesti sekurang-kurangnya 8 aksara",
  "validation_password_mismatch": "Kata laluan tidak sepadan",
  "validation_ic_invalid": "Masukkan IC dalam format 900101-14-5555",
  "validation_phone_invalid": "Masukkan telefon dalam format 012-3456789"
```

Note: `field_full_name`, `field_ic_number`, `field_phone_number`, and `registration_personal_details_label` are **identical Malay text in both files** — these are the mockup's own fixed official-terminology labels (Global Constraints), not translated per locale.

- [ ] **Step 4: Implement RegistrationPersonalScreen**

```dart
// app/lib/features/auth/registration_personal_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import 'auth_providers.dart';
import 'auth_validation.dart';

/// Ports stitch_renly_property_agent_network/registration_personal, with
/// email/password/confirm-password fields added ahead of the mockup's own
/// fullName/icNumber/phoneNumber fields (the mockup has no auth-credential
/// screen at all -- see the design doc's "Gap the mockups don't cover").
class RegistrationPersonalScreen extends ConsumerStatefulWidget {
  const RegistrationPersonalScreen({super.key});

  @override
  ConsumerState<RegistrationPersonalScreen> createState() => _RegistrationPersonalScreenState();
}

class _RegistrationPersonalScreenState extends ConsumerState<RegistrationPersonalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _icNumberController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    _icNumberController.dispose();
    _phoneNumberController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final repository = ref.read(authRepositoryProvider);
    try {
      final user = await repository.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await repository.insertNegotiator(
        negotiatorId: user.id,
        fullName: _fullNameController.text.trim(),
        icNumber: _icNumberController.text.trim(),
        phoneNumber: _phoneNumberController.text.trim(),
      );
      if (!mounted) return;
      context.push('/register/professional', extra: user.id);
    } catch (e) {
      if (mounted) setState(() => _submitError = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: Text('app_name'.tr()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('registration_step1_title'.tr(), style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 8),
                Text('registration_step1_subtitle'.tr(), style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('registration_personal_details_label'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.primary)),
                    Text('registration_step1_progress'.tr(), style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('reg_email_field'),
                  controller: _emailController,
                  decoration: InputDecoration(labelText: 'field_email'.tr()),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'validation_required'.tr();
                    if (!AuthValidation.isValidEmail(value.trim())) return 'validation_email_invalid'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reg_password_field'),
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'field_password'.tr()),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'validation_required'.tr();
                    if (!AuthValidation.isValidPassword(value)) return 'validation_password_too_short'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reg_confirm_password_field'),
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'field_confirm_password'.tr()),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'validation_required'.tr();
                    if (!AuthValidation.passwordsMatch(_passwordController.text, value)) {
                      return 'validation_password_mismatch'.tr();
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reg_full_name_field'),
                  controller: _fullNameController,
                  decoration: InputDecoration(labelText: 'field_full_name'.tr()),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'validation_required'.tr() : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reg_ic_number_field'),
                  controller: _icNumberController,
                  decoration: InputDecoration(labelText: 'field_ic_number'.tr()),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'validation_required'.tr();
                    if (!AuthValidation.isValidIcNumber(value.trim())) return 'validation_ic_invalid'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reg_phone_number_field'),
                  controller: _phoneNumberController,
                  decoration: InputDecoration(labelText: 'field_phone_number'.tr()),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'validation_required'.tr();
                    if (!AuthValidation.isValidPhoneNumber(value.trim())) return 'validation_phone_invalid'.tr();
                    return null;
                  },
                ),
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => context.pop(), child: Text('registration_cancel'.tr())),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text('registration_next_step'.tr()),
                    ),
                  ],
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

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/features/auth/registration_personal_screen_test.dart
```
Expected: `00:0X +3: All tests passed!`

- [ ] **Step 6: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/auth/registration_personal_screen.dart app/test/features/auth/registration_personal_screen_test.dart app/assets/translations/
git commit -m "feat: add RegistrationPersonalScreen (Step 1 of 2)"
```

---

### Task 9: RegistrationProfessionalScreen (Step 2 of 2) + HomePlaceholderScreen

**Files:**
- Create: `app/lib/features/auth/registration_professional_screen.dart`
- Create: `app/lib/features/auth/home_placeholder_screen.dart`
- Test: `app/test/features/auth/registration_professional_screen_test.dart`
- Test: `app/test/features/auth/home_placeholder_screen_test.dart`
- Modify: `app/pubspec.yaml` (add `image_picker` dependency)
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `AuthRepository` via `authRepositoryProvider` (Task 4). Reads `negotiatorId` from `GoRouterState.extra` (a `String`, set by Task 8's `context.push('/register/professional', extra: user.id)`). Navigates to `/verification-pending` on success.
- Produces: `RegistrationProfessionalScreen` (`ConsumerStatefulWidget`, constructor takes `{required this.negotiatorId}`) and `HomePlaceholderScreen` (`StatelessWidget`, no params) — Task 10's router wires both, the former reading `state.extra as String`.

- [ ] **Step 1: Add image_picker dependency**

In `app/pubspec.yaml`, under `dependencies:`, add:
```yaml
  image_picker: ^1.1.2
```

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter pub get
```
Expected: `Got dependencies!` with no resolution errors.

- [ ] **Step 2: Write the failing RegistrationProfessionalScreen test**

```dart
// app/test/features/auth/registration_professional_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/auth/registration_professional_screen.dart';

Widget _wrap(GoRouter router) {
  return ProviderScope(
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

  testWidgets('renders REN number, agency name, and tag photo upload fields', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const RegistrationProfessionalScreen(negotiatorId: 'test-id'),
      ),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reg_ren_number_field')), findsOneWidget);
    expect(find.byKey(const Key('reg_agency_name_field')), findsOneWidget);
    expect(find.text('Choose File'), findsOneWidget);
  });

  testWidgets('submitting with empty required fields shows validation errors', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const RegistrationProfessionalScreen(negotiatorId: 'test-id'),
      ),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Complete Registration'));
    await tester.pumpAndSettle();

    expect(find.text('This field is required'), findsWidgets);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
flutter test test/features/auth/registration_professional_screen_test.dart
```
Expected: FAIL — `package:renly/features/auth/registration_professional_screen.dart` not found.

- [ ] **Step 4: Write the failing HomePlaceholderScreen test**

```dart
// app/test/features/auth/home_placeholder_screen_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/features/auth/home_placeholder_screen.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('renders verified placeholder copy', (tester) async {
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
            home: const HomePlaceholderScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("You're verified"), findsOneWidget);
    expect(find.text('Dashboard coming soon.'), findsOneWidget);
  });
}
```

- [ ] **Step 5: Run test to verify it fails**

```bash
flutter test test/features/auth/home_placeholder_screen_test.dart
```
Expected: FAIL — `package:renly/features/auth/home_placeholder_screen.dart` not found.

- [ ] **Step 6: Add the translation keys**

`app/assets/translations/en.json` additions:
```json
  "registration_step2_title": "Verify your status",
  "registration_step2_subtitle": "Please provide your real estate negotiator details to continue.",
  "registration_professional_details_label": "Professional Details",
  "registration_step2_progress": "Step 2 of 2",
  "field_ren_number": "Nombor REN",
  "field_agency_name": "Nama Agensi",
  "registration_tag_photo_label": "REN Tag Photo",
  "registration_tag_photo_hint": "Clear, front-facing photo of your physical REN Tag",
  "registration_choose_file": "Choose File",
  "registration_complete": "Complete Registration",
  "home_placeholder_title": "You're verified",
  "home_placeholder_body": "Dashboard coming soon."
```

`app/assets/translations/ms.json` additions:
```json
  "registration_step2_title": "Sahkan status anda",
  "registration_step2_subtitle": "Sila berikan butiran negotiator hartanah anda untuk teruskan.",
  "registration_professional_details_label": "Professional Details",
  "registration_step2_progress": "Langkah 2 daripada 2",
  "field_ren_number": "Nombor REN",
  "field_agency_name": "Nama Agensi",
  "registration_tag_photo_label": "REN Tag Photo",
  "registration_tag_photo_hint": "Gambar jelas, menghadap depan, Tag REN fizikal anda",
  "registration_choose_file": "Pilih Fail",
  "registration_complete": "Lengkapkan Pendaftaran",
  "home_placeholder_title": "Anda telah disahkan",
  "home_placeholder_body": "Papan pemuka akan datang tidak lama lagi."
```

`field_ren_number` and `field_agency_name` and the two `_details_label` keys are again identical Malay text in both files, per the mockup's fixed terminology (same pattern as Task 8).

- [ ] **Step 7: Implement HomePlaceholderScreen**

```dart
// app/lib/features/auth/home_placeholder_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Implement RegistrationProfessionalScreen**

```dart
// app/lib/features/auth/registration_professional_screen.dart
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import 'auth_providers.dart';

/// Ports stitch_renly_property_agent_network/registration_professional.
/// "REN Tag Photo" is a plain image-picker upload (evidentiary record),
/// not live camera OCR scanning -- camera tag-scanning is explicitly
/// deferred per the design doc.
class RegistrationProfessionalScreen extends ConsumerStatefulWidget {
  const RegistrationProfessionalScreen({super.key, required this.negotiatorId});

  final String negotiatorId;

  @override
  ConsumerState<RegistrationProfessionalScreen> createState() => _RegistrationProfessionalScreenState();
}

class _RegistrationProfessionalScreenState extends ConsumerState<RegistrationProfessionalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _renNumberController = TextEditingController();
  final _agencyNameController = TextEditingController();
  XFile? _tagPhoto;
  bool _submitting = false;
  String? _submitError;
  String? _photoError;

  @override
  void dispose() {
    _renNumberController.dispose();
    _agencyNameController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() {
        _tagPhoto = picked;
        _photoError = null;
      });
    }
  }

  Future<void> _submit() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    final photoValid = _tagPhoto != null;
    if (!photoValid) setState(() => _photoError = 'validation_required'.tr());
    if (!formValid || !photoValid) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final repository = ref.read(authRepositoryProvider);
    try {
      final agencyId = await repository.findOrCreateAgency(_agencyNameController.text.trim());
      final bytes = await File(_tagPhoto!.path).readAsBytes();
      final photoUrl = await repository.uploadTagPhoto(
        negotiatorId: widget.negotiatorId,
        bytes: bytes,
      );
      await repository.completeProfessionalDetails(
        negotiatorId: widget.negotiatorId,
        renNumber: _renNumberController.text.trim(),
        agencyId: agencyId,
      );
      await repository.insertVerificationRecord(
        negotiatorId: widget.negotiatorId,
        tagPhotoUrl: photoUrl,
      );
      if (!mounted) return;
      context.go('/verification-pending');
    } catch (e) {
      if (mounted) setState(() => _submitError = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: Text('app_name'.tr()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('registration_step2_title'.tr(), style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 8),
                Text('registration_step2_subtitle'.tr(), style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('registration_step2_progress'.tr(), style: Theme.of(context).textTheme.labelSmall),
                    Text('registration_professional_details_label'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('reg_ren_number_field'),
                  controller: _renNumberController,
                  decoration: InputDecoration(labelText: 'field_ren_number'.tr()),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'validation_required'.tr() : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reg_agency_name_field'),
                  controller: _agencyNameController,
                  decoration: InputDecoration(labelText: 'field_agency_name'.tr()),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'validation_required'.tr() : null,
                ),
                const SizedBox(height: 12),
                Text('registration_tag_photo_label'.tr(), style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 4),
                Text('registration_tag_photo_hint'.tr(), style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _pickPhoto,
                  child: Text(_tagPhoto == null ? 'registration_choose_file'.tr() : _tagPhoto!.name),
                ),
                if (_photoError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_photoError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text('registration_complete'.tr()),
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

- [ ] **Step 9: Run both tests to verify they pass**

```bash
flutter test test/features/auth/registration_professional_screen_test.dart test/features/auth/home_placeholder_screen_test.dart
```
Expected: `00:0X +3: All tests passed!` (2 from RegistrationProfessionalScreen, 1 from HomePlaceholderScreen).

- [ ] **Step 10: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/features/auth/registration_professional_screen.dart app/lib/features/auth/home_placeholder_screen.dart app/test/features/auth/registration_professional_screen_test.dart app/test/features/auth/home_placeholder_screen_test.dart app/pubspec.yaml app/pubspec.lock app/assets/translations/
git commit -m "feat: add RegistrationProfessionalScreen and HomePlaceholderScreen"
```

---

### Task 10: Wire the router (Provider<GoRouter>) and main.dart

**Files:**
- Modify: `app/lib/core/router/app_router.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/core/router/app_router_test.dart`

**Interfaces:**
- Consumes: every screen from Tasks 5-9 (`AuthSelectionScreen`, `LoginScreen`, `RegistrationPersonalScreen`, `RegistrationProfessionalScreen`, `VerificationPendingScreen`, `HomePlaceholderScreen`), `authStateProvider` (Task 4).
- Produces: `computeAuthRedirect({required bool hasSession, required String location})` (pure `String?` function, unit-tested) and `appRouterProvider` (`Provider<GoRouter>`) replacing the old top-level `appRouter` constant. `main.dart`'s `RenlyApp` becomes a `ConsumerWidget` reading `ref.watch(appRouterProvider)`.

This is the integration task — after this, `flutter test` (full suite) and `flutter analyze` must both be clean, and the app is manually runnable end to end.

- [ ] **Step 1: Write the failing computeAuthRedirect test**

```dart
// app/test/core/router/app_router_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/router/app_router.dart';

void main() {
  group('computeAuthRedirect', () {
    test('unauthenticated user on / is allowed (no redirect)', () {
      expect(computeAuthRedirect(hasSession: false, location: '/'), isNull);
    });

    test('unauthenticated user on /login is allowed', () {
      expect(computeAuthRedirect(hasSession: false, location: '/login'), isNull);
    });

    test('unauthenticated user on /register/personal is allowed', () {
      expect(computeAuthRedirect(hasSession: false, location: '/register/personal'), isNull);
    });

    test('unauthenticated user on /register/professional is allowed', () {
      expect(computeAuthRedirect(hasSession: false, location: '/register/professional'), isNull);
    });

    test('unauthenticated user on /home is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/home'), '/');
    });

    test('unauthenticated user on /verification-pending is redirected to /', () {
      expect(computeAuthRedirect(hasSession: false, location: '/verification-pending'), '/');
    });

    test('authenticated user anywhere is never redirected', () {
      expect(computeAuthRedirect(hasSession: true, location: '/'), isNull);
      expect(computeAuthRedirect(hasSession: true, location: '/home'), isNull);
      expect(computeAuthRedirect(hasSession: true, location: '/verification-pending'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test test/core/router/app_router_test.dart
```
Expected: FAIL — `computeAuthRedirect` not defined (the old `app_router.dart` only exports `appRouter`).

- [ ] **Step 3: Rewrite app_router.dart**

```dart
// app/lib/core/router/app_router.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_providers.dart';
import '../../features/auth/auth_selection_screen.dart';
import '../../features/auth/home_placeholder_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/registration_personal_screen.dart';
import '../../features/auth/registration_professional_screen.dart';
import '../../features/auth/verification_pending_screen.dart';

const _publicRoutes = {'/', '/login', '/register/personal', '/register/professional'};

/// Pure redirect decision, unit-tested independently of GoRouter/Riverpod:
/// an unauthenticated session may only reach the public auth/registration
/// routes; anything else bounces back to '/'. Authenticated sessions are
/// never redirected by this function -- the pending-vs-approved routing
/// decision happens inside LoginScreen's submit handler, not here.
String? computeAuthRedirect({required bool hasSession, required String location}) {
  if (!hasSession && !_publicRoutes.contains(location)) {
    return '/';
  }
  return null;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final hasSession = authState.valueOrNull?.session != null;

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) => computeAuthRedirect(hasSession: hasSession, location: state.matchedLocation),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthSelectionScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register/personal',
        builder: (context, state) => const RegistrationPersonalScreen(),
      ),
      GoRoute(
        path: '/register/professional',
        builder: (context, state) => RegistrationProfessionalScreen(negotiatorId: state.extra as String),
      ),
      GoRoute(
        path: '/verification-pending',
        builder: (context, state) => const VerificationPendingScreen(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomePlaceholderScreen()),
    ],
  );
});
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/core/router/app_router_test.dart
```
Expected: `00:0X +7: All tests passed!`

- [ ] **Step 5: Update main.dart to use appRouterProvider**

Read `app/lib/main.dart` first. Change the `RenlyApp` class from a `StatelessWidget` reading the old top-level `appRouter` to a `ConsumerWidget` reading `appRouterProvider`:

```dart
// app/lib/main.dart (RenlyApp class only -- everything above it in the file, including main(), is unchanged)
class RenlyApp extends ConsumerWidget {
  const RenlyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'renly',
      theme: AppTheme.light,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      routerConfig: router,
    );
  }
}
```

Update the import line for the router in `main.dart` from whatever it currently imports (the old `appRouter` symbol) to import `appRouterProvider` from the same `core/router/app_router.dart` path — the import path itself doesn't change, only which symbol is used inside the file.

- [ ] **Step 6: Run the full test suite**

```bash
flutter test
```
Expected: every test across `test/core/`, `test/l10n/`, `test/features/auth/` passes, zero failures. Count should be Milestone 1's 13, minus the 1 moved-not-removed `verification_pending_screen_test.dart` (still counted, just relocated), plus this plan's new tests (Task 2: 14+1=15, Task 6: 3, Task 7: 2, Task 8: 3, Task 9: 2+1=3, Task 10: 7) — expect somewhere around `00:0X +44: All tests passed!` (exact count isn't the point; zero failures is).

- [ ] **Step 7: Run static analysis**

```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 8: Verify the translations file still has full key parity**

```bash
flutter test test/l10n/translations_test.dart
```
Expected: `00:0X +1: All tests passed!` — confirms every key added across Tasks 6-9 landed in both `en.json` and `ms.json` with no typo mismatches.

- [ ] **Step 9: Commit**

```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
git add app/lib/core/router/app_router.dart app/lib/main.dart app/test/core/router/app_router_test.dart
git commit -m "feat: wire Provider<GoRouter> with auth-gated redirect across all auth screens"
```

---

## Definition of Done

- `flutter test` (run from `app/`) passes with zero failures across the whole suite.
- `flutter analyze` reports no issues.
- `flutter run` on the user's Android emulator shows: `/` renders `AuthSelectionScreen` on the lime background; tapping "Create account" walks through Step 1 → Step 2 → `VerificationPendingScreen`; a second run with "Log In" using the same credentials reaches `VerificationPendingScreen` again (since the fresh account is still `pending`).
- The SQL migration has been run in the user's Supabase project and email confirmation has been disabled (Task 1's manual steps) — without this, registration will fail with Postgrest errors even though all code is correct.
- All 10 tasks committed individually.

## Explicitly not in this plan

Onboarding carousel, camera live tag-scan/OCR, automated LPPEH register cross-check, admin review UI for `verification_status`, real home dashboard (beyond the one-line placeholder), `territory` field collection. These are listed in the design doc's "Explicitly deferred" section and start in a later plan.
