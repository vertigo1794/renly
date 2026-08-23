# Tier-Gating Enforcement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce the Free-tier cap (max 3 active listings, max 3 active requirements, independently) now that `subscription_tier` is live via Subscription Core.

**Architecture:** A Postgres trigger on each of `listing`/`requirement`, firing only on transitions INTO the active state (new post or reactivation), rejecting a free-tier negotiator's 4th active row — the actual, unbypassable enforcement. Client-side: a plain count read per table, combined with the already-live `subscriptionStatusProvider` from Subscription Core, drives a live "X/3 active" indicator and a disabled submit/reactivate button with an upsell message on both the two Post screens and the two Detail screens' reactivate buttons — pure UX, never a substitute for the trigger.

**Tech Stack:** Flutter, Riverpod, supabase_flutter, easy_localization (EN/MS), Postgres `plpgsql` triggers. No new dependencies, no new tech.

## Global Constraints

- The trigger on each table fires on `before insert or update`, but only takes effect when `new.status = 'active'`/`'open'` AND (it's an INSERT, or `old.status` was NOT already active/open) — this is what correctly gates BOTH a brand-new post AND a reactivation via the existing "Mark Active"/"Mark Open" button, without firing on unrelated updates or a listing/requirement that's already active staying active.
- Professional tier is NEVER blocked by either trigger — the cap check only applies when `subscription_tier = 'free'`.
- The trigger's own `raise exception` message must NEVER be shown directly to the user (this project has an established, previously-fixed rule that raw exception text is never surfaced client-side — see Listing/Ratings' error-leak fixes). The client-side pre-check (disabled button + visible upsell message) is the primary UX; if the trigger still fires despite the pre-check passing (a rare race), the existing generic `listing_error_generic'.tr()` catch-all handles it — no new message-parsing logic that would risk leaking the raw DB string.
- Client-side count providers follow this codebase's existing local convention in `listing_providers.dart`/`requirement_providers.dart`: plain `FutureProvider` (NOT `.autoDispose`) — every existing provider in both files already omits it, and this is a one-shot count read, not a Realtime subscription (the leak risk `.autoDispose` guards against in this project's history is specifically about Stream/Realtime channels, not plain one-shot fetches).
- `subscriptionStatusProvider` is imported directly from `../subscription/subscription_providers.dart` into the listing/requirement screens — this project has an established precedent for a screen in one feature watching a live provider from a different feature directly (`ProfileScreen` already imports `ratings/rating_providers.dart` this way, with a `hide currentNegotiatorIdProvider` clause to avoid the per-feature-copy naming collision). Use the same `hide currentNegotiatorIdProvider` clause on this import.
- l10n: every new user-facing string needs both an `en.json` and `ms.json` entry.

---

### Task 1: Supabase Migration SQL (0014_tier_gating.sql)

**Files:**
- Create: `supabase/migrations/0014_tier_gating.sql`
- Modify: `app/README.md` (append a "Milestone 13 setup (tier gating)" section after the Milestone 12 section)

**Interfaces:**
- Consumes: `listing`/`requirement` tables, `negotiator.subscription_tier` (already exists, from `0001_auth_verification.sql`).
- Produces: `listing_active_cap_trigger`/`requirement_active_cap_trigger`, enforced server-side, consumed implicitly by every INSERT/UPDATE on either table from this point on.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0014_tier_gating.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0013.
--
-- Written to be re-runnable from the start, same pattern as every prior
-- migration.

-- Only gates transitions INTO 'active' -- a brand new listing, or
-- reactivation of a withdrawn one via PropertyDetailScreen's "Mark
-- Active" button (which calls the same updateListingStatus path as
-- PostListingScreen's initial create). Does nothing when status stays
-- active, moves OUT of active (sold/withdrawn), or an unrelated field
-- (price, description, photos) is edited on an already-active row.
--
-- No SECURITY DEFINER needed -- this only ever reads
-- negotiator.subscription_tier for the SAME negotiator who owns the row
-- being inserted/updated (their own row, already visible to them under
-- negotiator_select_own), unlike the cross-user cases elsewhere in this
-- project (get_listing_owner_info, is_agreement_party) that needed it.
create or replace function check_listing_active_cap() returns trigger as $$
declare
  tier text;
  active_count int;
