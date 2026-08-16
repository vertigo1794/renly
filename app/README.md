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
