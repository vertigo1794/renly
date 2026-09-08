# Negotiator Avatar + Online Presence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every negotiator a real, self-uploaded profile photo and a real (heartbeat-driven) online indicator, surfaced everywhere the app shows another negotiator's name — plus the upload flow for a negotiator's own photo.

**Architecture:** One migration adds `avatar_url`/`last_seen_at` to `negotiator`, a new public Storage bucket, and extends the existing `get_negotiator_public_info` RPC to compute `is_online` server-side. `ListingOwner` (the one shared model every consumer already uses) gains the two new fields. A new `NegotiatorAvatar` shared widget generalizes two hand-rolled avatar circles that already exist in this codebase (`conversation_list_screen.dart`, `marketplace_screen.dart`) and is rolled out to 9 call sites. A `WidgetsBindingObserver` on the app's existing top-level state sends the heartbeat.

**Tech Stack:** Flutter/Riverpod, Supabase (Postgres + Storage), `image_picker` (already a dependency).

## Global Constraints

- Never fabricate data: `avatarUrl`/`isOnline` render nothing decorative when unset — initials fallback, no dot, per `docs/superpowers/specs/2026-09-07-renly-negotiator-avatar-presence-design.md`.
- The `avatar-photos` Storage bucket is **public** (`public = true`), unlike `listing-photos`/`requirement-photos` (both private + signed URL) — see the design doc's Storage section for the exact rationale.
- `is_online` is computed **server-side** in the RPC (`now() - last_seen_at < interval '2 minutes'`), never client-side.
- Migration `0028_negotiator_avatar_presence.sql` follows `0012_settings.sql`'s **additive-only grant** pattern (no `revoke update ... from authenticated` first) — Postgres `GRANT` does not reset prior column grants, only `REVOKE` does; a revoke+narrower-regrant pair on this exact table caused a real Critical bug in `0010_profile.sql`, documented in that migration's own comment.
- Excluded from rollout: `main_dashboard_screen.dart` (explicit user instruction), and every place a screen shows the **viewer's own** profile (Marketplace/Messages/Post Broadcast header badges, Account Settings) — those are unrelated to "another negotiator" and stay untouched.
- Repository methods that call Supabase directly are **not** unit-tested in this project (manually verified after the migration/bucket are applied); pure model/widget logic gets real tests. This convention repeats in every task below.

---

### Task 1: Migration — avatar/presence columns, public bucket, RPC extension

**Files:**
- Create: `supabase/migrations/0028_negotiator_avatar_presence.sql`

**Interfaces:**
- Produces: `negotiator.avatar_url` (text, nullable), `negotiator.last_seen_at` (timestamptz, nullable); Storage bucket `avatar-photos` (public); RPC `get_negotiator_public_info(uuid)` now returns `(full_name text, ren_number text, agency_name text, verification_status text, avatar_url text, is_online boolean)`.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0028_negotiator_avatar_presence.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0027.
--
-- avatar_url: public URL (not a path -- ProfileRepository.uploadAvatar
-- resolves and stores the full public URL at upload time, since the
-- avatar-photos bucket below is public, unlike listing-photos/
-- requirement-photos which store paths and resolve them via a short-lived
-- signed URL on read). Nullable -- absent means no photo uploaded yet, UI
-- falls back to an initials avatar, never a fabricated placeholder image.
--
-- last_seen_at: updated by the client itself (on app resume + a periodic
-- heartbeat while active, see Task 5). Nullable -- a negotiator who has
-- never triggered a heartbeat reads as offline, never "online" by default.
alter table negotiator add column if not exists avatar_url text;
alter table negotiator add column if not exists last_seen_at timestamptz;

-- Additive only -- no prior REVOKE statement, per 0012_settings.sql's own
-- established reasoning: Postgres GRANT is additive and does not reset
-- prior column grants, so there is no need to (and real danger in trying
-- to) restate the full existing UPDATE column list. The existing 10-column
-- grant (full_name, ic_number, phone_number, ren_number, agency_id,
-- territory, property_specialisation, notify_match, notify_message,
-- notify_cobroke_request) is left untouched; these 2 columns are simply
-- added on top of it. No RLS policy change needed -- negotiator_update_own
-- (0001) already gates which ROW can be touched.
grant update (avatar_url, last_seen_at) on negotiator to authenticated;

-- Storage: path convention {negotiator_id}/avatar.jpg. PUBLIC bucket
-- (unlike listing-photos/requirement-photos, both private) -- avatars are
-- low-sensitivity and need broad, simple display across 9 screens without
-- managing signed-URL expiry at each one.
insert into storage.buckets (id, name, public) values ('avatar-photos', 'avatar-photos', true)
  on conflict (id) do nothing;

create policy avatar_photos_select_public on storage.objects for select
  to public using (bucket_id = 'avatar-photos');

