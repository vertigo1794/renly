# renly — Auth + Verification Module Design

Status: approved (2026-08-16). Second milestone, built on the Flutter scaffold merged in `docs/superpowers/specs/2026-08-16-renly-mvp-design.md`. Design/features still expected to evolve — this is the working spec, not a frozen contract.

## Goal

Registration + login flow that gets a negotiator from "never used renly" to "account created, verification pending" — matching the Stitch mockups (`login_register_selection_english_official_style`, `registration_personal`, `registration_professional`) and reusing the already-built `VerificationPendingScreen`. No automated LPPEH register cross-check yet (no public API exists per the proposal) — every registration lands in `pending` and stays there until manually flipped by an admin later. That admin flow is out of scope here.

## Gap the mockups don't cover

None of the 13 Stitch mockups include an email/password (or OTP) screen — registration only collects name/IC/phone/REN-number/agency/tag-photo. Supabase Auth needs a credential. Decision: **email + password**, fields added to Registration Step 1 (Personal Details) alongside the existing fields. The Login screen itself also isn't mocked — build a plain email/password form using the same Lumina Prime component style (input styling from `AppTheme.light.inputDecorationTheme`) as the registration forms.

## Screens

All under `lib/features/auth/` (folds in the existing `lib/features/verification/verification_pending_screen.dart` — settles the design-doc drift the Milestone-1 review flagged: the doc always said `features/auth/` should own verification, code had it split out).

