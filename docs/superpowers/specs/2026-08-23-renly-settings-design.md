# renly — Settings Design

## Goal

Build the Notification/Account/Privacy/Help settings sub-pages shown in the Stitch `profile_settings` mockup's "App Settings" list, appended to the existing `ProfileScreen`.

## Source of truth

Like Ratings/Reviews, this has no basis in the original proposal/ERD — it comes purely from `stitch_renly_property_agent_network/profile_settings/code.html`, which shows a 4-row settings list (Notification / Account / Privacy / Help) between the stat cards and the Log Out button. The mockup export only contains this list screen; none of the 4 destination screens have a mockup, so their content is defined here from scratch, confirmed with the user during brainstorm:

- **Notification**: 3 category toggles (new match, new message, new co-broke request), persisted to the database, but functionally inert — this app has no push notification delivery (FCM is not wired in anywhere in the codebase). Chosen deliberately over a fully-static toggle so that when FCM eventually lands, the toggles are already real and don't need rebuilding.
- **Account**: change password (Supabase Auth) + read-only display of identity info (IC number, phone number, REN number).
- **Privacy**: static text screen (data collected / how it's shared with other negotiators). No toggle — explicitly chosen over a "show my contact info" toggle because there's no existing feature it would meaningfully gate (phone/IC are already private at the RLS/select level; name/REN are already public via `get_listing_owner_info`).
- **Help**: static FAQ + static contact info (email/phone text). No submission form — explicitly dropped after discussion, since there is no admin UI or backend to receive submissions (verification approval itself is still done by hand via the Supabase Table Editor).

## Data model

One new migration, `supabase/migrations/0012_settings.sql`:

```sql
alter table negotiator add column if not exists notify_match boolean not null default true;
alter table negotiator add column if not exists notify_message boolean not null default true;
alter table negotiator add column if not exists notify_cobroke_request boolean not null default true;

-- Additive only -- no preceding `revoke update`. Postgres GRANT is additive
-- (it does not replace or reset prior column grants); only REVOKE resets a
-- privilege set. 0010_profile.sql's migration comment documents exactly why
-- a revoke+narrower-regrant pair is dangerous here (it silently stripped 5
-- pre-existing UPDATE columns in that milestone's Critical bug). This
-- migration sidesteps the entire bug class by never revoking at all -- the
-- existing 7-column UPDATE grant on negotiator
-- (full_name, ic_number, phone_number, ren_number, agency_id, territory,
-- property_specialisation) is untouched, and these 3 columns are simply
-- added on top of it.
grant update (notify_match, notify_message, notify_cobroke_request) on negotiator to authenticated;
```

No RLS policy changes needed — `negotiator_update_own`/`negotiator_select_own` (both row-scoped, `auth.uid() = negotiator_id`) already cover these columns exactly as they cover every other column on the row. No new table, no new grant for Privacy/Help (pure static content, no backend at all). Account's identity-info read needs no new grant either — `negotiator` has never had a column-scoped SELECT grant (SELECT was never revoked in `0001`/`0002`), so `ic_number`/`phone_number` are already selectable under the existing row-level policy; they've simply never been *queried* by the client before, since `ProfileRepository.fetchMyProfile`'s explicit column list omits them (a deliberate PII-minimization choice from Profile Management's final review — don't pull IC/phone into memory on every Profile screen view). Account's screen adds a second, narrower, on-demand query instead of touching that existing minimized query.

## Components

**`SettingsRepository`** (`app/lib/features/settings/settings_repository.dart`), sole Supabase touchpoint for this feature:

- `fetchNotificationPreferences(String negotiatorId) -> Future<NotificationPreferences>` — selects `notify_match, notify_message, notify_cobroke_request` from `negotiator`, `.eq('negotiator_id', ...).single()`.
- `updateNotificationPreferences({required String negotiatorId, required bool notifyMatch, required bool notifyMessage, required bool notifyCobrokeRequest}) -> Future<void>` — plain UPDATE on the same 3 columns.
- `fetchIdentityInfo(String negotiatorId) -> Future<IdentityInfo>` — selects `ic_number, phone_number, ren_number` from `negotiator`, `.eq('negotiator_id', ...).single()`. Only called when the Account screen is opened, not from `ProfileScreen`.
- `updatePassword(String newPassword) -> Future<void>` — `Supabase.instance.client.auth.updateUser(UserAttributes(password: newPassword))`. No re-authentication step: the session is already authenticated, matching Supabase Auth's own `updateUser` contract (no current-password argument exists in the SDK call).

**Models** (`app/lib/features/settings/models/`): `NotificationPreferences` (3 `bool` fields), `IdentityInfo` (`icNumber`, `phoneNumber`, `renNumber`, all `String?`).

**`settings_providers.dart`**: `settingsRepositoryProvider`, this feature's own `currentNegotiatorIdProvider` copy (established per-file duplication pattern, same as every other feature), `notificationPreferencesProvider = FutureProvider.autoDispose<NotificationPreferences>`, `identityInfoProvider = FutureProvider.autoDispose<IdentityInfo>`.

**Screens** (`app/lib/features/settings/`):
- `NotificationSettingsScreen` — 3 `SwitchListTile` rows bound to `notificationPreferencesProvider`, each `onChanged` calls `updateNotificationPreferences` directly (no separate save button — matches the mockup's toggle-is-the-action convention, distinct from `_EditForm`'s explicit-save pattern since there's no multi-field form here, just independent toggles) and `ref.invalidate`s the provider on success. Wrapped in try/catch with visible inline error on failure, matching `PropertyDetailScreen._changeStatus`'s established precedent.
- `AccountSettingsScreen` — top section shows `identityInfoProvider`'s data as read-only `Text` rows (IC/phone/REN, `'-'` fallback for null, same convention as `ProfileScreen`'s REN/agency display); below it, a password-change `Form` (`GlobalKey<FormState>`, new-password + confirm-password fields, `_submitting`/`_submitError` state pair) mirroring `ProposeAgreementDialog`'s established form-state pattern, calling `SettingsRepository.updatePassword` on submit. Validation reuses the existing `AuthValidation` helper (`app/lib/features/auth/auth_validation.dart`) exactly as registration already does: `AuthValidation.isValidPassword` (≥8 chars) on the new-password field, `AuthValidation.passwordsMatch` on the confirm field — no new validation logic invented for this screen.
- `PrivacyScreen` — `Scaffold` + `SingleChildScrollView` of static localized `Text` blocks. No provider, no repository call.
- `HelpScreen` — same static-content shape as `PrivacyScreen`: an FAQ section (a few Q/A pairs as localized text) + a contact section (static email/phone text, not a `mailto:`/`tel:` launcher — no new package dependency for this).

**`ProfileScreen` change**: a new "App Settings" section inserted between the stat-card `Row` and the Log Out `OutlinedButton` (matching the mockup's own layout order exactly), rendered as 4 `ListTile`s inside a `Card` (mirrors the "Settings List Container" grouping in the mockup), each navigating via `context.push('/settings/...')`.

**Router**: 4 new routes appended after `/reviews` in `app_router.dart`: `/settings/notification`, `/settings/account`, `/settings/privacy`, `/settings/help`. No path parameters on any of them.

## Error handling

Password change surfaces Supabase Auth errors (e.g. weak-password rejection) as inline form error text via `listing_error_generic`, same convention as every prior form in this codebase — Supabase Auth error messages are not shown verbatim to the user (established pattern: raw exception text is never surfaced). Notification toggle failures are wrapped in try/catch with a visible inline error and the toggle visually reverting (re-reading from the invalidated provider rather than trusting local optimistic state), matching `PropertyDetailScreen._changeStatus`. Privacy/Help have no error states — static content only.

## Testing approach

`SettingsRepository` is untested, per this codebase's established Supabase-boundary convention. `NotificationPreferences.fromJson`/`IdentityInfo.fromJson` get real unit tests (mirrors `Rating.fromJson`'s precedent). Widget tests via provider override for: `NotificationSettingsScreen` (toggle renders correct initial state, tap calls update), `AccountSettingsScreen` (identity info renders, password-mismatch validation blocks submit, successful submit calls the repository). `PrivacyScreen`/`HelpScreen` get a smoke test confirming they render without error — no logic to exercise. `ProfileScreen`'s new settings section gets a widget test confirming all 4 rows are present and each navigates to its expected route (mirrors the existing `_AgreementSection`/Rate-button navigation test style in `my_requests_screen_test.dart`).

## Manual setup

Run `supabase/migrations/0012_settings.sql` in the Supabase SQL Editor after `0001`-`0011`. No new bucket, no new RLS policy, no Realtime — a normal smoke test (open each of the 4 settings screens, toggle a notification preference, change password once) is sufficient. No sequence-sensitive verification needed (unlike Ratings) since nothing here depends on cross-user visibility.

## Explicitly deferred / out of scope for this milestone

- Actual push notification delivery (FCM) — the 3 toggles remain inert until that infrastructure exists, tracked separately in project status memory.
- Help's contact form / any backend message-receiving mechanism — explicitly dropped, no admin UI exists to act on submissions.
- Privacy toggles of any kind — static text only.
- The mockup's 4th stat-card action ("View Full Report") — unrelated to this settings scope, not built here.
- `mailto:`/`tel:` deep links on Help's contact info — plain static text, no `url_launcher` dependency added for this.