begin
  if new.status != 'active' or (TG_OP = 'UPDATE' and old.status = 'active') then
    return new;
  end if;

  select subscription_tier into tier from negotiator where negotiator_id = new.negotiator_id;
  if tier = 'professional' then
    return new;
  end if;

  select count(*) into active_count from listing where negotiator_id = new.negotiator_id and status = 'active';
  if active_count >= 3 then
    raise exception 'Free tier is limited to 3 active listings. Upgrade to Professional for unlimited listings.';
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists listing_active_cap_trigger on listing;
create trigger listing_active_cap_trigger
  before insert or update on listing for each row
  execute function check_listing_active_cap();

-- Structural mirror of the listing trigger above -- same reasoning, same
-- shape, 'requirement'/'open' instead of 'listing'/'active'.
create or replace function check_requirement_active_cap() returns trigger as $$
declare
  tier text;
  active_count int;
begin
  if new.status != 'open' or (TG_OP = 'UPDATE' and old.status = 'open') then
    return new;
  end if;

  select subscription_tier into tier from negotiator where negotiator_id = new.negotiator_id;
  if tier = 'professional' then
    return new;
  end if;

  select count(*) into active_count from requirement where negotiator_id = new.negotiator_id and status = 'open';
  if active_count >= 3 then
    raise exception 'Free tier is limited to 3 active requirements. Upgrade to Professional for unlimited requirements.';
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists requirement_active_cap_trigger on requirement;
create trigger requirement_active_cap_trigger
  before insert or update on requirement for each row
  execute function check_requirement_active_cap();
```

- [ ] **Step 2: Append README setup section**

Read `app/README.md`, find the "Milestone 12 setup (subscription)" section, and append immediately after it:

```markdown
## Milestone 13 setup (tier gating)

Run `supabase/migrations/0014_tier_gating.sql` in the Supabase SQL Editor after 0001-0013. This adds two `before insert or update` triggers (`listing_active_cap_trigger`, `requirement_active_cap_trigger`) enforcing the Free-tier cap of 3 active listings and 3 active requirements (independently) -- the actual, server-side enforcement, not just a client-side UI convenience. No RLS/grant changes -- these are plain triggers, transparent to the existing insert/update policies. No manual dashboard step beyond running the SQL.

**Manual verification:** as a free-tier negotiator, create 3 active listings, then attempt a 4th -- confirm it's rejected (both via the app's own disabled-button UX, and by attempting the same insert directly in the SQL Editor to confirm the trigger itself, not just the client check, is what's blocking it). Confirm withdrawing one of the 3 then posting a new one succeeds. Confirm reactivating a withdrawn listing while already at 3 active ones is also rejected (this is the reactivation path via PropertyDetailScreen's "Mark Active" button, not just PostListingScreen). Repeat for requirements. Confirm a Professional-tier negotiator is never blocked by any of the above.
```

- [ ] **Step 3: Verify with grep**

Run:
```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
grep -c "^create or replace function" supabase/migrations/0014_tier_gating.sql
grep -c "^create trigger" supabase/migrations/0014_tier_gating.sql
```
Expected: `2`, `2`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0014_tier_gating.sql app/README.md
git commit -m "feat: add tier-gating triggers for listing/requirement active caps"
```

---

### Task 2: Active-count repository methods + providers

**Files:**
- Modify: `app/lib/features/listing/listing_repository.dart`
- Modify: `app/lib/features/listing/listing_providers.dart`
- Modify: `app/lib/features/requirement/requirement_repository.dart`
- Modify: `app/lib/features/requirement/requirement_providers.dart`

**Interfaces:**
- Consumes: `listing`/`requirement` tables.
- Produces: `ListingRepository.countActiveListings(String negotiatorId) -> Future<int>`, `RequirementRepository.countActiveRequirements(String negotiatorId) -> Future<int>`, `activeListingCountProvider = FutureProvider.family<int, String>`, `activeRequirementCountProvider = FutureProvider.family<int, String>` — used by Tasks 3-6's screens.

- [ ] **Step 1: Add the repository method to ListingRepository**

