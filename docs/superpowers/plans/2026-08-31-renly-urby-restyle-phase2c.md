# Urby Restyle Phase 2C (Profile/Settings/Subscription) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the 7 Profile/Settings/Subscription screens with the neo-brutalist design system (`BrutalistButton`, `BrutalistCard`, Phosphor Bold icons). Closes out the Urby Restyle initiative's planned screen coverage.

**Architecture:** 5 tasks, one per screen with real changes (`PrivacyScreen`/`HelpScreen` need none, confirmed by direct read). No shared-widget work — `BrutalistButton`'s API is already feature-complete since Phase 2B.

**Tech Stack:** Flutter, Riverpod, `phosphor_flutter` (existing dependency), no new packages.

## Global Constraints

- All icons use `PhosphorIcons.X(PhosphorIconsStyle.bold)` — never `Icons.*` Material icons.
- No functional/business-logic change to any of the 7 screens.
- No global theme file (`app_theme.dart`/`app_colors.dart`) touched.
- All 4 error-state Retry `TextButton`s (in `AccountSettingsScreen`, `NotificationSettingsScreen`, `SubscriptionScreen`) are out of scope — leave untouched.
- `flutter analyze` and the full `flutter test` suite must stay clean throughout every task.
- No golden-image tests.
- `assets/illustrations/` is already declared as a directory in `app/pubspec.yaml` — no pubspec change needed for the new `reviews_empty.png` slot.
- Confirmed this session: none of the 5 affected test files have `find.byType(Card/ElevatedButton/OutlinedButton)` matchers. `notification_settings_screen_test.dart` has 2 `find.byType(SwitchListTile)` matchers — these stay valid since `SwitchListTile` itself is not replaced, only wrapped in a new `BrutalistCard`.

---

### Task 1: Restyle `ProfileScreen`

**Files:**
- Modify: `app/lib/features/profile/profile_screen.dart`
- Test: `app/test/features/profile/profile_screen_test.dart` (confirmed this session: no `Card`/`ElevatedButton`/`OutlinedButton` type matcher — no test changes needed)

**Interfaces:**
- Consumes: `BrutalistButton`, `BrutalistButtonVariant`, `BrutalistCard` (all existing, unchanged since Phase 2B).

- [ ] **Step 1: Add imports**

In `app/lib/features/profile/profile_screen.dart`, add after the existing imports:

```dart
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';
import '../../core/widgets/brutalist_card.dart';
```

- [ ] **Step 2: Restyle the App Settings list card**

Replace:

```dart
                Card(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('settings_section_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
                        ),
                      ),
                      const Divider(height: 1),
```

with:

```dart
                BrutalistCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('settings_section_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
                        ),
                      ),
                      const Divider(height: 1),
```

