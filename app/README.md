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
