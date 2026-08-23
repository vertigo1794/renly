# renly

Verified co-broking platform for Malaysian real estate negotiators.

## Setup

### 1. Get Flutter on your PATH

The Flutter SDK lives at `~/development/flutter/bin` and is not on `PATH` by default. For the current terminal session:

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
```

To persist it, add that line to `~/.zshrc`, then restart your terminal (or run `source ~/.zshrc`).

Verify with `flutter --version`.

### 2. Install dependencies

From the `app/` directory:

```bash
flutter pub get
```

### 3. Configure environment variables

```bash
cp .env.example .env
```

Then open `.env` and fill in your real Supabase project URL and anon key, found in the Supabase dashboard under **Project Settings → API**.

> **Trap:** `.env` is registered as a pubspec asset (required at runtime by `flutter_dotenv`). If it doesn't exist, `flutter test` fails with `No file or variants found for asset: .env`. An **empty** `.env` file is enough to satisfy the asset bundler and run tests without real credentials — but `flutter run` needs real Supabase credentials in it to actually work.

### 4. Run tests and the app

```bash
flutter test   # run the test suite
flutter run    # run the app
```

## Milestone 2 setup (auth + verification)

Two one-time steps in the Supabase dashboard, in addition to the `.env` setup above:

1. **Run both migrations, in order.** Open the Supabase dashboard for this project -> SQL Editor -> New query. The migrations live at the repo root, not inside `app/`:
   1. Paste the entire contents of `supabase/migrations/0001_auth_verification.sql` and click Run. This creates the `negotiator`, `agency`, and `verification_record` tables, their Row-Level Security policies, and the `ren-tags` storage bucket.
   2. Then, in a new query, paste the entire contents of `supabase/migrations/0002_rls_hardening.sql` and click Run. This adds the column-level `GRANT`/`REVOKE` hardening that RLS alone can't express — without it any signed-up user can PATCH their own `verification_status` to `approved` and their `subscription_tier` to `professional`, bypassing the verification gate entirely. It also adds the storage `UPDATE` policy that re-uploads (`upsert: true`) need, plus size/MIME limits on the `ren-tags` bucket.

   If you already ran `0001` before `0002` existed, just run `0002` on top — it is written to apply cleanly against an existing `0001` database.
2. **Disable email confirmation.** Dashboard -> Authentication -> Sign In / Providers -> Email -> turn off "Confirm email". Without this, `signUp()` requires the user to click a confirmation link in their inbox before a session is active, which would strand Step 1 of registration before Step 2 can run. This is fine for development; revisit before any real production launch.

Registration won't work (Postgrest errors on every insert) until step 1 is done. Login will hang waiting for email confirmation until step 2 is done.

## Milestone 3 setup (listing)

One more SQL file, same process as before: Supabase dashboard -> SQL Editor -> New query -> paste the entire contents of `supabase/migrations/0003_listing.sql` (repo root) -> Run. This creates the `listing` table, its RLS policies, and the `listing-photos` storage bucket. No Auth-dashboard changes needed this time.

**Then run a second file:** in a new query, paste the entire contents of `supabase/migrations/0004_listing_hardening.sql` and Run. It must go **after** `0003_listing.sql`. This one:

- scopes the `listing` policies to `authenticated` (as shipped in `0003` they were also readable by the `anon` role — the key baked into the app — so anyone could read every active listing straight from the REST API);
- adds the column-level `GRANT`/`REVOKE` hardening so `created_at`, `listing_id` and `negotiator_id` can't be rewritten by their owner;
- adds non-negative `CHECK`s on `bedrooms`/`bathrooms`;
- creates the `get_listing_owner_info()` function that the property detail screen calls to show a listing's negotiator name + REN number. Without it that section renders blank for every listing you don't own.

Like `0002`, this file is written to be re-runnable — running it twice is harmless.

## Milestone 4 setup (requirement)

One more SQL file, same process as before: Supabase dashboard -> SQL Editor -> New query -> paste the entire contents of `supabase/migrations/0005_requirement.sql` (repo root) -> Run. This creates the `requirement` table, its RLS policies (scoped to `authenticated` and column-grant hardened from the start this time), and the `requirement-photos` storage bucket. No Auth-dashboard changes needed. Unlike Milestone 3, there's no separate hardening file to run afterwards -- everything is in this one file.

## Milestone 5 setup (matching)

One more SQL file, same process as before: Supabase dashboard -> SQL Editor -> New query -> paste the entire contents of `supabase/migrations/0006_matching.sql` (repo root) -> Run. This creates the `match` table and its two RLS policies. No storage bucket, no Auth-dashboard changes.

## Milestone 6 setup (co-broke request)

One more SQL file, same process as before: Supabase dashboard -> SQL Editor -> New query -> paste the entire contents of `supabase/migrations/0007_cobroke_request.sql` (repo root) -> Run. This creates the `cobroke_request` table and its three RLS policies. No storage bucket, no Auth-dashboard changes.

## Milestone 7 setup (messaging)

Run `supabase/migrations/0008_messaging.sql` in the Supabase SQL Editor after 0001-0007. This creates the `message` table, its RLS policies, and enables Realtime delivery for it (`alter publication supabase_realtime add table message;`) — no separate Database > Replication dashboard step is needed, it's included in the migration. If that statement ever errors with "must be owner of publication" (a role-permissions edge case, not expected on this project), toggle `message` on manually under Database > Replication instead.

## Milestone 8 setup (agreement)

Run `supabase/migrations/0009_agreement.sql` in the Supabase SQL Editor after 0001-0008. This creates the `agreement` table, its RLS policies, and a trigger that sets `accepted_at` server-side when an agreement's status moves to `accepted` -- no manual dashboard step beyond running the SQL.

## Milestone 9 setup (profile)

Run `supabase/migrations/0010_profile.sql` in the Supabase SQL Editor after 0001-0009. This adds `negotiator.property_specialisation` and re-grants UPDATE on `(full_name, ic_number, phone_number, ren_number, agency_id, territory, property_specialisation)` -- the same 6 columns 0002_rls_hardening.sql already granted, plus the new one (a bare revoke without restating all 6 would silently break registration Step 2).

After running, verify the grant with this query -- expect UPDATE listed for exactly those 7 columns, and NO row for `verification_status` or `subscription_tier`:
```sql
select grantee, privilege_type, column_name
from information_schema.column_privileges
where table_name = 'negotiator' and grantee = 'authenticated';
```

## Milestone 10 setup (rating)

Run `supabase/migrations/0011_rating.sql` in the Supabase SQL Editor after 0001-0010. This creates the `rating` table, its RLS policies, an `is_agreement_party` helper function (SECURITY DEFINER -- required so the party check still works after a listing/requirement is marked sold/fulfilled/withdrawn, when it would otherwise be hidden from the other party by listing_select/requirement_select's own RLS), and a trigger that sets `updated_at` server-side on every update -- no manual dashboard step beyond running the SQL.

After running, verify the grant with this query -- expect UPDATE listed for exactly `stars`/`review_text`, INSERT for exactly `agreement_id`/`rater_id`/`rated_id`/`stars`/`review_text`, and NO UPDATE row for `created_at`/`rater_id`/`rated_id`/`agreement_id`:
```sql
select grantee, privilege_type, column_name
from information_schema.column_privileges
where table_name = 'rating' and grantee = 'authenticated';
```

**Mandatory manual verification, sequence-sensitive:** with two real accounts and an accepted agreement, mark the listing sold and the requirement fulfilled BEFORE testing ratings (this is the step that would have caught the security-definer bug this milestone's final review found -- testing immediately after acceptance passes even with that bug present), then confirm BOTH parties can rate each other, not just the agreement's own initiator rating the other side.

## Milestone 11 setup (settings)

Run `supabase/migrations/0012_settings.sql` in the Supabase SQL Editor after 0001-0011. This adds 3 notification-preference boolean columns to `negotiator` (all default `true`) and an additive-only UPDATE grant for them -- no RLS policy change, no new table, no `revoke` statement. No manual dashboard step beyond running the SQL.

After running, verify the grant with this query -- expect UPDATE listed for `notify_match`/`notify_message`/`notify_cobroke_request` in addition to the 7 columns from Milestone 9's grant (10 UPDATE rows total):
```sql
select grantee, privilege_type, column_name
from information_schema.column_privileges
where table_name = 'negotiator' and grantee = 'authenticated' and privilege_type = 'UPDATE';
```

**Ordering note:** always run migrations in numeric order (0001 through 0012). `0010_profile.sql` contains a `revoke update on negotiator` statement -- re-running it AFTER `0012_settings.sql` would silently strip the 3 notification grants added here, causing the toggles to fail with a permission error. This migration was deliberately written to never revoke, for exactly this reason, but 0010 predates that lesson.

A normal smoke test after running is sufficient beyond the grant check above: open Settings > Notification and confirm all 3 toggles show as ON by default, flip one off and confirm it persists across an app restart.

Consider enabling Supabase's "Secure password change" project setting (Authentication > Settings), which requires a recent login before a password change is accepted -- this codebase's password-change flow has no re-authentication step of its own, by design, since Supabase Auth's `updateUser` API has no current-password parameter.

## Milestone 12 setup (subscription)

Run `supabase/migrations/0013_subscription.sql` in the Supabase SQL Editor after 0001-0012. This adds 4 nullable columns to `negotiator` for Stripe subscription state -- no grant statement of any kind is added for them, ever (unlike every other new-column migration in this project). They are written only by the `stripe-webhook` Edge Function using the Supabase service role key, which bypasses grants and RLS entirely.

The same migration also adds `negotiator` to the `supabase_realtime` publication (guarded, re-runnable -- same pattern `0008_messaging.sql` uses for `message`). This is required, not optional: without it the Subscription screen's `.stream()` subscription receives its initial snapshot and then never sees the tier flip written by `stripe-webhook`, so a user who has just paid successfully sits on "This is taking longer than expected" until they manually tap Refresh. It is now included in the migration, so there is no separate step to remember -- just re-run `0013_subscription.sql` if you applied an earlier copy of it before this was added.

This milestone also requires deploying 3 new Supabase Edge Functions and configuring a Stripe account (test mode) -- see the Subscription Core design doc (`docs/superpowers/specs/2026-08-24-renly-subscription-core-design.md`) for the full manual setup sequence (Stripe account, Price creation, secrets, Edge Function deployment with `--no-verify-jwt` on `stripe-webhook`, webhook registration). This is NOT just a SQL paste-and-run step like every prior migration -- the migration alone does nothing useful until the Edge Functions are deployed and the webhook is registered.

`supabase/config.toml` now declares `[functions.stripe-webhook] verify_jwt = false`, which structurally enforces the `--no-verify-jwt` requirement for that one function so it survives any future redeploy even if someone forgets the flag. The header comment in `supabase/functions/stripe-webhook/index.ts` explaining *why* the flag is mandatory stays as-is -- the two are defence in depth, not duplicates: the comment tells a human why, the config file makes the tooling do it. `project_id` in that file is a local identifier only; the remote project ref still comes from `supabase link` or `--project-ref`.

Android note: `MainActivity` extends `FlutterFragmentActivity` (not `FlutterActivity`) and the launch/normal themes descend from `Theme.MaterialComponents.*`. Both are hard requirements of flutter_stripe -- the PaymentSheet is an AndroidX `BottomSheetDialogFragment` and Stripe's SDK throws under a non-AppCompat theme. Do not revert either when regenerating Android platform files.

## Milestone 13 setup (tier gating)

Run `supabase/migrations/0014_tier_gating.sql` in the Supabase SQL Editor after 0001-0013. This adds two `before insert or update` triggers (`listing_active_cap_trigger`, `requirement_active_cap_trigger`) enforcing the Free-tier cap of 3 active listings and 3 active requirements (independently) -- the actual, server-side enforcement, not just a client-side UI convenience. No RLS/grant changes -- these are plain triggers, transparent to the existing insert/update policies. No manual dashboard step beyond running the SQL.

**Manual verification:** as a free-tier negotiator, create 3 active listings, then attempt a 4th -- confirm it's rejected (both via the app's own disabled-button UX, and by attempting the same insert directly in the SQL Editor to confirm the trigger itself, not just the client check, is what's blocking it). Confirm withdrawing one of the 3 then posting a new one succeeds. Confirm reactivating a withdrawn listing while already at 3 active ones is also rejected -- verify this BOTH via the app (PropertyDetailScreen's "Reactivate Listing" button should be disabled) AND by attempting the same `update listing set status = 'active' where listing_id = '...'` directly in the SQL Editor. The client-side check disables that button before any database call happens, so the app-only check alone proves nothing about whether the trigger's reactivation branch (the `TG_OP = 'UPDATE' and old.status = 'active'` early-return guard in `0014_tier_gating.sql`, which must let an already-active row through while still counting a withdrawn-to-active transition) actually works -- it is the easiest branch to get backwards. Confirm a Professional-tier negotiator is never blocked by any of the above.

Repeat all four checks for requirements specifically -- do not assume the mirror trigger behaves identically without testing it: (1) a 4th active requirement is rejected via the app AND via a direct SQL Editor insert; (2) withdrawing one requirement then posting a new one succeeds; (3) reactivating a withdrawn requirement while at 3 open ones is rejected via the app (RequirementDetailScreen's "Reactivate Requirement" button disabled) AND via a direct SQL Editor `update requirement set status = 'open' where requirement_id = '...'`; (4) a Professional-tier negotiator is never blocked.