(`BrutalistCard`'s default padding is `EdgeInsets.all(16)`, which would double-pad against this card's own internal `Padding` widgets on the title and each `ListTile` — pass `padding: EdgeInsets.zero` to let the inner widgets own their own spacing, matching how `Card`'s own zero-default padding behaved before.)

The closing `),` that closed the original `Card(` needs no change — `BrutalistCard` takes the same `child:` shape.

- [ ] **Step 3: Restyle `_StatCard`**

Replace:

```dart
class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label),
          ],
        ),
      ),
    );
  }
}
```

with:

```dart
class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return BrutalistCard(
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(label),
        ],
      ),
    );
  }
}
```

(`BrutalistCard`'s default `EdgeInsets.all(16)` padding replaces the removed manual `Padding` — no double-padding.)

- [ ] **Step 4: Restyle `_TrustScoreCard`**

Replace:

```dart
        return Card(
          child: InkWell(
            onTap: () => context.push('/reviews'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(display, style: Theme.of(context).textTheme.headlineSmall),
                  Text('profile_trust_score_label'.tr()),
```

with:

```dart
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push('/reviews'),
            child: BrutalistCard(
              child: Column(
                children: [
                  Text(display, style: Theme.of(context).textTheme.headlineSmall),
                  Text('profile_trust_score_label'.tr()),
```

The closing tags after this `Column`'s children stay structurally the same depth (`Card`→`InkWell`→`Padding`→`Column` becomes `Material`→`InkWell`→`BrutalistCard`→`Column`, still 4 levels) — no change needed to the closing braces below.

- [ ] **Step 5: Restyle the Sign Out button**

Replace:

```dart
                OutlinedButton(
                  onPressed: () async {
                    try {
                      await ref.read(authRepositoryProvider).signOut();
                    } catch (_) {
                      // Sign-out already clears the local session before any
                      // network call and swallows most HTTP errors -- a
                      // rethrow here would only be a transport failure after
                      // the local session is already gone, so the redirect
                      // to '/' still happens regardless. Swallow rather than
                      // show an error the user can't act on.
                    }
                  },
                  child: Text('profile_sign_out'.tr()),
                ),
```

with:

```dart
                BrutalistButton(
                  label: 'profile_sign_out'.tr(),
                  variant: BrutalistButtonVariant.secondary,
                  icon: PhosphorIcons.signOut(PhosphorIconsStyle.bold),
                  onPressed: () async {
                    try {
                      await ref.read(authRepositoryProvider).signOut();
                    } catch (_) {
                      // Sign-out already clears the local session before any
                      // network call and swallows most HTTP errors -- a
                      // rethrow here would only be a transport failure after
                      // the local session is already gone, so the redirect
                      // to '/' still happens regardless. Swallow rather than
                      // show an error the user can't act on.
                    }
                  },
                ),
```

- [ ] **Step 6: Restyle the Save button in `_EditForm`**

Replace:

```dart
        ElevatedButton(
          onPressed: _submitting ? null : _save,
          child: Text('profile_save'.tr()),
        ),
```

with:

```dart
        BrutalistButton(
          label: 'profile_save'.tr(),
          icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
          onPressed: _submitting ? null : _save,
        ),
```

- [ ] **Step 7: Run tests and analyze**

Run: `cd app && flutter test test/features/profile/profile_screen_test.dart && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/profile/profile_screen.dart
git commit -m "feat: restyle ProfileScreen with BrutalistCard and BrutalistButton"
```

---

### Task 2: Restyle `AccountSettingsScreen`

**Files:**
- Modify: `app/lib/features/settings/account_settings_screen.dart`
- Test: `app/test/features/settings/account_settings_screen_test.dart` (confirmed this session: no `ElevatedButton` type matcher — no test changes needed)

**Interfaces:**
- Consumes: `BrutalistButton` (existing, unchanged).

- [ ] **Step 1: Add imports**

In `app/lib/features/settings/account_settings_screen.dart`, add:

```dart
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';
```

- [ ] **Step 2: Restyle the password submit button**

Replace:

```dart
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: Text('account_settings_submit'.tr()),
          ),
```

with:

```dart
          BrutalistButton(
            label: 'account_settings_submit'.tr(),
            icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
            onPressed: _submitting ? null : _submit,
          ),
```

The error-state Retry `TextButton` (lines ~29-32, `onPressed: () => ref.invalidate(identityInfoProvider)`) is explicitly out of scope — do not touch it.

- [ ] **Step 3: Run tests and analyze**

Run: `cd app && flutter test test/features/settings/account_settings_screen_test.dart && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/settings/account_settings_screen.dart
git commit -m "feat: restyle AccountSettingsScreen with BrutalistButton"
```

---

### Task 3: Restyle `NotificationSettingsScreen`

**Files:**
- Modify: `app/lib/features/settings/notification_settings_screen.dart`
- Test: `app/test/features/settings/notification_settings_screen_test.dart` (confirmed this session: 2 `find.byType(SwitchListTile)` matchers — both stay valid since `SwitchListTile` is not replaced, only wrapped; no test changes needed)

**Interfaces:**
- Consumes: `BrutalistCard` (existing, unchanged).

- [ ] **Step 1: Add import**

In `app/lib/features/settings/notification_settings_screen.dart`, add:

```dart
import '../../core/widgets/brutalist_card.dart';
```

- [ ] **Step 2: Wrap the 3 switches in a `BrutalistCard`**

Replace:

```dart
        data: (prefs) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SwitchListTile(
              title: Text('notification_settings_match_label'.tr()),
              value: _matchOverride ?? prefs.notifyMatch,
              onChanged: (value) => _toggle(notifyMatch: value),
            ),
            SwitchListTile(
              title: Text('notification_settings_message_label'.tr()),
              value: _messageOverride ?? prefs.notifyMessage,
              onChanged: (value) => _toggle(notifyMessage: value),
            ),
            SwitchListTile(
              title: Text('notification_settings_cobroke_request_label'.tr()),
              value: _cobrokeOverride ?? prefs.notifyCobrokeRequest,
              onChanged: (value) => _toggle(notifyCobrokeRequest: value),
            ),
          ],
        ),
```

with:

```dart
        data: (prefs) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            BrutalistCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text('notification_settings_match_label'.tr()),
                    value: _matchOverride ?? prefs.notifyMatch,
                    onChanged: (value) => _toggle(notifyMatch: value),
                  ),
                  SwitchListTile(
                    title: Text('notification_settings_message_label'.tr()),
                    value: _messageOverride ?? prefs.notifyMessage,
                    onChanged: (value) => _toggle(notifyMessage: value),
                  ),
                  SwitchListTile(
                    title: Text('notification_settings_cobroke_request_label'.tr()),
                    value: _cobrokeOverride ?? prefs.notifyCobrokeRequest,
                    onChanged: (value) => _toggle(notifyCobrokeRequest: value),
                  ),
                ],
              ),
            ),
          ],
        ),
```

(`padding: EdgeInsets.zero` since `SwitchListTile`'s own default `contentPadding` already provides spacing — matches this project's established `ListTile`-inside-`BrutalistCard` convention from Phase 2A.)

- [ ] **Step 3: Run tests and analyze**

Run: `cd app && flutter test test/features/settings/notification_settings_screen_test.dart && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/settings/notification_settings_screen.dart
git commit -m "feat: wrap NotificationSettingsScreen's switches in BrutalistCard"
```

---

### Task 4: Restyle `SubscriptionScreen`

**Files:**
- Modify: `app/lib/features/subscription/subscription_screen.dart`
- Test: `app/test/features/subscription/subscription_screen_test.dart` (confirmed this session: no `ElevatedButton` type matcher — no test changes needed)

**Interfaces:**
- Consumes: `BrutalistButton` (existing, unchanged).

- [ ] **Step 1: Add imports**

In `app/lib/features/subscription/subscription_screen.dart`, add:

```dart
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/widgets/brutalist_button.dart';
```

- [ ] **Step 2: Restyle the Refresh button**

Replace:

```dart
                  ElevatedButton(onPressed: _refresh, child: Text('subscription_refresh_button'.tr())),
```

with:

```dart
                  BrutalistButton(
                    label: 'subscription_refresh_button'.tr(),
                    icon: PhosphorIcons.arrowClockwise(PhosphorIconsStyle.bold),
                    onPressed: _refresh,
                  ),
```

- [ ] **Step 3: Restyle the Manage Subscription button**

Replace:

```dart
                ElevatedButton(
                  onPressed: _submitting ? null : _manageSubscription,
                  child: Text('subscription_manage_button'.tr()),
                ),
```

with:

```dart
                BrutalistButton(
                  label: 'subscription_manage_button'.tr(),
                  icon: PhosphorIcons.gear(PhosphorIconsStyle.bold),
                  onPressed: _submitting ? null : _manageSubscription,
                ),
```

- [ ] **Step 4: Restyle the Upgrade button**

Replace:

```dart
                ElevatedButton(
                  onPressed: _submitting ? null : _upgrade,
                  child: Text('subscription_upgrade_button'.tr()),
                ),
```

with:

```dart
                BrutalistButton(
                  label: 'subscription_upgrade_button'.tr(),
                  icon: PhosphorIcons.crown(PhosphorIconsStyle.bold),
                  onPressed: _submitting ? null : _upgrade,
                ),
```

The error-state Retry `TextButton` (`onPressed: () => ref.invalidate(subscriptionStatusProvider)`) is explicitly out of scope — do not touch it.

- [ ] **Step 5: Run tests and analyze**

Run: `cd app && flutter test test/features/subscription/subscription_screen_test.dart && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/subscription/subscription_screen.dart
git commit -m "feat: restyle SubscriptionScreen with BrutalistButton"
```

---

### Task 5: Restyle `ReviewsScreen`

**Files:**
- Modify: `app/lib/features/ratings/reviews_screen.dart`
- Test: `app/test/features/ratings/reviews_screen_test.dart` (confirmed this session: no `Card` type matcher — no test changes needed)

**Interfaces:**
- Consumes: `BrutalistCard` (existing, unchanged).

- [ ] **Step 1: Add import**

In `app/lib/features/ratings/reviews_screen.dart`, add:

```dart
import '../../core/widgets/brutalist_card.dart';
```

- [ ] **Step 2: Add the empty-state illustration**

Replace:

```dart
        if (candidates.isEmpty) {
          return Center(child: Text('rating_reviews_empty'.tr()));
        }
```

with:

```dart
        if (candidates.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/illustrations/reviews_empty.png',
                  height: 160,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),
                Text('rating_reviews_empty'.tr()),
              ],
            ),
          );
        }
```

- [ ] **Step 3: Restyle the review row card**

Replace:

```dart
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(candidate.rater.fullName, style: Theme.of(context).textTheme.titleMedium),
```

with:

```dart
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BrutalistCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(candidate.rater.fullName, style: Theme.of(context).textTheme.titleMedium),
```

`Card(margin:, child: Padding(padding:, child: Column(...)))` and `Padding(padding:, child: BrutalistCard(child: Column(...)))` both wrap `Column` two levels deep — the closing braces after `Column`'s children list need no change, only these opening lines.

- [ ] **Step 4: Run tests and analyze**

Run: `cd app && flutter test test/features/ratings/reviews_screen_test.dart && flutter analyze`
Expected: All PASS, no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/ratings/reviews_screen.dart
git commit -m "feat: restyle ReviewsScreen with BrutalistCard"
```

---

## After this plan

This closes the Urby Restyle initiative's planned screen coverage (Phase 1's 3 flagship screens + Phase 2A's 8 + Phase 2B's 7 + Phase 2C's 5 real changes = 23 screens restyled, plus `PrivacyScreen`/`HelpScreen` confirmed to need nothing). Real illustration artwork for all 10 reserved empty-state slots (2 Phase 1 + 4 Phase 2A + 3 Phase 2B + 1 this phase) remains the only outstanding item on the design track, still not sourced as of this plan.
