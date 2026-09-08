# Profile & Settings Ultra-Premium Restyle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle `ProfileScreen` to match the Stitch "Profile & Settings (Ultra-Premium Edition)" mockup, treating every mockup element as Real (backed by existing or newly-computed data), Reframed (honest copy over a real mechanic), or Dropped (no backing, logged as a future item).

**Architecture:** One new repository method (`ProfileRepository.fetchCoBrokeVolume`, no migration — a client-side PostgREST-embedding query already covered by existing RLS) plus a single-screen restructure of `ProfileScreen`/`_EditForm` into a header, a 4-stat grid, a split edit-vs-display avatar/form area, and two new real shortcut rows (Auto-Match Radar, Security & Biometrics) that read/write data other screens already own.

**Tech Stack:** Flutter/Riverpod, Supabase (Postgres via PostgREST embedding, no migration).

## Global Constraints

- Never fabricate data: every new/changed element renders nothing decorative when its backing value is null/absent/zero — no fabricated certifying-body names, split defaults, license expiry dates, wallet balances, or bank details anywhere in this screen.
- Dropped for this pass (log as future sub-projects, do not build): Digital Card, Co-Broke Escrow Wallet, Bank Account & Payouts, Default Split Rate, multi-tag Designated Areas, license expiry date, app-version footer.
- The avatar tap-to-upload section must remain ALWAYS VISIBLE, never gated behind the new Edit-Profile toggle — this is a real, already-shipped feature (`app/test/features/profile/profile_screen_test.dart`'s `'shows a tappable avatar with the upload hint'` test must keep passing with zero changes to its own test body).
- The Auto-Match Radar toggle on this screen must call `SettingsRepository.updateNotificationPreferences` with ONLY `notifyMatch:` set (never pass `notifyMessage`/`notifyCobrokeRequest`) — this method performs a genuine partial update and passing the other two would clobber concurrent writes to those columns.
- The Security & Biometrics row is a read-only status display + navigation shortcut to `/settings/account` — it must NOT duplicate `_BiometricToggle`'s own enable/disable logic.
- `fetchCoBrokeVolume` and every other Supabase-boundary repository method are not unit-tested in this project — manually verified later. Widget tests use provider overrides on the existing `_wrap` helper in `profile_screen_test.dart`, extended (not duplicated).

---

### Task 1: `ProfileRepository.fetchCoBrokeVolume`

**Files:**
- Modify: `app/lib/features/profile/profile_repository.dart`
- Modify: `app/lib/features/profile/profile_providers.dart`

**Interfaces:**
- Produces: `ProfileRepository.fetchCoBrokeVolume(String negotiatorId)` (`Future<double>`) — consumed by Task 4. `profileCountsProvider`'s tuple type changes from `(int, int)` to `(int, int, double)` (active listings, deals closed, co-broke volume) — consumed by Task 4.

- [ ] **Step 1: Add `fetchCoBrokeVolume` to `ProfileRepository`**

In `app/lib/features/profile/profile_repository.dart`, add this method after `countDealsClosed()`:

```dart
  /// Sums `listing.price` across every accepted agreement this negotiator
  /// is a party to. No `negotiator_id` filter in the query itself --
  /// `agreement_select`'s own RLS policy (0009_agreement.sql) already
  /// scopes visible rows to ones where the current user is a party (the
  /// agreement's own initiator, or the owner of the underlying match's
  /// listing/requirement), same reasoning as countDealsClosed() above. The
  /// `negotiatorId` param exists only for interface symmetry with this
  /// file's other counting methods.
  ///
  /// Returns 0.0 (never null, never a fabricated non-zero fallback) when
  /// there are no accepted agreements yet -- a real "no volume yet" fact.
  Future<double> fetchCoBrokeVolume(String negotiatorId) async {
    final rows = await _client
        .from('agreement')
        .select('cobroke_request!inner(match!inner(listing!inner(price)))')
        .eq('status', 'accepted') as List;
    var total = 0.0;
    for (final row in rows) {
      final cobrokeRequest = row['cobroke_request'] as Map<String, dynamic>?;
      final match = cobrokeRequest?['match'] as Map<String, dynamic>?;
      final listing = match?['listing'] as Map<String, dynamic>?;
      final price = listing?['price'] as num?;
      if (price != null) total += price.toDouble();
    }
    return total;
  }
```

- [ ] **Step 2: Extend `profileCountsProvider`'s tuple to include volume**

In `app/lib/features/profile/profile_providers.dart`, replace the whole file with:

```dart
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

/// (activeListings, dealsClosed, coBrokeVolume) -- all three fetched
/// concurrently via Future.wait, not sequential awaits, same
/// concurrent-resolution pattern established across every prior
/// milestone's repository code. Future.wait<dynamic> since the three
/// results have different types (int, int, double); each is cast back to
/// its real type before returning the tuple.
final profileCountsProvider = FutureProvider.autoDispose<(int, int, double)>((ref) async {
  final negotiatorId = ref.watch(currentNegotiatorIdProvider);
  if (negotiatorId == null) {
    throw StateError('profileCountsProvider watched with no active session');
  }
  final repository = ref.watch(profileRepositoryProvider);
  final results = await Future.wait<dynamic>([
    repository.countActiveListings(negotiatorId),
    repository.countDealsClosed(),
    repository.fetchCoBrokeVolume(negotiatorId),
  ]);
  return (results[0] as int, results[1] as int, results[2] as double);
});
```

- [ ] **Step 3: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: errors in `profile_screen.dart` referencing `counts.$1`/`counts.$2` as a 2-tuple against the new 3-tuple type — this is EXPECTED at this point, since Task 1 only changes the provider/repository, not the screen. Confirm the errors are ONLY in `profile_screen.dart` (the file Task 5 will fix) and nowhere else. Do not fix `profile_screen.dart` in this task.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/profile/profile_repository.dart app/lib/features/profile/profile_providers.dart
git commit -m "feat: add real Co-Broke Volume computation to ProfileRepository"
```

`fetchCoBrokeVolume` is a Supabase-boundary method, not unit-tested here — manually verified later against real accepted agreements, per this project's established convention. The `flutter analyze` errors introduced by this task are resolved by Task 3, which updates `profile_screen.dart`'s own consumption of the tuple.

---

### Task 2: Header restyle

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart`
- Test: `app/test/features/profile/profile_screen_test.dart`

**Interfaces:**
- Consumes: `myProfileProvider` (already watched), `unreadNotificationCountProvider` (real, already used by `marketplace_screen.dart` for its own bell badge — import from wherever that file imports it).

- [ ] **Step 1: Read `app/lib/features/listing/marketplace_screen.dart`'s header block fresh**

Confirm its exact current bell-icon-with-unread-dot structure (a `Stack` with an `IconButton` using `PhosphorIcons.bellSimple(PhosphorIconsStyle.bold)` navigating to `/notifications`, plus a `Positioned` red dot shown `if (unreadCount > 0)`) and the exact import path for `unreadNotificationCountProvider` — copy both verbatim.

- [ ] **Step 2: Replace `ProfileScreen`'s bare `AppBar`**

`ProfileScreen`'s current structure returns a single `Scaffold(appBar: ..., body: SafeArea(child: profileAsync.when(...)))` — the `AppBar` is a SIBLING of the body's `profileAsync.when(...)`, not nested inside its `data:` callback, so `profile` (only bound inside that callback) is NOT in scope where the `AppBar` is constructed. Mirror the exact same pattern `property_detail_screen.dart` already uses for this identical problem (its own share button, which needs the fetched `listing` from inside `listingAsync.when`'s own `data:` branch while building its `AppBar` outside it): compute a nullable local from `.valueOrNull` BEFORE the `Scaffold`, and null-guard the action.

Add, near the top of `build()`, alongside the existing `profileAsync`/`countsAsync` locals:

```dart
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final ownProfile = profileAsync.valueOrNull;
```

Replace:

```dart
      appBar: AppBar(title: Text('profile_title'.tr())),
```

with (add the imports for `RStarBadge`, `AppColors`, `PhosphorIcons`, `SharePlus`/`ShareParams`, `go_router`'s `context.push`, and `unreadNotificationCountProvider` — all already used elsewhere in this codebase, mirror their exact existing import paths from `property_detail_screen.dart`/`marketplace_screen.dart`):

```dart
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const RStarBadge(size: 28),
            const SizedBox(width: 8),
            Text(
              'app_name'.tr(),
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: AppColors.ink,
                    fontSize: 20,
                    letterSpacing: -1.0,
                    height: 1,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(PhosphorIcons.shareNetwork(PhosphorIconsStyle.bold)),
            onPressed: ownProfile == null
                ? null
                : () => SharePlus.instance.share(
                      ShareParams(text: 'REN ${ownProfile.renNumber ?? '-'} • ${ownProfile.fullName}'),
                    ),
          ),
          Stack(
            children: [
              IconButton(
                icon: Icon(PhosphorIcons.bellSimple(PhosphorIconsStyle.bold)),
                onPressed: () => context.push('/notifications'),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
```

This matches `property_detail_screen.dart`'s own `final ownListing = listingAsync.valueOrNull;` + `onPressed: ownListing == null ? null : ...` pattern exactly — the share icon is disabled for the single frame before `profileAsync` first resolves, then enabled for the rest of the screen's life (this screen has no loading-to-error transition back to null once loaded, so there is no flicker-back-to-disabled case to handle).

- [ ] **Step 3: Add a regression test**

In `app/test/features/profile/profile_screen_test.dart`, add `unreadNotificationCountProvider.overrideWithValue(0)` to the `_wrap` helper's `overrides` list (read the file fresh first to get its exact current override list before editing), then add:

```dart
  testWidgets('shows the renly wordmark and a share/bell header', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('renly'), findsOneWidget);
    expect(find.byIcon(PhosphorIcons.shareNetwork(PhosphorIconsStyle.bold)), findsOneWidget);
    expect(find.byIcon(PhosphorIcons.bellSimple(PhosphorIconsStyle.bold)), findsOneWidget);
  });
```

Import `PhosphorIcons` in the test file if not already imported.

- [ ] **Step 4: Run the test file**

Run: `cd app && flutter test test/features/profile/profile_screen_test.dart`
Expected: all existing tests still pass (none of their own assertions reference the old bare `AppBar`) plus the new one.

- [ ] **Step 5: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: the errors from Task 1 about `counts.$1`/`counts.$2` against a 3-tuple still present (unrelated to this task, fixed in Task 3) — no NEW errors introduced by this task.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/profile/profile_screen.dart app/test/features/profile/profile_screen_test.dart
git commit -m "feat: add a real header (wordmark, share, notifications) to Profile screen"
```

---

### Task 3: Verified badge icon + Co-Broke Volume stat card

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart`
- Test: `app/test/features/profile/profile_screen_test.dart`

**Interfaces:**
- Consumes: `profile.verificationStatus` (real, existing), `profileCountsProvider`'s new `(int, int, double)` tuple from Task 1.
- Produces: fixes the `flutter analyze` errors introduced by Task 1.

- [ ] **Step 1: Read `_AgentCard`'s verified-checkmark code in `property_detail_screen.dart` fresh**

Confirm the exact current icon/color (`Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.fill), size: 15, color: const Color(0xFF059669))`, shown conditionally when `owner.verificationStatus == 'approved'`) to copy verbatim.

- [ ] **Step 2: Add the verified icon beside the name**

Replace:

```dart
                  Text(profile.fullName, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Chip(label: Text(_statusLabel(profile.verificationStatus))),
```

with:

```dart
                  Row(
                    children: [
                      Flexible(
                        child: Text(profile.fullName, style: Theme.of(context).textTheme.headlineMedium, overflow: TextOverflow.ellipsis),
                      ),
                      if (profile.verificationStatus == 'approved') ...[
                        const SizedBox(width: 6),
                        Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.fill), size: 18, color: const Color(0xFF059669)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Chip(label: Text(_statusLabel(profile.verificationStatus))),
```

- [ ] **Step 3: Add the 4th stat card**

Replace:

```dart
                  countsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (error, stack) => const SizedBox.shrink(),
                    data: (counts) => Row(
                      children: [
                        Expanded(child: _StatCard(value: '${counts.$1}', label: 'profile_active_listings_label'.tr())),
                        const SizedBox(width: 12),
                        Expanded(child: _StatCard(value: '${counts.$2}', label: 'profile_deals_closed_label'.tr())),
                        const SizedBox(width: 12),
                        Expanded(child: _TrustScoreCard(negotiatorId: profile.negotiatorId)),
                      ],
                    ),
                  ),
```

with:

```dart
                  countsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (error, stack) => const SizedBox.shrink(),
                    data: (counts) => Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _StatCard(value: '${counts.$1}', label: 'profile_active_listings_label'.tr())),
                            const SizedBox(width: 12),
                            Expanded(child: _StatCard(value: '${counts.$2}', label: 'profile_deals_closed_label'.tr())),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _TrustScoreCard(negotiatorId: profile.negotiatorId)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                value: ListingFormatting.formatPrice(counts.$3, 'sale'),
                                label: 'profile_cobroke_volume_label'.tr(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
```

Add `import '../listing/listing_formatting.dart';` to reuse the same real currency-formatting helper already used across the Listing feature (e.g. `ListingFormatting.formatPrice`) rather than hand-rolling a new `RM`-prefixed formatter — read that file fresh first to confirm `formatPrice`'s exact signature (it takes a `transactionType` param purely for a "/mo" rent suffix; passing `'sale'` here renders a plain `RM X` amount with no suffix, which is what a volume figure needs).

- [ ] **Step 4: Add the new l10n key**

In `app/assets/translations/en.json`, add near `profile_deals_closed_label`:

```json
  "profile_cobroke_volume_label": "Co-Broke Vol.",
```

In `app/assets/translations/ms.json`, add at the same relative position:

```json
  "profile_cobroke_volume_label": "Vol. Co-Broke",
```

- [ ] **Step 5: Add a regression test**

In `app/test/features/profile/profile_screen_test.dart`, update the `_wrap` helper's `counts` param default and every call site that constructs a counts tuple to the new 3-tuple shape (read the file fresh to find every `(int, int)` literal passed as `counts:`, e.g. `(5, 3)`, and change each to `(5, 3, 125000.0)` or similar), then add:

```dart
  testWidgets('shows the real Co-Broke Volume stat', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, counts: (5, 3, 250000.0)));
    await tester.pumpAndSettle();

    expect(find.text('Co-Broke Vol.'), findsOneWidget);
    expect(find.textContaining('250,000'), findsOneWidget);
  });
```

Adjust the exact expected formatted-price substring to match `ListingFormatting.formatPrice`'s real output for `250000.0` (read that function's implementation fresh to confirm the exact thousands-separator/decimal format it produces, and use that exact substring in the assertion rather than guessing).

- [ ] **Step 6: Run the test file**

Run: `cd app && flutter test test/features/profile/profile_screen_test.dart`
Expected: all tests pass, including the new one and the updated tuple literals in existing tests.

- [ ] **Step 7: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!` — this closes out the errors Task 1 introduced.

- [ ] **Step 8: Run l10n parity check**

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
Expected: `parity ok <N>`, no assertion error.

- [ ] **Step 9: Commit**

```bash
git add app/lib/features/profile/profile_screen.dart app/test/features/profile/profile_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: show a real verified checkmark and Co-Broke Volume stat on Profile"
```

---

### Task 4: Split the avatar (always-visible) from the Edit Profile toggle

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart`
- Test: `app/test/features/profile/profile_screen_test.dart`

**Interfaces:**
- Produces: `_EditFormState` gains a new `bool _editing` field (default `false`); the avatar `Stack`+upload-hint block moves OUT of `_EditForm` and into `ProfileScreen.build()` directly, always rendered.

This is the task that resolves the CRITICAL design nuance: the mockup's "Edit Profile" button implies a distinct edit mode, but the avatar tap-to-change-photo feature must stay visible outside that mode (an existing, already-shipped, already-tested capability — hiding it would be a real regression).

- [ ] **Step 1: Read the current `ProfileScreen.build()` and `_EditForm`/`_EditFormState` in full**

Confirm current structure exactly matches what's described in this task (it may have shifted slightly from Tasks 2-3's own edits — re-read after those tasks, not from memory).

- [ ] **Step 2: Move the avatar block out of `_EditForm` into `ProfileScreen.build()`**

In `ProfileScreen.build()`, replace the line `_EditForm(profile: profile),` with:

```dart
                  Center(
                    child: GestureDetector(
                      onTap: _uploadingAvatar ? null : () => _uploadAvatar(ref, profile),
                      child: Column(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              NegotiatorAvatar(fullName: profile.fullName, avatarUrl: profile.avatarUrl, size: 72),
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
                  _EditForm(profile: profile),
```

Since `ProfileScreen` is a `ConsumerWidget` (not stateful), and the avatar upload needs an `_uploadingAvatar` loading flag plus the actual upload logic (currently inside `_EditFormState`), the CLEANEST way to keep this avatar section always-visible while still tracking its own loading state is to extract it into its OWN small `ConsumerStatefulWidget`, rather than trying to hoist mutable state into the stateless `ProfileScreen`. Do this instead of the inline block above:

Replace the line `_EditForm(profile: profile),` in `ProfileScreen.build()` with:

```dart
                  _ProfileAvatar(profile: profile),
                  const SizedBox(height: 20),
                  _EditForm(profile: profile),
```

Add this new widget class after `_TrustScoreCard` (before `_EditForm`):

```dart
class _ProfileAvatar extends ConsumerStatefulWidget {
  const _ProfileAvatar({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<_ProfileAvatar> {
  bool _uploading = false;
  String? _error;

  Future<void> _upload() async {
    final negotiatorId = ref.read(currentNegotiatorIdProvider);
    if (negotiatorId == null) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    if (mounted) setState(() => _error = null);
    try {
      if (mounted) setState(() => _uploading = true);
      final Uint8List bytes = await picked.readAsBytes();
      final repository = ref.read(profileRepositoryProvider);
      final avatarUrl = await repository.uploadAvatar(negotiatorId: negotiatorId, bytes: bytes);
      await repository.updateAvatarUrl(negotiatorId: negotiatorId, avatarUrl: avatarUrl);
      ref.invalidate(myProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('profile_save_success'.tr())),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'listing_error_generic'.tr());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: _uploading ? null : _upload,
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                NegotiatorAvatar(fullName: widget.profile.fullName, avatarUrl: widget.profile.avatarUrl, size: 72),
                if (_uploading) const CircularProgressIndicator(),
              ],
            ),
            const SizedBox(height: 6),
            Text('profile_avatar_upload_hint'.tr(), style: Theme.of(context).textTheme.labelSmall),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
```

This is a straight lift of `_EditFormState._uploadAvatar()`'s exact existing logic into its own small widget's own `_upload()` method -- same repository calls, same error handling, same snackbar. `ProfileRepository`/`ImagePicker`/`Uint8List` imports are already present in this file from the prior avatar-upload milestone.

- [ ] **Step 3: Remove the avatar block and its supporting fields from `_EditForm`/`_EditFormState`**

In `_EditFormState`, remove the `_uploadingAvatar` field and the entire `_uploadAvatar()` method (now duplicated into `_ProfileAvatarState._upload()` above — `_EditForm` no longer needs it). In `_EditFormState.build()`, remove the `Center(child: GestureDetector(...))` avatar block and the `const SizedBox(height: 20)` immediately after it (the avatar now lives in `_ProfileAvatar`, rendered by `ProfileScreen` before `_EditForm`, not inside `_EditForm` itself).

- [ ] **Step 4: Add the Edit Profile toggle**

`_EditFormState` gains a new field `bool _editing = false;`. Wrap `_EditFormState.build()`'s remaining content (the 2 `TextField`s, error text, Save button) in a conditional, and add an "Edit Profile" toggle button before it:

```dart
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BrutalistButton(
          label: 'profile_edit_button'.tr(),
          icon: PhosphorIcons.pencilSimple(PhosphorIconsStyle.bold),
          variant: BrutalistButtonVariant.secondary,
          onPressed: () => setState(() => _editing = !_editing),
        ),
        if (_editing) ...[
          const SizedBox(height: 12),
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
            onPressed: _submitting ? null : _saveAndClose,
          ),
        ],
      ],
    );
  }
```

Add a new `_saveAndClose()` method (`_save()` already exists — this wraps it so a successful save also collapses the form back, per the design doc's "hidden again ... on a successful save"):

```dart
  Future<void> _saveAndClose() async {
    await _save();
    if (mounted && _submitError == null) setState(() => _editing = false);
  }
```

Add the new l10n key `profile_edit_button` to both `en.json` ("Edit Profile") and `ms.json` ("Sunting Profil"), near `profile_save`.

- [ ] **Step 5: Add regression tests**

In `app/test/features/profile/profile_screen_test.dart`, add:

```dart
  testWidgets('territory field is hidden until Edit Profile is tapped', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Territory'), findsNothing);

    await tester.ensureVisible(find.text('Edit Profile'));
    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Territory'), findsOneWidget);
  });
```

Adjust `'Territory'`/`'Edit Profile'` to whatever the real English l10n strings for `profile_territory_label`/`profile_edit_button` actually render as (check `en.json` for `profile_territory_label`'s exact existing value before writing this assertion — do not guess).

Confirm the existing `'shows a tappable avatar with the upload hint'` test (already in this file) still passes UNCHANGED -- it should, since `_ProfileAvatar` renders the identical `NegotiatorAvatar` + hint text `ProfileScreen.build()` always shows, outside `_editing`.

- [ ] **Step 6: Run the test file**

Run: `cd app && flutter test test/features/profile/profile_screen_test.dart`
Expected: all tests pass, including the unchanged avatar test and the new toggle test.

- [ ] **Step 7: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Run l10n parity check** (same command as Task 3 Step 8)

- [ ] **Step 9: Commit**

```bash
git add app/lib/features/profile/profile_screen.dart app/test/features/profile/profile_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: keep avatar always-visible, gate profile-field editing behind a toggle"
```

---

### Task 5: Auto-Match Radar shortcut toggle + Designated Areas display

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart`
- Test: `app/test/features/profile/profile_screen_test.dart`

**Interfaces:**
- Consumes: `notificationPreferencesProvider`, `settingsRepositoryProvider` (both from `app/lib/features/settings/settings_providers.dart`), `profile.territory` (real, existing).

- [ ] **Step 1: Read `app/lib/features/settings/notification_settings_screen.dart` fresh**

Confirm its exact current optimistic-override + await-refetch pattern (shown in this plan's own research, but re-read the live file since it may have shifted) to mirror faithfully.

- [ ] **Step 2: Add a "Co-Broking Preferences" card**

Add `import '../settings/settings_providers.dart';` and `import '../settings/models/notification_preferences.dart';` to `profile_screen.dart`. Insert a new card after the settings-navigation `BrutalistCard` (or wherever fits best structurally after reading the current file — insert it as a new top-level section, do not nest inside the existing settings card):

```dart
                  const SizedBox(height: 20),
                  _CoBrokingPreferencesCard(negotiatorId: profile.negotiatorId, territory: profile.territory),
```

Add this new widget class near the bottom of the file (after `_TrustScoreCard`, before `_ProfileAvatar`):

```dart
class _CoBrokingPreferencesCard extends ConsumerStatefulWidget {
  const _CoBrokingPreferencesCard({required this.negotiatorId, required this.territory});

  final String negotiatorId;
  final String? territory;

  @override
  ConsumerState<_CoBrokingPreferencesCard> createState() => _CoBrokingPreferencesCardState();
}

class _CoBrokingPreferencesCardState extends ConsumerState<_CoBrokingPreferencesCard> {
  // Same optimistic-override pattern as NotificationSettingsScreen._toggle
  // -- the switch's thumb moves the instant it's tapped, cleared once the
  // write+refetch settles (success or failure).
  bool? _matchOverride;

  Future<void> _toggleMatch(bool value) async {
    setState(() => _matchOverride = value);
    try {
      await ref.read(settingsRepositoryProvider).updateNotificationPreferences(
            negotiatorId: widget.negotiatorId,
            notifyMatch: value,
          );
      ref.invalidate(notificationPreferencesProvider);
      try {
        await ref.read(notificationPreferencesProvider.future);
      } catch (_) {
        // A refetch failure after a successful write shouldn't surface as
        // a write error -- the write already succeeded.
      }
      if (mounted) setState(() => _matchOverride = null);
    } catch (_) {
      if (mounted) {
        setState(() => _matchOverride = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('listing_error_generic'.tr())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    return BrutalistCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('profile_cobroking_preferences_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            const Divider(height: 1),
            prefsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (error, stack) => const SizedBox.shrink(),
              data: (prefs) => SwitchListTile(
                title: Text('profile_auto_match_radar_label'.tr()),
                subtitle: Text('profile_auto_match_radar_subtitle'.tr()),
                value: _matchOverride ?? prefs.notifyMatch,
                onChanged: _toggleMatch,
              ),
            ),
            if (widget.territory != null) ...[
              const Divider(height: 1),
              ListTile(
                title: Text('profile_designated_area_label'.tr()),
                subtitle: Text(widget.territory!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Add the 3 new l10n keys**

`en.json`: `"profile_cobroking_preferences_title": "Co-Broking Preferences"`, `"profile_auto_match_radar_label": "Auto-Match Radar"`, `"profile_auto_match_radar_subtitle": "Instant alerts for matching buyers"`, `"profile_designated_area_label": "Designated Area"`.

`ms.json`: `"profile_cobroking_preferences_title": "Keutamaan Co-Broking"`, `"profile_auto_match_radar_label": "Radar Auto-Padan"`, `"profile_auto_match_radar_subtitle": "Amaran segera untuk pembeli yang sepadan"`, `"profile_designated_area_label": "Kawasan Ditetapkan"`.

- [ ] **Step 4: Add regression tests**

In `_wrap`, add an optional `NotificationPreferences? notificationPreferences` param defaulting to `const NotificationPreferences(notifyMatch: true, notifyMessage: true, notifyCobrokeRequest: true)`, and an override `notificationPreferencesProvider.overrideWith((ref) async => notificationPreferences ?? const NotificationPreferences(notifyMatch: true, notifyMessage: true, notifyCobrokeRequest: true))`. Then add:

```dart
  testWidgets('Auto-Match Radar reflects and updates the real notifyMatch preference', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      notificationPreferences: const NotificationPreferences(notifyMatch: false, notifyMessage: true, notifyCobrokeRequest: true),
    ));
    await tester.pumpAndSettle();

    final switchFinder = find.byType(SwitchListTile).first;
    final switchWidget = tester.widget<SwitchListTile>(switchFinder);
    expect(switchWidget.value, isFalse);
  });

  testWidgets('shows the real Designated Area when territory is set', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();

    expect(find.text('Petaling Jaya'), findsOneWidget);
  });
```

The second test relies on `_fixtureProfile`'s existing `territory: 'Petaling Jaya'` value (already in the file's fixture, confirmed via this session's own read of the file).

- [ ] **Step 5: Run the test file**

Run: `cd app && flutter test test/features/profile/profile_screen_test.dart`
Expected: all tests pass.

- [ ] **Step 6: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Run l10n parity check** (same command as Task 3 Step 8)

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/profile/profile_screen.dart app/test/features/profile/profile_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add real Auto-Match Radar shortcut and Designated Area to Profile"
```

---

### Task 6: Security & Biometrics shortcut + Agent Support relabel

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart`
- Test: `app/test/features/profile/profile_screen_test.dart`

**Interfaces:**
- Consumes: `biometricAvailableProvider`, `biometricLoginEnabledProvider` (both from `app/lib/features/auth/auth_providers.dart`).

- [ ] **Step 1: Add the Security & Biometrics shortcut row**

Add `import '../auth/auth_providers.dart';` to `profile_screen.dart` if not already present (it may already be imported for `authRepositoryProvider`'s Sign Out call — check first, do not add a duplicate import). Add a new small widget after `_CoBrokingPreferencesCard`:

```dart
class _BiometricStatusRow extends ConsumerWidget {
  const _BiometricStatusRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availableAsync = ref.watch(biometricAvailableProvider);
    final enabledAsync = ref.watch(biometricLoginEnabledProvider);

    return availableAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (available) {
        if (!available) return const SizedBox.shrink();
        return enabledAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (error, stack) => const SizedBox.shrink(),
          data: (enabled) => BrutalistCard(
            padding: EdgeInsets.zero,
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                leading: const Icon(Icons.fingerprint),
                title: Text('profile_biometric_label'.tr()),
                subtitle: Text(enabled ? 'account_settings_biometric_enabled'.tr() : 'account_settings_biometric_disabled'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/account'),
              ),
            ),
          ),
        );
      },
    );
  }
}
```

Insert it into `ProfileScreen.build()` right after `_CoBrokingPreferencesCard`:

```dart
                  const SizedBox(height: 12),
                  const _BiometricStatusRow(),
```

- [ ] **Step 2: Check whether `account_settings_biometric_enabled`/`account_settings_biometric_disabled` l10n keys already exist**

Run: `grep -n "account_settings_biometric_enabled\|account_settings_biometric_disabled" app/assets/translations/en.json`

If they already exist (likely, since `account_settings_screen.dart`'s own `_BiometricToggle` probably needs enabled/disabled subtitle copy too — verify by reading that file's own l10n key usage fresh), reuse them verbatim, no new keys needed for those two. If they do NOT exist, add them: `en.json` — `"account_settings_biometric_enabled": "Enabled"`, `"account_settings_biometric_disabled": "Disabled"`; `ms.json` — `"account_settings_biometric_enabled": "Diaktifkan"`, `"account_settings_biometric_disabled": "Dinyahaktifkan"`.

Add the new `profile_biometric_label` key regardless: `en.json` — `"profile_biometric_label": "Security & Biometrics"`; `ms.json` — `"profile_biometric_label": "Keselamatan & Biometrik"`.

- [ ] **Step 3: Relabel the existing Help settings row**

Read the current `ListTile` for `settings_help_row_title'.tr()`/`settings_help_row_subtitle'.tr()` fresh. Per the design doc, the mockup's fabricated "Renly Agent Support: Dedicated 24/7 VIP Concierge" framing should NOT introduce a new row -- it should relabel this EXISTING row's copy honestly. Check the current value of `settings_help_row_subtitle` in `en.json`; if it already says something honest (e.g. "Get help" or similar), leave it unchanged (no fabricated claim exists to remove, nothing to fix). If it currently says something that echoes the fabricated framing, change it to an honest subtitle (e.g. `"settings_help_row_subtitle": "Get help with your account"`) in both `en.json` and `ms.json`, keeping the existing key name (no new key). Do not add "24/7" or "VIP Concierge" anywhere.

- [ ] **Step 4: Add a regression test**

```dart
  testWidgets('shows the real Security & Biometrics status when biometric login is available', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/settings/account', builder: (context, state) => const Text('account screen')),
    ]);

    await tester.pumpWidget(_wrap(router, biometricAvailable: true, biometricEnabled: true));
    await tester.pumpAndSettle();

    expect(find.text('Security & Biometrics'), findsOneWidget);

    await tester.ensureVisible(find.text('Security & Biometrics'));
    await tester.tap(find.text('Security & Biometrics'));
    await tester.pumpAndSettle();
    expect(find.text('account screen'), findsOneWidget);
  });

  testWidgets('hides Security & Biometrics when biometric login is unavailable', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const ProfileScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, biometricAvailable: false));
    await tester.pumpAndSettle();

    expect(find.text('Security & Biometrics'), findsNothing);
  });
```

Add `bool biometricAvailable = false, bool biometricEnabled = false` optional params to `_wrap`, with overrides `biometricAvailableProvider.overrideWith((ref) async => biometricAvailable)` and `biometricLoginEnabledProvider.overrideWith((ref) async => biometricEnabled)` — defaulting to `false`/`false` so every EXISTING test (which doesn't pass these params) renders the row hidden, matching today's real absence of biometric setup in a fresh test environment.

- [ ] **Step 5: Run the test file**

Run: `cd app && flutter test test/features/profile/profile_screen_test.dart`
Expected: all tests pass.

- [ ] **Step 6: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Run l10n parity check** (same command as Task 3 Step 8)

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/profile/profile_screen.dart app/test/features/profile/profile_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add real Security & Biometrics shortcut, relabel Help row honestly"
```

---

### Task 7: Full-suite verification

**Files:** none (verification-only task).

- [ ] **Step 1: Run the full test suite**

Run: `cd app && flutter test`
Expected: every test passes, count higher than the pre-plan baseline by the number of new tests across Tasks 2-6 (2 + 1 + 1 + 2 + 2 = 8 new tests expected).

- [ ] **Step 2: Run `flutter analyze`**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Run l10n parity check** (same command as Task 3 Step 8)

- [ ] **Step 4: Manually verify against a real logged-in account** (documented here, not automated)

1. Co-Broke Volume shows `RM 0` for an account with no accepted agreements, and the real sum once at least one exists.
2. Tapping the avatar still opens the photo picker and uploads correctly (unchanged from the prior milestone).
3. Tapping "Edit Profile" reveals the territory/specialisation fields; saving successfully collapses the form again.
4. Toggling Auto-Match Radar on Profile updates the SAME real value seen on `/settings/notification` (and vice versa).
5. Security & Biometrics row is absent on a device/emulator with no biometric hardware enrolled, present with the real enabled/disabled label otherwise.

No commit for this task — it is a verification checkpoint, not a code change.