create policy avatar_photos_insert_own on storage.objects for insert
  to authenticated with check (bucket_id = 'avatar-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatar_photos_update_own on storage.objects for update
  to authenticated using (bucket_id = 'avatar-photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatar-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatar_photos_delete_own on storage.objects for delete
  to authenticated using (bucket_id = 'avatar-photos' and (storage.foldername(name))[1] = auth.uid()::text);

update storage.buckets
set file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png']
where id = 'avatar-photos';

-- Postgres does NOT allow CREATE OR REPLACE FUNCTION to change a
-- function's return type (RETURNS TABLE compiles to OUT parameters) --
-- the function must be dropped and recreated, same as 0019 and 0026 both
-- had to do. Dropping a function discards its existing grants, so they
-- are explicitly restated below.
drop function if exists get_negotiator_public_info(uuid);

create function get_negotiator_public_info(p_negotiator_id uuid)
returns table (
  full_name text, ren_number text, agency_name text, verification_status text,
  avatar_url text, is_online boolean
)
language sql
security definer
set search_path = public
as $$
  select n.full_name, n.ren_number, a.firm_name, n.verification_status,
         n.avatar_url, (n.last_seen_at is not null and now() - n.last_seen_at < interval '2 minutes')
  from negotiator n
  left join agency a on a.agency_id = n.agency_id
  where n.negotiator_id = p_negotiator_id;
$$;

revoke execute on function get_negotiator_public_info(uuid) from public;
grant execute on function get_negotiator_public_info(uuid) to authenticated;
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/0028_negotiator_avatar_presence.sql
git commit -m "feat: add negotiator avatar/presence migration"
```

This migration is file-only in this task — it is applied manually via the Supabase SQL Editor later, same as every prior migration in this project. Do not attempt to run it against a live database from this task.

---

### Task 2: `ListingOwner` model — avatarUrl and isOnline

**Files:**
- Modify: `app/lib/features/listing/models/listing_owner.dart`
- Test: `app/test/features/listing/models/listing_owner_test.dart`

**Interfaces:**
- Produces: `ListingOwner.avatarUrl` (`String?`), `ListingOwner.isOnline` (`bool`, defaults `false`) — consumed by Task 4 (`NegotiatorAvatar`) and every rollout task (6-9).

- [ ] **Step 1: Write the failing tests**

Add to the end of the existing `group('ListingOwner.fromJson', ...)` block in `app/test/features/listing/models/listing_owner_test.dart` (do not remove the 2 existing tests):

```dart
    test('parses avatar_url and is_online when present', () {
      final owner = ListingOwner.fromJson({
        'full_name': 'Aiman Yusof',
        'ren_number': '12345',
        'avatar_url': 'https://example.test/avatar.jpg',
        'is_online': true,
      });

      expect(owner.avatarUrl, 'https://example.test/avatar.jpg');
      expect(owner.isOnline, isTrue);
    });

    test('avatarUrl is null and isOnline is false when absent, never fabricated', () {
      final owner = ListingOwner.fromJson({
        'full_name': 'Aiman Yusof',
        'ren_number': '12345',
      });

      expect(owner.avatarUrl, isNull);
      expect(owner.isOnline, isFalse);
    });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/features/listing/models/listing_owner_test.dart`
Expected: FAIL — `avatarUrl`/`isOnline` are not defined on `ListingOwner`.

- [ ] **Step 3: Add the fields**

In `app/lib/features/listing/models/listing_owner.dart`, replace the whole file with:

```dart
/// The listing's negotiator, scoped to what PropertyDetailScreen displays
/// (name + REN number) -- deliberately not the full `Negotiator` model from
/// the auth feature, to keep this feature's Supabase reads self-contained
/// rather than reaching into another feature's model. `agencyName` added
/// for the Main Dashboard's Co-Broking Radar card (shows the matched
/// agent's agency as a trust signal) -- nullable because the RPC's LEFT
/// JOIN on `agency` returns null for a negotiator with no `agency_id` set.
/// `verificationStatus` added for the Property Detail Ultra-Premium
/// Restyle's real verified-checkmark -- nullable for the same reason as
/// every other optional field here (absent means unknown, never assumed
/// approved). `avatarUrl`/`isOnline` added for the Negotiator Avatar +
/// Online Presence feature -- `avatarUrl` is a full public URL (the
/// avatar-photos bucket is public), nullable meaning no photo uploaded yet;
/// `isOnline` is computed server-side by the RPC from `last_seen_at`,
/// defaults false (never assumed online).
class ListingOwner {
  final String fullName;
  final String renNumber;
  final String? agencyName;
  final String? verificationStatus;
  final String? avatarUrl;
  final bool isOnline;

  const ListingOwner({
    required this.fullName,
    required this.renNumber,
    this.agencyName,
    this.verificationStatus,
    this.avatarUrl,
    this.isOnline = false,
  });

  factory ListingOwner.fromJson(Map<String, dynamic> json) {
    return ListingOwner(
      fullName: json['full_name'] as String,
      renNumber: json['ren_number'] as String? ?? '',
      agencyName: json['agency_name'] as String?,
      verificationStatus: json['verification_status'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/features/listing/models/listing_owner_test.dart`
Expected: PASS, all 4 tests.

- [ ] **Step 5: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/listing/models/listing_owner.dart app/test/features/listing/models/listing_owner_test.dart
git commit -m "feat: add avatarUrl/isOnline to ListingOwner"
```

---

### Task 3: `ProfileRepository` — heartbeat + avatar upload

**Files:**
- Modify: `app/lib/features/profile/profile_repository.dart`
- Modify: `app/lib/features/profile/models/profile.dart`
- Test: `app/test/features/profile/models/profile_test.dart`

**Interfaces:**
- Consumes: `SupabaseClient` (constructor param, already present on `ProfileRepository`).
- Produces: `ProfileRepository.updateLastSeen({required String negotiatorId})` (`Future<void>`), `ProfileRepository.uploadAvatar({required String negotiatorId, required Uint8List bytes})` (`Future<String>`, returns the public URL), `ProfileRepository.updateAvatarUrl({required String negotiatorId, required String avatarUrl})` (`Future<void>`) — consumed by Task 5 (heartbeat) and Task 10 (upload UI). `Profile.avatarUrl` (`String?`) — consumed by Task 10.

- [ ] **Step 1: Write the failing test for `Profile.avatarUrl`**

Add to `app/test/features/profile/models/profile_test.dart` (read the file first to match its exact existing test style/group name, then add these 2 tests to the relevant `group`):

```dart
    test('parses avatar_url when present', () {
      final profile = Profile.fromJson({
        'negotiator_id': 'n-1',
        'full_name': 'Aiman Yusof',
        'verification_status': 'approved',
        'avatar_url': 'https://example.test/avatar.jpg',
      });

      expect(profile.avatarUrl, 'https://example.test/avatar.jpg');
    });

    test('avatar_url is null when absent', () {
      final profile = Profile.fromJson({
        'negotiator_id': 'n-1',
        'full_name': 'Aiman Yusof',
        'verification_status': 'approved',
      });

      expect(profile.avatarUrl, isNull);
    });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && flutter test test/features/profile/models/profile_test.dart`
Expected: FAIL — `avatarUrl` is not defined on `Profile`.

- [ ] **Step 3: Add `avatarUrl` to `Profile`**

In `app/lib/features/profile/models/profile.dart`, replace the whole file with:

```dart
/// The current negotiator's own full profile -- composed from `negotiator`
/// plus a follow-up `agency` lookup for the firm name. Deliberately
/// separate from the auth feature's own scoped-down `Negotiator` model
/// (which only carries the 3 fields the router redirect needs).
/// `avatarUrl` added for the Negotiator Avatar + Online Presence feature --
/// a full public URL (the avatar-photos bucket is public), nullable
/// meaning no photo uploaded yet.
class Profile {
  final String negotiatorId;
  final String fullName;
  final String? renNumber;
  final String? agencyName;
  final String? territory;
  final String? propertySpecialisation;
  final String verificationStatus;
  final String? avatarUrl;

  const Profile({
    required this.negotiatorId,
    required this.fullName,
    this.renNumber,
    this.agencyName,
    this.territory,
    this.propertySpecialisation,
    required this.verificationStatus,
    this.avatarUrl,
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
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && flutter test test/features/profile/models/profile_test.dart`
Expected: PASS, all tests including the 2 new ones.

- [ ] **Step 5: Add the 3 new `ProfileRepository` methods**

In `app/lib/features/profile/profile_repository.dart`, add `import 'dart:typed_data';` at the top (after the existing comment line, before the `supabase_flutter` import), add `'avatar_url'` to `fetchMyProfile`'s existing `.select(...)` column list, and add the 3 new methods after `updateProfile`:

```dart
// app/lib/features/profile/profile_repository.dart
import 'dart:typed_data';

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
        .select('negotiator_id, full_name, ren_number, agency_id, territory, property_specialisation, verification_status, avatar_url')
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

  /// The `avatar-photos` bucket is public (unlike `listing-photos`/
  /// `requirement-photos`, both private + signed-URL), so this returns the
  /// full public URL directly -- no signing step needed at any of this
  /// URL's 9+ display call sites. Does NOT write `avatar_url` on the
  /// negotiator row -- callers persist the returned URL via
  /// [updateAvatarUrl], same two-step split as
  /// `ListingRepository.uploadListingPhoto`/`updateListingPhotos`.
  Future<String> uploadAvatar({required String negotiatorId, required Uint8List bytes}) async {
    final path = '$negotiatorId/avatar.jpg';
    await _client.storage.from('avatar-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return _client.storage.from('avatar-photos').getPublicUrl(path);
  }

  Future<void> updateAvatarUrl({required String negotiatorId, required String avatarUrl}) {
    return _client.from('negotiator').update({'avatar_url': avatarUrl}).eq('negotiator_id', negotiatorId);
  }

  /// Best-effort heartbeat -- see `_PresenceHeartbeat` in main.dart for the
  /// caller. A failure here (offline, backend hiccup) must never surface an
  /// error or block the app; callers swallow exceptions from this method.
  Future<void> updateLastSeen({required String negotiatorId}) {
    return _client.from('negotiator').update({'last_seen_at': DateTime.now().toIso8601String()}).eq('negotiator_id', negotiatorId);
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

- [ ] **Step 6: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

`uploadAvatar`/`updateAvatarUrl`/`updateLastSeen` are Supabase-boundary methods and are not unit-tested here, per this project's established convention — they are manually verified once the migration and bucket from Task 1 are applied.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/profile/profile_repository.dart app/lib/features/profile/models/profile.dart app/test/features/profile/models/profile_test.dart
git commit -m "feat: add avatar upload and presence heartbeat to ProfileRepository"
```

---

### Task 4: `NegotiatorAvatar` shared widget

**Files:**
- Create: `app/lib/core/widgets/negotiator_avatar.dart`
- Test: `app/test/core/widgets/negotiator_avatar_test.dart`

**Interfaces:**
- Consumes: nothing beyond plain Dart/Flutter types (`fullName` String, `avatarUrl` String?, `isOnline` bool, `size` double) -- has no Supabase/Riverpod dependency, same principle as `SignedPhoto`.
- Produces: `NegotiatorAvatar` widget -- consumed by Tasks 6-9.

- [ ] **Step 1: Write the failing tests**

Create `app/test/core/widgets/negotiator_avatar_test.dart`:

```dart
// app/test/core/widgets/negotiator_avatar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/widgets/negotiator_avatar.dart';

void main() {
  group('NegotiatorAvatar', () {
    testWidgets('renders the initials fallback when avatarUrl is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NegotiatorAvatar(fullName: 'Aiman Yusof'))),
      );

      expect(find.text('A'), findsOneWidget);
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isNull);
    });

    testWidgets('renders "?" when fullName is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NegotiatorAvatar(fullName: ''))),
      );

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('renders a network image when avatarUrl is set', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NegotiatorAvatar(fullName: 'Aiman Yusof', avatarUrl: 'https://example.test/avatar.jpg'),
          ),
        ),
      );

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isA<NetworkImage>());
      expect((avatar.backgroundImage! as NetworkImage).url, 'https://example.test/avatar.jpg');
      expect(find.text('A'), findsNothing);
    });

    testWidgets('shows no online dot when isOnline is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NegotiatorAvatar(fullName: 'Aiman Yusof'))),
      );

      expect(find.byType(Stack), findsNothing);
    });

    testWidgets('shows an online dot when isOnline is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NegotiatorAvatar(fullName: 'Aiman Yusof', isOnline: true)),
        ),
      );

      expect(find.byType(Stack), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd app && flutter test test/core/widgets/negotiator_avatar_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:renly/core/widgets/negotiator_avatar.dart'`.

- [ ] **Step 3: Write the widget**

Create `app/lib/core/widgets/negotiator_avatar.dart`:

```dart
// app/lib/core/widgets/negotiator_avatar.dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A circular avatar for ANOTHER negotiator (not the viewer's own profile)
/// -- their uploaded photo when set, else the initials-on-ink-circle
/// fallback this app already hand-rolled in two places
/// (`conversation_list_screen.dart` radius 22, `marketplace_screen.dart`
/// radius 15) before this widget existed. A small green dot overlays the
/// bottom-right corner ONLY when [isOnline] is true -- no dot at all when
/// false, so a viewer never has to guess whether gray means "offline" or
/// "unknown" (see the design doc's own reasoning for this choice). Has no
/// Supabase/Riverpod dependency, same principle as `SignedPhoto` --
/// [avatarUrl] is expected to already be a full public URL (the
/// avatar-photos bucket is public, unlike the private+signed-URL
/// listing/requirement photo buckets `SignedPhoto` was built for).
///
/// [size] mirrors `RStarBadge`'s own size-param convention (a single
/// scalar controlling overall diameter, with internal proportions computed
/// off it) -- default 44 matches `conversation_list_screen.dart`'s
/// pre-existing radius-22 visual, so that call site's own replacement is a
/// drop-in with zero visual change beyond the new photo/dot capability.
class NegotiatorAvatar extends StatelessWidget {
  const NegotiatorAvatar({
    required this.fullName,
    this.avatarUrl,
    this.isOnline = false,
    this.size = 44,
    super.key,
  });

  final String fullName;
  final String? avatarUrl;
  final bool isOnline;
  final double size;

  @override
  Widget build(BuildContext context) {
    final circle = CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFF0B0F19),
      backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl!),
      child: avatarUrl != null
          ? null
          : Text(
              fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: size * 16 / 44),
            ),
    );

    if (!isOnline) return circle;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        circle,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: size * 12 / 44,
            height: size * 12 / 44,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: size * 2 / 44),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd app && flutter test test/core/widgets/negotiator_avatar_test.dart`
Expected: PASS, all 5 tests.

- [ ] **Step 5: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/core/widgets/negotiator_avatar.dart app/test/core/widgets/negotiator_avatar_test.dart
git commit -m "feat: add NegotiatorAvatar shared widget"
```

---

### Task 5: Presence heartbeat in `main.dart`

**Files:**
- Modify: `app/lib/main.dart`
- Modify: `app/lib/features/profile/profile_providers.dart`

**Interfaces:**
- Consumes: `ProfileRepository.updateLastSeen({required String negotiatorId})` (Task 3), `profileRepositoryProvider` (must exist in `profile_providers.dart` -- read that file fresh first; if it does not already expose a plain `Provider<ProfileRepository>`, add one following its existing provider style).

- [ ] **Step 1: Read `app/lib/features/profile/profile_providers.dart` fresh**

Confirm the exact name and shape of the existing `ProfileRepository` provider (referenced elsewhere in this plan as `profileRepositoryProvider`, matching the pattern `ref.read(profileRepositoryProvider)` already used in `profile_screen.dart`'s `_EditForm._save()`). Use that exact provider — do not create a second one.

- [ ] **Step 2: Add the heartbeat observer to `_RenlyAppState`**

In `app/lib/main.dart`, change the class declaration and add lifecycle wiring. The diff:

```dart
class _RenlyAppState extends ConsumerState<RenlyApp> with WidgetsBindingObserver {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  Timer? _presenceHeartbeat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.firebaseReady) return;
    _registerToken();
    Supabase.instance.client.auth.onAuthStateChange.listen((_) => _registerToken());
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => _registerToken());
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((message) => _navigateFromMessage(message.data));
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _navigateFromMessage(message.data);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceHeartbeat?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sendHeartbeat();
      _presenceHeartbeat ??= Timer.periodic(const Duration(seconds: 60), (_) => _sendHeartbeat());
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _presenceHeartbeat?.cancel();
      _presenceHeartbeat = null;
    }
  }

  /// Best-effort, same reasoning as every other push/notification call site
  /// in this file -- a heartbeat failing (offline, backend hiccup) must
  /// never surface an error or block the app. No-ops when logged out.
  Future<void> _sendHeartbeat() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    try {
      await ref.read(profileRepositoryProvider).updateLastSeen(negotiatorId: session.user.id);
    } catch (_) {
      // Swallowed -- see doc comment above.
    }
  }
```

Add `import 'dart:async';` to the top of `main.dart` (for `Timer`) and `import 'features/profile/profile_providers.dart';` (for `profileRepositoryProvider`) alongside the existing feature imports.

Do not remove or reorder any of the existing methods in `_RenlyAppState` (`_registerToken`, `_stringData`, `_navigateFromMessage`, `_handleForegroundMessage`, `build`) -- this step only adds the `with WidgetsBindingObserver` mixin, the `_presenceHeartbeat` field, the observer registration lines inside the existing `initState`, a new `dispose`, and the two new methods (`didChangeAppLifecycleState`, `_sendHeartbeat`).

- [ ] **Step 3: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

This task's own logic (`_sendHeartbeat`, lifecycle dispatch) is not unit-tested — it is a thin wrapper around a Supabase-boundary call and Flutter's own `AppLifecycleState` dispatch, consistent with this project's established convention of not unit-testing app-lifecycle/Supabase-boundary glue. It is manually verified after Task 1's migration is applied (see this plan's own final manual-verification note).

- [ ] **Step 4: Run the full existing test suite to confirm no regression**

Run: `cd app && flutter test`
Expected: All existing tests still pass (this change adds a mixin and new methods to `_RenlyAppState`; it must not alter `RenlyApp`'s existing `build()` output or any existing behavior any current test asserts on).

- [ ] **Step 5: Commit**

```bash
git add app/lib/main.dart
git commit -m "feat: send a presence heartbeat on app resume and while active"
```

---

### Task 6: Rollout — `conversation_list_screen.dart` and `marketplace_screen.dart`

These are the 2 sites that already hand-roll the exact avatar-circle pattern `NegotiatorAvatar` generalizes — this task **replaces** that existing code, it does not add alongside it.

**Files:**
- Modify: `app/lib/features/collaboration/conversation_list_screen.dart`
- Modify: `app/lib/features/listing/marketplace_screen.dart`
- Test: `app/test/features/collaboration/conversation_list_screen_test.dart`
- Test: `app/test/features/listing/marketplace_screen_test.dart`

**Interfaces:**
- Consumes: `NegotiatorAvatar` (Task 4), `ListingOwner.avatarUrl`/`isOnline` (Task 2).

- [ ] **Step 1: Read both files fresh**

Read `app/lib/features/collaboration/conversation_list_screen.dart` around its `counterparty` row (previously confirmed at approximately lines 516-523, showing `CircleAvatar(radius: 22, backgroundColor: const Color(0xFF0B0F19), child: Text(counterparty.fullName.isNotEmpty ? ... : '?', ...))`) and `app/lib/features/listing/marketplace_screen.dart` around its listing-owner row (previously confirmed at approximately lines 684-691, showing `CircleAvatar(radius: 15, backgroundColor: const Color(0xFF1E293B), child: Text(owner.fullName.isNotEmpty ? ... : '?', ...))`) to get their exact current line numbers and surrounding structure before editing -- both may have shifted slightly since last read this session.

- [ ] **Step 2: Replace `conversation_list_screen.dart`'s hand-rolled avatar**

Replace:

```dart
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF0B0F19),
                    child: Text(
                      counterparty.fullName.isNotEmpty ? counterparty.fullName[0].toUpperCase() : '?',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                    ),
                  ),