In `app/lib/features/listing/listing_repository.dart`, add this method (same `.count(CountOption.exact)` pattern already established in `ProfileRepository.countActiveListings` — verified directly against that file's existing code, not reinvented):

```dart
  Future<int> countActiveListings(String negotiatorId) async {
    final response = await _client
        .from('listing')
        .select('listing_id')
        .eq('negotiator_id', negotiatorId)
        .eq('status', 'active')
        .count(CountOption.exact);
    return response.count;
  }
```

- [ ] **Step 2: Add the provider to listing_providers.dart**

In `app/lib/features/listing/listing_providers.dart`, add after `listingOwnerProvider`:

```dart
final activeListingCountProvider = FutureProvider.family<int, String>((ref, negotiatorId) {
  return ref.watch(listingRepositoryProvider).countActiveListings(negotiatorId);
});
```

- [ ] **Step 3: Add the repository method to RequirementRepository**

In `app/lib/features/requirement/requirement_repository.dart`, add the structural mirror:

```dart
  Future<int> countActiveRequirements(String negotiatorId) async {
    final response = await _client
        .from('requirement')
        .select('requirement_id')
        .eq('negotiator_id', negotiatorId)
        .eq('status', 'open')
        .count(CountOption.exact);
    return response.count;
  }
```

- [ ] **Step 4: Add the provider to requirement_providers.dart**

In `app/lib/features/requirement/requirement_providers.dart`, add after `requirementOwnerProvider`:

```dart
final activeRequirementCountProvider = FutureProvider.family<int, String>((ref, negotiatorId) {
  return ref.watch(requirementRepositoryProvider).countActiveRequirements(negotiatorId);
});
```

- [ ] **Step 5: Verify it compiles**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter analyze lib/features/listing/ lib/features/requirement/`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/listing/listing_repository.dart app/lib/features/listing/listing_providers.dart app/lib/features/requirement/requirement_repository.dart app/lib/features/requirement/requirement_providers.dart
git commit -m "feat: add active-listing/requirement count repository methods and providers"
```

---

### Task 3: PostListingScreen cap indicator + block

**Files:**
- Modify: `app/lib/features/listing/post_listing_screen.dart`
- Modify: `app/test/features/listing/post_listing_screen_test.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `activeListingCountProvider` (Task 2), `subscriptionStatusProvider`/`SubscriptionStatus` (Subscription Core, already merged, `app/lib/features/subscription/subscription_providers.dart`), `currentNegotiatorIdProvider` (this file's existing own copy).
- Produces: no new public interface — this task only changes `PostListingScreen`'s rendered UI and submit-gating behavior.

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`, find the line `"settings_subscription_row_subtitle": "Manage your plan and billing"` (currently the last key before the closing `}`) and change it to add a trailing comma, then insert these keys after it, before the closing `}`:

```json
  "settings_subscription_row_subtitle": "Manage your plan and billing",
  "listing_active_count_label": "active listings",
  "listing_cap_reached_message": "You've reached the Free plan's limit of 3 active listings. Upgrade to Professional for unlimited listings."
```

In `app/assets/translations/ms.json`, find the line `"settings_subscription_row_subtitle": "Urus pelan dan bil anda"` (currently the last key before the closing `}`) and change it to add a trailing comma, then insert these keys after it, before the closing `}`:

```json
  "settings_subscription_row_subtitle": "Urus pelan dan bil anda",
  "listing_active_count_label": "penyenaraian aktif",
  "listing_cap_reached_message": "Anda telah mencapai had 3 penyenaraian aktif pelan Percuma. Naik taraf ke Profesional utk penyenaraian tanpa had."
```

- [ ] **Step 2: Write the failing test**

`app/test/features/listing/post_listing_screen_test.dart`'s existing `_wrap(GoRouter router)` helper has NO provider overrides at all (confirmed by reading the file directly). Change its signature to accept an optional `overrides` list, defaulting to empty, so existing tests keep working unchanged:

```dart
Widget _wrap(GoRouter router, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: EasyLocalization(
```

(Only the `ProviderScope(` line changes — from `ProviderScope(` with no arguments to `ProviderScope(overrides: overrides,` — everything else in the helper stays exactly as it is.)

Add these imports to the top of the test file:
```dart
import 'package:renly/features/listing/listing_providers.dart';
import 'package:renly/features/subscription/models/subscription_status.dart' as subscription;
import 'package:renly/features/subscription/subscription_providers.dart' as subscription_providers;
```

Add this test inside the existing `main()` block, after the last existing `testWidgets`, before the closing `}` of `main()`:

```dart
  testWidgets('shows active count and disables submit at the free-tier cap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PostListingScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      activeListingCountProvider('n-1').overrideWith((ref) async => 3),
      subscription_providers.subscriptionStatusProvider.overrideWith(
        (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'free')),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text("You've reached the Free plan's limit of 3 active listings. Upgrade to Professional for unlimited listings."), findsOneWidget);

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('does not block submit for a professional-tier negotiator even at 3 active listings', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PostListingScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      activeListingCountProvider('n-1').overrideWith((ref) async => 3),
      subscription_providers.subscriptionStatusProvider.overrideWith(
        (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'professional')),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text("You've reached the Free plan's limit of 3 active listings. Upgrade to Professional for unlimited listings."), findsNothing);

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/listing/post_listing_screen_test.dart -v`
Expected: FAIL — `activeListingCountProvider` not found / the cap message never renders.

- [ ] **Step 4: Wire the cap check into PostListingScreen**

In `app/lib/features/listing/post_listing_screen.dart`, add these imports after the existing `import 'listing_providers.dart';` line:

```dart
import '../subscription/subscription_providers.dart' hide currentNegotiatorIdProvider;
```

In `_PostListingScreenState`'s `build` method, find this exact existing block (currently lines 164-166):

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
```

Replace it with:

```dart
  @override
  Widget build(BuildContext context) {
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);
    final tierAsync = ref.watch(subscriptionStatusProvider);
    final countAsync = negotiatorId == null
        ? const AsyncValue<int>.data(0)
        : ref.watch(activeListingCountProvider(negotiatorId));
    final activeCount = countAsync.valueOrNull ?? 0;
    final atCap = tierAsync.valueOrNull?.tier == 'free' && activeCount >= 3;

    return Scaffold(
```

Find this exact existing block (the photo-count-then-error block, currently around lines 264-333, specifically the part right before the submit button):

```dart
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text('listing_post_now'.tr()),
                ),
```

Replace it with:

```dart
                if (tierAsync.valueOrNull?.tier == 'free') ...[
                  const SizedBox(height: 12),
                  Text('$activeCount/3 ${'listing_active_count_label'.tr()}'),
                ],
                if (atCap) ...[
                  const SizedBox(height: 8),
                  Text(
                    'listing_cap_reached_message'.tr(),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: (_submitting || atCap) ? null : _submit,
                  child: Text('listing_post_now'.tr()),
                ),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/listing/post_listing_screen_test.dart -v`
Expected: PASS (all existing tests plus the 2 new ones).

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/listing/post_listing_screen.dart app/test/features/listing/post_listing_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: block PostListingScreen submit at the free-tier active-listing cap"
```

---

### Task 4: PostRequirementScreen cap indicator + block

**Files:**
- Modify: `app/lib/features/requirement/post_requirement_screen.dart`
- Modify: `app/test/features/requirement/post_requirement_screen_test.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json`

**Interfaces:**
- Consumes: `activeRequirementCountProvider` (Task 2), `subscriptionStatusProvider`/`SubscriptionStatus` (Subscription Core), `currentNegotiatorIdProvider` (this file's existing own copy).
- Produces: no new public interface — this task only changes `PostRequirementScreen`'s rendered UI and submit-gating behavior.

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`, find the line `"listing_cap_reached_message": "You've reached the Free plan's limit of 3 active listings. Upgrade to Professional for unlimited listings."` (now the last key before the closing `}`) and change it to add a trailing comma, then insert these keys after it, before the closing `}`:

```json
  "listing_cap_reached_message": "You've reached the Free plan's limit of 3 active listings. Upgrade to Professional for unlimited listings.",
  "requirement_active_count_label": "active requirements",
  "requirement_cap_reached_message": "You've reached the Free plan's limit of 3 active requirements. Upgrade to Professional for unlimited requirements."
```

In `app/assets/translations/ms.json`, find the line `"listing_cap_reached_message": "Anda telah mencapai had 3 penyenaraian aktif pelan Percuma. Naik taraf ke Profesional utk penyenaraian tanpa had."` (now the last key before the closing `}`) and change it to add a trailing comma, then insert these keys after it, before the closing `}`:

```json
  "listing_cap_reached_message": "Anda telah mencapai had 3 penyenaraian aktif pelan Percuma. Naik taraf ke Profesional utk penyenaraian tanpa had.",
  "requirement_active_count_label": "keperluan aktif",
  "requirement_cap_reached_message": "Anda telah mencapai had 3 keperluan aktif pelan Percuma. Naik taraf ke Profesional utk keperluan tanpa had."
