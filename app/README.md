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

1. **Run the migration.** Open the Supabase dashboard for this project -> SQL Editor -> New query. Paste the entire contents of `supabase/migrations/0001_auth_verification.sql` (repo root, not inside `app/`) and click Run. This creates the `negotiator`, `agency`, and `verification_record` tables, their Row-Level Security policies, and the `ren-tags` storage bucket.
2. **Disable email confirmation.** Dashboard -> Authentication -> Sign In / Providers -> Email -> turn off "Confirm email". Without this, `signUp()` requires the user to click a confirmation link in their inbox before a session is active, which would strand Step 1 of registration before Step 2 can run. This is fine for development; revisit before any real production launch.

Registration won't work (Postgrest errors on every insert) until step 1 is done. Login will hang waiting for email confirmation until step 2 is done.