```

with:

```dart
                  NegotiatorAvatar(
                    fullName: counterparty.fullName,
                    avatarUrl: counterparty.avatarUrl,
                    isOnline: counterparty.isOnline,
                  ),
```

Add `import '../../core/widgets/negotiator_avatar.dart';` to this file's import list.

- [ ] **Step 3: Replace `marketplace_screen.dart`'s hand-rolled avatar**

Replace:

```dart
                                  CircleAvatar(
                                    radius: 15,
                                    backgroundColor: const Color(0xFF1E293B),
                                    child: Text(
                                      owner.fullName.isNotEmpty ? owner.fullName[0].toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
```

with:

```dart
                                  NegotiatorAvatar(
                                    fullName: owner.fullName,
                                    avatarUrl: owner.avatarUrl,
                                    isOnline: owner.isOnline,
                                    size: 30,
                                  ),
```

Add `import '../../core/widgets/negotiator_avatar.dart';` to this file's import list.

- [ ] **Step 4: Add a regression test to each screen's existing test file**

Read each test file's existing fixtures first (both already construct a `ListingOwner`/counterparty fixture for their respective rows), then add ONE test per file reusing that fixture with `isOnline: true` and asserting `NegotiatorAvatar` is present, e.g. for `conversation_list_screen_test.dart`:

```dart
  testWidgets('shows a NegotiatorAvatar for the counterparty', (tester) async {
    // Reuse this file's existing pump/fixture setup for a screen showing at
    // least one conversation row -- see the file's own established
    // convention above for the exact pump call and fixture construction.
    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byType(NegotiatorAvatar), findsWidgets);
  });
```

and the analogous test in `marketplace_screen_test.dart` for its own listing-card row. Import `package:renly/core/widgets/negotiator_avatar.dart` in both test files.

- [ ] **Step 5: Run both test files**

Run: `cd app && flutter test test/features/collaboration/conversation_list_screen_test.dart test/features/listing/marketplace_screen_test.dart`
Expected: PASS, including the 2 new tests.

- [ ] **Step 6: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/collaboration/conversation_list_screen.dart app/lib/features/listing/marketplace_screen.dart app/test/features/collaboration/conversation_list_screen_test.dart app/test/features/listing/marketplace_screen_test.dart
git commit -m "feat: roll out NegotiatorAvatar to Messages and Marketplace"
```

---

### Task 7: Rollout — matching-family screens

**Files:**
- Modify: `app/lib/features/matching/my_matches_screen.dart`
- Modify: `app/lib/features/matching/matches_for_requirement_screen.dart`
- Modify: `app/lib/features/matching/matches_for_listing_screen.dart`
- Test: `app/test/features/matching/my_matches_screen_test.dart`
- Test: `app/test/features/matching/matches_for_requirement_screen_test.dart`
- Test: `app/test/features/matching/matches_for_listing_screen_test.dart`

**Interfaces:**
- Consumes: `NegotiatorAvatar` (Task 4), `ListingOwner.avatarUrl`/`isOnline` (Task 2).

None of these 3 screens currently render any avatar -- each has a plain `Text('${owner.fullName} (REN: ${owner.renNumber})')` row. This task wraps each in a `Row` with a small `NegotiatorAvatar` (size 28) beside it.

- [ ] **Step 1: Read all 3 files fresh**

Confirm current line numbers/structure around each owner-display `Text` (previously confirmed at approximately: `my_matches_screen.dart` lines 84 and 93 inside the same `Column`; `matches_for_requirement_screen.dart` line 74; `matches_for_listing_screen.dart` line 74).

- [ ] **Step 2: Update `my_matches_screen.dart`**

Replace both occurrences of this shape (once for `candidate.requirementOwner`, once for `candidate.listingOwner`):

```dart
                            Text(
                              '${candidate.requirementOwner.fullName} (REN: ${candidate.requirementOwner.renNumber})',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
```

with:

```dart
                            Row(
                              children: [
                                NegotiatorAvatar(
                                  fullName: candidate.requirementOwner.fullName,
                                  avatarUrl: candidate.requirementOwner.avatarUrl,
                                  isOnline: candidate.requirementOwner.isOnline,
                                  size: 28,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${candidate.requirementOwner.fullName} (REN: ${candidate.requirementOwner.renNumber})',
                                    style: Theme.of(context).textTheme.labelSmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
```

and the mirrored replacement for the `candidate.listingOwner` occurrence (same shape, `requirementOwner` → `listingOwner` throughout). Add `import '../../core/widgets/negotiator_avatar.dart';` to this file.

- [ ] **Step 3: Update `matches_for_requirement_screen.dart`**

Replace:

```dart
                          Text(
                            '${candidate.listingOwner.fullName} (REN: ${candidate.listingOwner.renNumber})',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
```

with:

```dart
                          Row(
                            children: [
                              NegotiatorAvatar(
                                fullName: candidate.listingOwner.fullName,
                                avatarUrl: candidate.listingOwner.avatarUrl,
                                isOnline: candidate.listingOwner.isOnline,
                                size: 28,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${candidate.listingOwner.fullName} (REN: ${candidate.listingOwner.renNumber})',
                                  style: Theme.of(context).textTheme.labelSmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
```

Add `import '../../core/widgets/negotiator_avatar.dart';` to this file.

- [ ] **Step 4: Update `matches_for_listing_screen.dart`**

Same shape as Step 3, `listingOwner` → `requirementOwner` throughout (this screen shows the requirement side):

```dart
                          Row(
                            children: [
                              NegotiatorAvatar(
                                fullName: candidate.requirementOwner.fullName,
                                avatarUrl: candidate.requirementOwner.avatarUrl,
                                isOnline: candidate.requirementOwner.isOnline,
                                size: 28,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${candidate.requirementOwner.fullName} (REN: ${candidate.requirementOwner.renNumber})',
                                  style: Theme.of(context).textTheme.labelSmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
```

Add `import '../../core/widgets/negotiator_avatar.dart';` to this file.

- [ ] **Step 5: Add one regression test per screen**

Read each existing test file's fixtures first, then add one test per file asserting `find.byType(NegotiatorAvatar)` is present after pumping a screen state that already has at least one match candidate (reuse each file's existing "renders a candidate" test's own setup). Import `package:renly/core/widgets/negotiator_avatar.dart` in each.

- [ ] **Step 6: Run all 3 test files**

Run: `cd app && flutter test test/features/matching/my_matches_screen_test.dart test/features/matching/matches_for_requirement_screen_test.dart test/features/matching/matches_for_listing_screen_test.dart`
Expected: PASS, including the 3 new tests.

- [ ] **Step 7: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/matching/my_matches_screen.dart app/lib/features/matching/matches_for_requirement_screen.dart app/lib/features/matching/matches_for_listing_screen.dart app/test/features/matching/my_matches_screen_test.dart app/test/features/matching/matches_for_requirement_screen_test.dart app/test/features/matching/matches_for_listing_screen_test.dart
git commit -m "feat: roll out NegotiatorAvatar to My Matches and matches-for screens"
```

---

### Task 8: Rollout — requirement/request-family screens

**Files:**
- Modify: `app/lib/features/collaboration/my_requests_screen.dart`
- Modify: `app/lib/features/requirement/requirement_board_screen.dart`
- Modify: `app/lib/features/requirement/requirement_detail_screen.dart`
- Test: `app/test/features/collaboration/my_requests_screen_test.dart`
- Test: `app/test/features/requirement/requirement_board_screen_test.dart`
- Test: `app/test/features/requirement/requirement_detail_screen_test.dart`

**Interfaces:**
- Consumes: `NegotiatorAvatar` (Task 4), `ListingOwner.avatarUrl`/`isOnline` (Task 2).

- [ ] **Step 1: Read all 3 files fresh**

Confirm current line numbers/structure (previously confirmed at approximately: `my_requests_screen.dart` line 130, a `Text` inside a `BrutalistCard`'s `Column`; `requirement_board_screen.dart` line 160, inside an `ownerAsync.when(... data: (owner) => Text(...))`; `requirement_detail_screen.dart` lines 147-148, inside an `ownerAsync.when(... data: (owner) => Column(children: [Text(owner.fullName, ...), Text('REN: ...', ...)]))`).

- [ ] **Step 2: Update `my_requests_screen.dart`**

Replace:

```dart
                      Text(
                        '${counterpartyOwner.fullName} (REN: ${counterpartyOwner.renNumber})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
```

with:

```dart
                      Row(
                        children: [
                          NegotiatorAvatar(
                            fullName: counterpartyOwner.fullName,
                            avatarUrl: counterpartyOwner.avatarUrl,
                            isOnline: counterpartyOwner.isOnline,
                            size: 32,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${counterpartyOwner.fullName} (REN: ${counterpartyOwner.renNumber})',
                              style: Theme.of(context).textTheme.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
```

This file lives at `app/lib/features/collaboration/my_requests_screen.dart`, 2 directories under `app/lib/`, same depth as `app/lib/core/widgets/negotiator_avatar.dart` is under `app/lib/`. Add `import '../../core/widgets/negotiator_avatar.dart';` to this file's import list.

- [ ] **Step 3: Update `requirement_board_screen.dart`**

Replace:

```dart
                                            data: (owner) => Text(
                                              '${owner.fullName} (REN: ${owner.renNumber})',
                                              style: Theme.of(context).textTheme.labelSmall,
                                            ),
```

with:

```dart
                                            data: (owner) => Row(
                                              children: [
                                                NegotiatorAvatar(
                                                  fullName: owner.fullName,
                                                  avatarUrl: owner.avatarUrl,
                                                  isOnline: owner.isOnline,
                                                  size: 24,
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    '${owner.fullName} (REN: ${owner.renNumber})',
                                                    style: Theme.of(context).textTheme.labelSmall,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
```

This file lives at `app/lib/features/requirement/requirement_board_screen.dart`, the same depth under `app/lib/` as `conversation_list_screen.dart`. Add `import '../../core/widgets/negotiator_avatar.dart';` to this file's import list.

- [ ] **Step 4: Update `requirement_detail_screen.dart`**

Replace:

```dart
                      data: (owner) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(owner.fullName, style: Theme.of(context).textTheme.titleMedium),
                          Text('REN: ${owner.renNumber}', style: Theme.of(context).textTheme.labelSmall),
                        ],
                      ),
```

with:

```dart
                      data: (owner) => Row(
                        children: [
                          NegotiatorAvatar(
                            fullName: owner.fullName,
                            avatarUrl: owner.avatarUrl,
                            isOnline: owner.isOnline,
                            size: 40,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(owner.fullName, style: Theme.of(context).textTheme.titleMedium),
                              Text('REN: ${owner.renNumber}', style: Theme.of(context).textTheme.labelSmall),
                            ],
                          ),
                        ],
                      ),
```

This file lives at `app/lib/features/requirement/requirement_detail_screen.dart`, the same depth under `app/lib/` as `conversation_list_screen.dart`. Add `import '../../core/widgets/negotiator_avatar.dart';` to this file's import list.

- [ ] **Step 5: Add one regression test per screen**

Read each existing test file's fixtures first, then add one test per file asserting `find.byType(NegotiatorAvatar)` is present after pumping a screen state that already shows an owner row (reuse each file's own existing relevant test setup). Import `package:renly/core/widgets/negotiator_avatar.dart` in each.

- [ ] **Step 6: Run all 3 test files**

Run: `cd app && flutter test test/features/collaboration/my_requests_screen_test.dart test/features/requirement/requirement_board_screen_test.dart test/features/requirement/requirement_detail_screen_test.dart`
Expected: PASS, including the 3 new tests.

- [ ] **Step 7: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/collaboration/my_requests_screen.dart app/lib/features/requirement/requirement_board_screen.dart app/lib/features/requirement/requirement_detail_screen.dart app/test/features/collaboration/my_requests_screen_test.dart app/test/features/requirement/requirement_board_screen_test.dart app/test/features/requirement/requirement_detail_screen_test.dart
git commit -m "feat: roll out NegotiatorAvatar to My Requests and Requirement Board/Detail"
```

---

### Task 9: Rollout — Property Detail's Agent Card (the original ask)

**Files:**
- Modify: `app/lib/features/listing/property_detail_screen.dart`
- Test: `app/test/features/listing/property_detail_screen_test.dart`

**Interfaces:**
- Consumes: `NegotiatorAvatar` (Task 4), `ListingOwner.avatarUrl`/`isOnline` (Task 2).

- [ ] **Step 1: Read `property_detail_screen.dart` fresh**

This file has been edited many times this session (most recently for badge/button recoloring) -- read its current `_AgentCard` class in full (previously confirmed at class-declaration line 857) before editing, since exact line numbers within it may have shifted.

- [ ] **Step 2: Add `NegotiatorAvatar` to `_AgentCard`**

`_AgentCard`'s `build` method currently returns a `Container` whose `child` is a `Row` with an `Expanded` (name/REN/rating column) and an `OutlinedButton.icon` (Message button). Add a `NegotiatorAvatar` as the Row's first child, before the `Expanded`:

```dart
          child: Row(
            children: [
              NegotiatorAvatar(
                fullName: owner.fullName,
                avatarUrl: owner.avatarUrl,
                isOnline: owner.isOnline,
                size: 56,
              ),
              const SizedBox(width: 12),
              Expanded(
```

(the existing `Expanded(child: Column(...))` and everything after it in the `Row`'s `children` list is unchanged -- only the `NegotiatorAvatar` + `SizedBox` are inserted before it, and the `Row`'s own opening changes from `child: Row(\n            children: [\n              Expanded(` to the 5 lines shown above).

Add `import '../../core/widgets/negotiator_avatar.dart';` to this file's import list.

- [ ] **Step 3: Add a regression test**

Read `app/test/features/listing/property_detail_screen_test.dart`'s existing fixtures for `_AgentCard` (it already has tests asserting real rating display -- reuse that same pump/fixture setup), then add:

```dart
  testWidgets('shows a NegotiatorAvatar for the listing owner', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byType(NegotiatorAvatar), findsOneWidget);
  });
```

Import `package:renly/core/widgets/negotiator_avatar.dart` in the test file. Adjust the exact router/`_wrap` call to match this test file's own already-established convention (read the file's other tests first -- do not invent a different pump pattern).

- [ ] **Step 4: Run the test file**

Run: `cd app && flutter test test/features/listing/property_detail_screen_test.dart`
Expected: PASS, all tests including the new one.

- [ ] **Step 5: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/listing/property_detail_screen.dart app/test/features/listing/property_detail_screen_test.dart
git commit -m "feat: show a real avatar and online dot on Property Detail's Agent Card"
```

---

### Task 10: Upload UI in `ProfileScreen`

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart`
- Modify: `app/assets/translations/en.json`
- Modify: `app/assets/translations/ms.json`
- Test: `app/test/features/profile/profile_screen_test.dart`

**Interfaces:**
- Consumes: `ProfileRepository.uploadAvatar`/`updateAvatarUrl` (Task 3), `Profile.avatarUrl` (Task 3).

- [ ] **Step 1: Read `profile_screen.dart` fresh**

Confirm `_EditForm`'s current structure (previously confirmed: `_EditFormState` has `_territoryController`, `_specialisationController`, `_submitting`, `_submitError`, a `_save()` method, and a `build()` returning a `Column` of 2 `TextField`s + error text + a save `BrutalistButton`).

- [ ] **Step 2: Add the 2 new l10n keys**

In `app/assets/translations/en.json`, add near the other `profile_*` keys:

```json
  "profile_avatar_upload_hint": "Tap to add a photo",
```

In `app/assets/translations/ms.json`, add at the same relative position:

```json
  "profile_avatar_upload_hint": "Ketik untuk tambah gambar",
```

- [ ] **Step 3: Add the avatar picker to `_EditForm`**

In `app/lib/features/profile/profile_screen.dart`, add `import 'dart:typed_data';`, `import 'package:image_picker/image_picker.dart';`, and `import '../../core/widgets/negotiator_avatar.dart';` to the top imports. In `_EditFormState`, add an `_uploadingAvatar` bool field and an `_uploadAvatar` method, and add a tappable avatar row at the top of `build()`'s `Column`:

```dart
class _EditFormState extends ConsumerState<_EditForm> {
  late final TextEditingController _territoryController;
  late final TextEditingController _specialisationController;
  bool _submitting = false;
  bool _uploadingAvatar = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _territoryController = TextEditingController(text: widget.profile.territory ?? '');
    _specialisationController = TextEditingController(text: widget.profile.propertySpecialisation ?? '');
  }

  // After a successful save, ref.invalidate(myProfileProvider) causes
  // ProfileScreen to rebuild with a fresh Profile instance -- but since
  // _EditForm occupies the same slot with the same widget type, Flutter
  // reuses this State and initState does NOT re-run, so the controllers
  // would otherwise never resync to the newly-fetched canonical values.
  @override
  void didUpdateWidget(covariant _EditForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.profile.territory != oldWidget.profile.territory) {
      _territoryController.text = widget.profile.territory ?? '';
    }
    if (widget.profile.propertySpecialisation != oldWidget.profile.propertySpecialisation) {
      _specialisationController.text = widget.profile.propertySpecialisation ?? '';
    }
  }

  @override
  void dispose() {
    _territoryController.dispose();
    _specialisationController.dispose();
    super.dispose();
  }

  Future<void> _uploadAvatar() async {
    final negotiatorId = ref.read(currentNegotiatorIdProvider);
    if (negotiatorId == null) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final Uint8List bytes = await picked.readAsBytes();
      final repository = ref.read(profileRepositoryProvider);
      final avatarUrl = await repository.uploadAvatar(negotiatorId: negotiatorId, bytes: bytes);
      await repository.updateAvatarUrl(negotiatorId: negotiatorId, avatarUrl: avatarUrl);
      ref.invalidate(myProfileProvider);
    } catch (_) {
      if (mounted) setState(() => _submitError = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('profile_save_success'.tr())),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: GestureDetector(
            onTap: _uploadingAvatar ? null : _uploadAvatar,
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    NegotiatorAvatar(fullName: widget.profile.fullName, avatarUrl: widget.profile.avatarUrl, size: 72),
                    if (_uploadingAvatar) const CircularProgressIndicator(),
                  ],
                ),
                const SizedBox(height: 6),
                Text('profile_avatar_upload_hint'.tr(), style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
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
        BrutalistButton(
          label: 'profile_save'.tr(),
          icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
          onPressed: _submitting ? null : _save,
        ),
      ],
    );
  }
}
```

`NegotiatorAvatar` is reused here even though this is the viewer's OWN profile (not "another negotiator") -- it is still the correct widget for "a circular photo-or-initials avatar," and `isOnline` is simply left at its default `false` (irrelevant for a self-view, no dot shown, matching the design doc's own "no dot when false" behavior harmlessly).

- [ ] **Step 4: Add a regression test**

Read `app/test/features/profile/profile_screen_test.dart`'s existing fixtures first, then add:

```dart
  testWidgets('shows a tappable avatar with the upload hint', (tester) async {
    // Reuse this file's existing pump/fixture setup for a loaded profile --
    // see the file's own established convention above for the exact pump
    // call and fixture construction.
    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.byType(NegotiatorAvatar), findsOneWidget);
    expect(find.text('profile_avatar_upload_hint'.tr()), findsOneWidget);
  });
```

Import `package:renly/core/widgets/negotiator_avatar.dart` in the test file.

- [ ] **Step 5: Run the test file**

Run: `cd app && flutter test test/features/profile/profile_screen_test.dart`
Expected: PASS, all tests including the new one.

- [ ] **Step 6: Run l10n parity check**

Run:
```bash
cd app && python3 -c "
import json
en=json.load(open('assets/translations/en.json'))
ms=json.load(open('assets/translations/ms.json'))
assert set(en) == set(ms), (set(en)-set(ms), set(ms)-set(en))
print('parity ok', len(en))
"
```
Expected: `parity ok <N>` with no assertion error.

- [ ] **Step 7: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/profile/profile_screen.dart app/assets/translations/en.json app/assets/translations/ms.json app/test/features/profile/profile_screen_test.dart
git commit -m "feat: add avatar upload to Profile screen"
```

---

## Manual Verification (after all tasks, once Task 1's migration and bucket are applied)

This plan's repository methods (`uploadAvatar`, `updateAvatarUrl`, `updateLastSeen`) and the `main.dart` heartbeat wiring are not unit-tested, per this project's established convention. After Task 1's migration is applied via the Supabase SQL Editor (same manual process as every prior migration):

1. Upload a photo via Profile screen — confirm it appears there, and confirm (via `supabase db query --linked`) that `negotiator.avatar_url` is a reachable public URL.
2. Confirm the same photo appears at each of the 9 rollout call sites for that negotiator (a listing/requirement they own, a match/request involving them, a conversation with them).
3. Force-close and reopen the app while logged in — confirm (via `supabase db query --linked`) that `negotiator.last_seen_at` updates to a recent timestamp.
4. Wait 2+ minutes with the app backgrounded, then check another account's view of that negotiator — confirm the online dot disappears once `last_seen_at` is stale.