```

- [ ] **Step 2: Write the failing test**

Read `app/test/features/requirement/post_requirement_screen_test.dart` first to confirm its existing `_wrap` helper's exact current shape (it should be structurally identical to `post_listing_screen_test.dart`'s, confirm before editing). Apply the same `overrides` parameter change described in Task 3 Step 2.

Add these imports:
```dart
import 'package:renly/features/requirement/requirement_providers.dart';
import 'package:renly/features/subscription/models/subscription_status.dart' as subscription;
import 'package:renly/features/subscription/subscription_providers.dart' as subscription_providers;
```

Add these two tests (structural mirror of Task 3's, `Requirement`/`open`/3-active wording instead of `Listing`/`active`):

```dart
  testWidgets('shows active count and disables submit at the free-tier cap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PostRequirementScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      activeRequirementCountProvider('n-1').overrideWith((ref) async => 3),
      subscription_providers.subscriptionStatusProvider.overrideWith(
        (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'free')),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text("You've reached the Free plan's limit of 3 active requirements. Upgrade to Professional for unlimited requirements."), findsOneWidget);

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('does not block submit for a professional-tier negotiator even at 3 active requirements', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PostRequirementScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      activeRequirementCountProvider('n-1').overrideWith((ref) async => 3),
      subscription_providers.subscriptionStatusProvider.overrideWith(
        (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'professional')),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text("You've reached the Free plan's limit of 3 active requirements. Upgrade to Professional for unlimited requirements."), findsNothing);

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/requirement/post_requirement_screen_test.dart -v`
Expected: FAIL — `activeRequirementCountProvider` not found / the cap message never renders.

- [ ] **Step 4: Wire the cap check into PostRequirementScreen**

In `app/lib/features/requirement/post_requirement_screen.dart`, add this import after the existing `import 'requirement_providers.dart';` line:

```dart
import '../subscription/subscription_providers.dart' hide currentNegotiatorIdProvider;
```

Find this exact existing block (confirmed by reading the file directly, currently lines 147-149):

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
```