1. **`AuthSelectionScreen`** (`auth_selection_screen.dart`) — ports `login_register_selection_english_official_style/code.html`: logo, tagline, "Create account" (primary, white pill) / "Log In" (outline pill) buttons on lime (`#D4FF00`) background.
2. **`LoginScreen`** (`login_screen.dart`) — not mocked, built fresh: email field, password field, submit button, "Don't have an account? Create one" link back to `AuthSelectionScreen`.
3. **`RegistrationPersonalScreen`** (`registration_personal_screen.dart`) — ports `registration_personal/code.html`, Step 1 of 2. Fields, in order: **email**, **password**, **confirm password** (new, not in mockup), then mockup's own `fullName`, `icNumber` (Malaysian format `NNNNNN-NN-NNNN`), `phoneNumber`. "Next Step" submits `AuthRepository.signUp(...)`, then navigates to Step 2 carrying the new `negotiator_id`.
4. **`RegistrationProfessionalScreen`** (`registration_professional_screen.dart`) — ports `registration_professional/code.html`, Step 2 of 2. Fields: `ren-number`, `agency-name` (free text), REN tag photo (image picker, not live camera scan — camera/OCR tag-scanning is explicitly deferred per the original proposal's own fallback design). "Complete Registration" submits, uploads the photo, writes the DB rows, routes to `VerificationPendingScreen`.
5. **`VerificationPendingScreen`** — already built (Milestone 1), moves folder, otherwise unchanged.

Onboarding carousel (3 marketing slides) is explicitly out of scope for this milestone — `/` routes straight to `AuthSelectionScreen`. Revisit once the core flow works end to end.

## Data model changes

Three tables from the original ERD get created now (they didn't exist yet — Milestone 1 only scaffolded the Flutter client, no DB objects). `negotiator` gains two columns the ERD didn't have: `ic_number`, `phone_number` — the mockups collect both and the original ERD missed them.

```sql
-- agency
create table agency (
  agency_id uuid primary key default gen_random_uuid(),
  firm_name text not null,
  registration_no text,
  address text,
  created_at timestamptz not null default now()
);
create unique index agency_firm_name_lower_idx on agency (lower(trim(firm_name)));

-- negotiator (negotiator_id IS the Supabase Auth user id — 1:1 with auth.users)
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

-- verification_record (immutable audit trail — insert/select only, no update/delete policy)
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
```

**RLS** (deny-by-default is the platform default the moment `enable row level security` runs — every table gets an explicit policy per the Milestone-1 design doc's global constraint):

```sql
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
```

`agency` insert is intentionally open to any authenticated user (find-or-create pattern below) — agency name/registration-no/address isn't sensitive data, and full agency-account activation is still out of scope (per Milestone-1 doc's "explicitly deferred" list).

**Storage** — REN tag photos, one private bucket, path convention `{auth.uid()}/tag.jpg` so the RLS policy can check ownership from the path itself:

```sql
insert into storage.buckets (id, name, public) values ('ren-tags', 'ren-tags', false)
  on conflict (id) do nothing;

create policy ren_tags_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'ren-tags' and (storage.foldername(name))[1] = auth.uid()::text);
create policy ren_tags_select_own on storage.objects for select to authenticated
  using (bucket_id = 'ren-tags' and (storage.foldername(name))[1] = auth.uid()::text);
```

## Auth + registration flow

**Sign-up (Step 1 submit):**
1. `Supabase.instance.client.auth.signUp(email: ..., password: ...)` → returns a `User` with `id`.
2. Insert into `negotiator`: `negotiator_id = user.id`, `full_name`, `ic_number`, `phone_number`, `verification_status = 'pending'` (default), `subscription_tier = 'free'` (default).
3. Navigate to Step 2, carrying `negotiator_id` (route extra / provider state — Step 2 doesn't re-derive it from Supabase Auth session alone, since Step 1's insert already ran and Step 2 only needs to update the same row).

**Professional details (Step 2 submit):**
1. Find-or-create agency: `insert into agency (firm_name) values ($1) on conflict ((lower(trim(firm_name)))) do nothing returning agency_id` — if no row returned (conflict), follow with `select agency_id from agency where lower(trim(firm_name)) = lower(trim($1))`.
2. Upload tag photo to Storage: path `{negotiator_id}/tag.jpg`, bucket `ren-tags`.
3. Update `negotiator` row: `ren_number`, `agency_id`.
4. Insert `verification_record`: `negotiator_id`, `method = 'manual_registration'`, `tag_photo_url` (the storage path), `outcome = 'pending'` (default).
5. Navigate to `VerificationPendingScreen`.

**Login:**
1. `Supabase.instance.client.auth.signInWithPassword(email: ..., password: ...)`.
2. Fetch own `negotiator` row (RLS-scoped, so this always returns exactly the caller's row, or nothing if the Step 1 insert never completed — e.g. app was killed between `signUp()` succeeding and the `negotiator` insert running).
3. Route by outcome: no `negotiator` row → a plain error screen state on `LoginScreen` itself ("Registration incomplete — contact support to finish setup"; building a full resume-mid-registration flow is out of scope, this is a rare edge case, not a path to design UI around this pass). `verification_status = 'pending'` → `VerificationPendingScreen`. `approved`/`rejected` → a minimal temporary placeholder screen (`HomePlaceholderScreen`, one line: "You're verified — dashboard coming soon") since the real dashboard is a later milestone, not building a throwaway screen's worth of scope here beyond one placeholder.

## Router

`appRouter` (currently a top-level `final GoRouter`) becomes `final appRouterProvider = Provider<GoRouter>((ref) => ...)`, so its `redirect` callback can `ref.watch` an auth-state stream provider and react to sign-in/sign-out without the widget tree needing to poll. This was flagged as a Minor backlog item in the Milestone-1 review — this is the first module that actually needs it (auth-gated navigation), so fixing it now instead of layering more routes on the global-const version.

Routes: `/` → `AuthSelectionScreen`, `/login` → `LoginScreen`, `/register/personal` → `RegistrationPersonalScreen`, `/register/professional` → `RegistrationProfessionalScreen` (requires the `negotiator_id` route extra from Step 1, redirects back to `/register/personal` if missing), `/verification-pending` → `VerificationPendingScreen`, `/home` → `HomePlaceholderScreen`.

## File structure

```
lib/
  core/
    router/
      app_router.dart          # Provider<GoRouter>, redirect logic
  features/
    auth/
      auth_selection_screen.dart
      login_screen.dart
      registration_personal_screen.dart
      registration_professional_screen.dart
      verification_pending_screen.dart      # moved from features/verification/
      auth_repository.dart                  # Supabase Auth + negotiator/agency/verification_record calls
      auth_providers.dart                   # Riverpod providers: authStateProvider, negotiatorProfileProvider
      home_placeholder_screen.dart
```

`AuthRepository` is the only file that talks to Supabase directly for this module — screens call repository methods, never `Supabase.instance.client` inline. This keeps the Supabase-specific code (table names, RLS-shaped queries) in one testable, mockable place.

## Manual setup (user does this once, same pattern as `.env` in Milestone 1)

1. Paste the SQL above (combined into one migration file the plan will generate) into the Supabase project's **SQL Editor** and run it.
2. Supabase Dashboard → **Authentication → Sign In / Providers → Email** → turn off "Confirm email", so `signUp()` returns an active session immediately instead of requiring an out-of-app email-link click before Step 2 can proceed. (Acceptable for a development/demo-stage app; revisit before any real production launch.)

Neither step is automatable from here — this session has no DB credentials or dashboard access to the user's Supabase project.

## Testing approach

- `AuthRepository` methods get unit tests against a fake/mock Supabase client where feasible (form validation logic — IC format, password confirmation match, email format — is pure Dart and fully unit-testable regardless).
- Screen widget tests follow the Milestone-1 pattern (`testWidgets` + `EasyLocalization` + `GoogleFonts.config.allowRuntimeFetching = false`), asserting the right fields render and required-field validation blocks submit.
- No integration test against a real Supabase project in this pass (would require live credentials in CI, out of scope) — the manual `flutter run` verification the user's already doing live is the end-to-end check for this milestone.

## Explicitly deferred / out of scope for this milestone

- Onboarding carousel (3 marketing slides).
- Camera live tag-scanning / OCR (photo upload only, per the proposal's own documented fallback).
- Automated LPPEH register cross-check (no public API exists).
- Admin review UI for flipping `verification_status` from `pending`.
- Real home dashboard (one-line placeholder screen only).
- Territory field on `negotiator` (in the ERD, not collected by any current mockup — leave nullable).