Replace it with:

```dart
  @override
  Widget build(BuildContext context) {
    final negotiatorId = ref.watch(currentNegotiatorIdProvider);
    final tierAsync = ref.watch(subscriptionStatusProvider);
    final countAsync = negotiatorId == null
        ? const AsyncValue<int>.data(0)
        : ref.watch(activeRequirementCountProvider(negotiatorId));
    final activeCount = countAsync.valueOrNull ?? 0;
    final atCap = tierAsync.valueOrNull?.tier == 'free' && activeCount >= 3;

    return Scaffold(
```

Find this exact existing block (confirmed by reading the file directly, currently the tail of the submit section):

```dart
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text('requirement_post_now'.tr()),
                ),
```

Replace it with:

```dart
                if (tierAsync.valueOrNull?.tier == 'free') ...[
                  const SizedBox(height: 12),
                  Text('$activeCount/3 ${'requirement_active_count_label'.tr()}'),
                ],
                if (atCap) ...[
                  const SizedBox(height: 8),
                  Text(
                    'requirement_cap_reached_message'.tr(),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: (_submitting || atCap) ? null : _submit,
                  child: Text('requirement_post_now'.tr()),
                ),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/requirement/post_requirement_screen_test.dart -v`
Expected: PASS (all existing tests plus the 2 new ones).

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/requirement/post_requirement_screen.dart app/test/features/requirement/post_requirement_screen_test.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: block PostRequirementScreen submit at the free-tier active-requirement cap"
```

---

### Task 5: PropertyDetailScreen reactivate-button cap gating

**Files:**
- Modify: `app/lib/features/listing/property_detail_screen.dart`
- Modify: `app/test/features/listing/property_detail_screen_test.dart`

**Interfaces:**
- Consumes: `activeListingCountProvider` (Task 2), `subscriptionStatusProvider` (Subscription Core), `currentNegotiatorIdProvider` (this file's existing own copy). Reuses the `listing_cap_reached_message` l10n key added in Task 3 — no new l10n keys in this task.

- [ ] **Step 1: Write the failing test**

`app/test/features/listing/property_detail_screen_test.dart`'s current exact content (confirmed by reading the file directly):

```dart
const _fixtureListing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'The Vertex Residency',
  description: 'A modern apartment with lots of light.',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  price: 1250000,
  bedrooms: 3,
  bathrooms: 2,
  photoUrls: [],
  status: 'active',
);

const _fixtureOwner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

Widget _wrap(GoRouter router, {String currentNegotiatorId = 'n-2'}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue(currentNegotiatorId),
      listingDetailProvider.overrideWith((ref, listingId) async => _fixtureListing),
      listingOwnerProvider.overrideWith((ref, negotiatorId) async => _fixtureOwner),
    ],
    child: EasyLocalization(
      ...
```

Change `_wrap` to accept an optional `listing` override and extra overrides, keeping every existing call site (which passes neither) working unchanged:

```dart
Widget _wrap(GoRouter router, {String currentNegotiatorId = 'n-2', Listing? listing, List<Override> extraOverrides = const []}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue(currentNegotiatorId),
      listingDetailProvider.overrideWith((ref, listingId) async => listing ?? _fixtureListing),
      listingOwnerProvider.overrideWith((ref, negotiatorId) async => _fixtureOwner),
      ...extraOverrides,
    ],
    child: EasyLocalization(
```

(Only the function signature's first line and the `overrides:` list's second entry + the added `...extraOverrides` spread change — the rest of `_wrap`'s body, everything from `child: EasyLocalization(` onward, stays exactly as it is.)

Add these imports:
```dart
import 'package:renly/features/subscription/models/subscription_status.dart' as subscription;
import 'package:renly/features/subscription/subscription_providers.dart' as subscription_providers;
```

Add a withdrawn-status fixture and a test asserting the "Mark Active" button (`property_reactivate` key) is disabled and shows the cap-reached message when the owner is free-tier and already at 3 active listings:

```dart
const _withdrawnListingOwnedByN1 = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'The Vertex Residency',
  description: 'A modern apartment with lots of light.',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  price: 1250000,
  bedrooms: 3,
  bathrooms: 2,
  photoUrls: [],
  status: 'withdrawn',
);

  testWidgets('disables the reactivate button at the free-tier active-listing cap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const PropertyDetailScreen(listingId: 'l-1')),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      currentNegotiatorId: 'n-1',
      listing: _withdrawnListingOwnedByN1,
      extraOverrides: [
        activeListingCountProvider('n-1').overrideWith((ref) async => 3),
        subscription_providers.subscriptionStatusProvider.overrideWith(
          (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'free')),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text("You've reached the Free plan's limit of 3 active listings. Upgrade to Professional for unlimited listings."), findsOneWidget);

    final reactivateButton = tester.widget<OutlinedButton>(
      find.ancestor(of: find.text('property_reactivate'.tr()), matching: find.byType(OutlinedButton)),
    );
    expect(reactivateButton.onPressed, isNull);
  });
```

`activeListingCountProvider` comes from `listing_providers.dart`, already imported by this file (line 11) — no new import needed for it, only the two `subscription` imports above.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/listing/property_detail_screen_test.dart -v`
Expected: FAIL — the cap message never renders / the button is enabled.

- [ ] **Step 3: Wire the cap check into PropertyDetailScreen**

In `app/lib/features/listing/property_detail_screen.dart`, add this import after the existing `listing_providers.dart` import:

```dart
import '../subscription/subscription_providers.dart' hide currentNegotiatorIdProvider;
```

Find this exact existing block (the `build` method's data callback, currently starting at line 55):

```dart
        data: (listing) {
          final isOwner = currentNegotiatorId != null && currentNegotiatorId == listing.negotiatorId;
```

Replace it with:

```dart
        data: (listing) {
          final isOwner = currentNegotiatorId != null && currentNegotiatorId == listing.negotiatorId;
          final tierAsync = ref.watch(subscriptionStatusProvider);
          final countAsync = currentNegotiatorId == null
              ? const AsyncValue<int>.data(0)
              : ref.watch(activeListingCountProvider(currentNegotiatorId));
          final atCap = tierAsync.valueOrNull?.tier == 'free' && (countAsync.valueOrNull ?? 0) >= 3;
```

Find this exact existing block (the reactivate button, currently the last item inside the `if (isOwner) ...` list):

```dart
                    if (listing.status != 'active')
                      OutlinedButton(
                        onPressed: () => _changeStatus(listing, 'active'),
                        child: Text('property_reactivate'.tr()),
                      ),
```

Replace it with:

```dart
                    if (listing.status != 'active') ...[
                      if (atCap) ...[
                        Text(
                          'listing_cap_reached_message'.tr(),
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                        const SizedBox(height: 8),
                      ],
                      OutlinedButton(
                        onPressed: atCap ? null : () => _changeStatus(listing, 'active'),
                        child: Text('property_reactivate'.tr()),
                      ),
                    ],
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/listing/property_detail_screen_test.dart -v`
Expected: PASS (all existing tests plus the new one).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/listing/property_detail_screen.dart app/test/features/listing/property_detail_screen_test.dart
git commit -m "feat: gate PropertyDetailScreen's reactivate button on the free-tier active-listing cap"
```

---

### Task 6: RequirementDetailScreen reactivate-button cap gating

**Files:**
- Modify: `app/lib/features/requirement/requirement_detail_screen.dart`
- Modify: `app/test/features/requirement/requirement_detail_screen_test.dart`

**Interfaces:**
- Consumes: `activeRequirementCountProvider` (Task 2), `subscriptionStatusProvider` (Subscription Core), `currentNegotiatorIdProvider` (this file's existing own copy). Reuses the `requirement_cap_reached_message` l10n key added in Task 4 — no new l10n keys in this task.

- [ ] **Step 1: Write the failing test**

`app/test/features/requirement/requirement_detail_screen_test.dart`'s current exact content (confirmed by reading the file directly) has the identical shape to Task 5's `property_detail_screen_test.dart`:

```dart
const _fixtureRequirement = Requirement(
  requirementId: 'r-1',
  negotiatorId: 'n-1',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  budgetMin: 300000,
  budgetMax: 500000,
  bedrooms: 3,
  photoUrls: [],
  status: 'open',
);

const _fixtureOwner = ListingOwner(fullName: 'Aiman Yusof', renNumber: '12345');

Widget _wrap(GoRouter router, {String currentNegotiatorId = 'n-2'}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue(currentNegotiatorId),
      requirementDetailProvider.overrideWith((ref, requirementId) async => _fixtureRequirement),
      requirementOwnerProvider.overrideWith((ref, negotiatorId) async => _fixtureOwner),
    ],
    child: EasyLocalization(
      ...
```

Apply the same `_wrap` extension as Task 5 Step 1 (add `Requirement? requirement` and `List<Override> extraOverrides = const []` params, `requirement ?? _fixtureRequirement` in the override, `...extraOverrides` spread):

```dart
Widget _wrap(GoRouter router, {String currentNegotiatorId = 'n-2', Requirement? requirement, List<Override> extraOverrides = const []}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue(currentNegotiatorId),
      requirementDetailProvider.overrideWith((ref, requirementId) async => requirement ?? _fixtureRequirement),
      requirementOwnerProvider.overrideWith((ref, negotiatorId) async => _fixtureOwner),
      ...extraOverrides,
    ],
    child: EasyLocalization(
```

Add these imports (`activeRequirementCountProvider` comes from `requirement_providers.dart`, already imported by this file — no new import needed for it):
```dart
import 'package:renly/features/subscription/models/subscription_status.dart' as subscription;
import 'package:renly/features/subscription/subscription_providers.dart' as subscription_providers;
```

Add a withdrawn-status fixture and the test:

```dart
const _withdrawnRequirementOwnedByN1 = Requirement(
  requirementId: 'r-1',
  negotiatorId: 'n-1',
  propertyType: 'apartment',
  transactionType: 'sale',
  state: 'Selangor',
  area: 'Petaling Jaya',
  budgetMin: 300000,
  budgetMax: 500000,
  bedrooms: 3,
  photoUrls: [],
  status: 'withdrawn',
);

  testWidgets('disables the reactivate button at the free-tier active-requirement cap', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const RequirementDetailScreen(requirementId: 'r-1')),
    ]);

    await tester.pumpWidget(_wrap(
      router,
      currentNegotiatorId: 'n-1',
      requirement: _withdrawnRequirementOwnedByN1,
      extraOverrides: [
        activeRequirementCountProvider('n-1').overrideWith((ref) async => 3),
        subscription_providers.subscriptionStatusProvider.overrideWith(
          (ref) => Stream.value(const subscription.SubscriptionStatus(tier: 'free')),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text("You've reached the Free plan's limit of 3 active requirements. Upgrade to Professional for unlimited requirements."), findsOneWidget);

    final reactivateButton = tester.widget<OutlinedButton>(
      find.ancestor(of: find.text('requirement_reactivate'.tr()), matching: find.byType(OutlinedButton)),
    );
    expect(reactivateButton.onPressed, isNull);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/requirement/requirement_detail_screen_test.dart -v`
Expected: FAIL.

- [ ] **Step 3: Wire the cap check into RequirementDetailScreen**

In `app/lib/features/requirement/requirement_detail_screen.dart`, add this import after the existing `requirement_providers.dart` import:

```dart
import '../subscription/subscription_providers.dart' hide currentNegotiatorIdProvider;
```

Find this exact existing block (confirmed by reading the file directly, currently lines 51-53):

```dart
        data: (requirement) {
          final isOwner = currentNegotiatorId != null && currentNegotiatorId == requirement.negotiatorId;
```

Replace it with:

```dart
        data: (requirement) {
          final isOwner = currentNegotiatorId != null && currentNegotiatorId == requirement.negotiatorId;
          final tierAsync = ref.watch(subscriptionStatusProvider);
          final countAsync = currentNegotiatorId == null
              ? const AsyncValue<int>.data(0)
              : ref.watch(activeRequirementCountProvider(currentNegotiatorId));
          final atCap = tierAsync.valueOrNull?.tier == 'free' && (countAsync.valueOrNull ?? 0) >= 3;
```

Find this exact existing block (confirmed by reading the file directly, the reactivate button):

```dart
                    if (requirement.status != 'open')
                      OutlinedButton(
                        onPressed: () => _changeStatus(requirement, 'open'),
                        child: Text('requirement_reactivate'.tr()),
                      ),
```

Replace it with:

```dart
                    if (requirement.status != 'open') ...[
                      if (atCap) ...[
                        Text(
                          'requirement_cap_reached_message'.tr(),
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                        const SizedBox(height: 8),
                      ],
                      OutlinedButton(
                        onPressed: atCap ? null : () => _changeStatus(requirement, 'open'),
                        child: Text('requirement_reactivate'.tr()),
                      ),
                    ],
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/requirement/requirement_detail_screen_test.dart -v`
Expected: PASS.

- [ ] **Step 5: Run full suite and analyze**

Run:
```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app"
flutter test
flutter analyze
```
Expected: all tests pass (real count — confirm from actual output, do not estimate), `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/requirement/requirement_detail_screen.dart app/test/features/requirement/requirement_detail_screen_test.dart
git commit -m "feat: gate RequirementDetailScreen's reactivate button on the free-tier active-requirement cap"
```

---

## Self-Review Notes

- **Spec coverage:** trigger enforcement on both tables including the reactivation path (Task 1), client-side count reads (Task 2), UX on both Post screens (Tasks 3-4) and both Detail screens' reactivate buttons (Tasks 5-6) — the design doc's every named surface is covered.
- **Placeholder scan:** no TBD/TODO; every task has complete, real code. Tasks 5-6 initially delegated their test-file edits to "read the file and follow its conventions" — caught during this self-review as under-specified, so both were rewritten with the actual current `_wrap`/fixture code (verified by reading `property_detail_screen_test.dart`/`requirement_detail_screen_test.dart` directly) and the exact, concrete replacement, the same rigor as every other task.
- **Type consistency:** `activeListingCountProvider`/`activeRequirementCountProvider` signatures (`FutureProvider.family<int, String>`) and the `tierAsync`/`countAsync`/`atCap` local-variable pattern are identical across Tasks 3, 4, 5, 6 — verified by re-reading each task's code side by side while writing this plan.
