# Agreement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let two negotiators with an ACCEPTED co-broke request propose, accept, or decline a digital co-broking agreement recording the commission split, gated at the RLS level on `cobroke_request.status = 'accepted'`.

**Architecture:** An `agreement` table with RLS joining through `cobroke_request` -> `match` -> `listing`/`requirement` (same ownership-join pattern as `message`). `AgreementRepository` needs no composed dependency (no owner-name lookups required -- the counterparty's name is already shown by the surrounding row). All UI lives inline inside `MyRequestsScreen`'s existing accepted-row `Card`, via a new `_AgreementSection` widget and a `ProposeAgreementDialog` -- no new screen, no new route. No Supabase Realtime in this milestone.

**Tech Stack:** Flutter, Riverpod, supabase_flutter, easy_localization (EN/MS). No new dependencies.

## Global Constraints

- RLS gate: `agreement_select`/`agreement_insert`/`agreement_update_by_recipient` all require `cobroke_request.status = 'accepted'` for the underlying request -- not just a UI-level check.
- `agreement_update_by_recipient` needs an explicit `WITH CHECK`, genuinely different from its `USING` clause -- the lesson from `cobroke_request`'s Critical bug: a `FOR UPDATE` policy that omits `WITH CHECK` has Postgres reuse `USING` against the new row too, and accept/decline is specifically designed to move `status` AWAY from `'pending'`.
- `accepted_at` is set ONLY by a database trigger, never by the client -- it is in neither the INSERT nor UPDATE column grant.
- Column-scoped grants: `insert (request_id, initiator_id, split_initiator, split_counterparty, terms)`, `update (status)` only.
- `AgreementRepository` is untested directly (Supabase-calling code) -- established project convention. `Agreement.fromJson` gets a real unit test. The `MyRequestsScreen` additions get widget tests via provider override.
- `currentNegotiatorIdProvider`: add another own copy in `agreement_providers.dart`, same as every other feature file (`listing`, `requirement`, `matching`, `collaboration`'s `cobroke_request_providers.dart` and `message_providers.dart`) -- deliberately not hoisted to a shared file, per established precedent.
- `agreementForRequestProvider` MUST be `.autoDispose.family`, not bare `.family` -- in this project's pinned Riverpod version (2.6.1), `.family` alone does NOT default to autoDispose (confirmed the hard way during Messaging's final review).
- Client-side sum-to-100 validation must compare as integer cents (`(a * 100).round() + (b * 100).round() == 10000`), never `a + b == 100` on raw `double`s -- floating-point arithmetic can make an exact-100 sum fail an exact equality check even when the two inputs are individually correct.
- l10n: every new user-facing string needs both an `en.json` and `ms.json` entry, same `easy_localization` key-based pattern as `agreement_*` keys below.

---

### Task 1: Supabase Migration SQL (0009_agreement.sql)

**Files:**
- Create: `supabase/migrations/0009_agreement.sql`
- Modify: `app/README.md` (append a "Milestone 8 setup (agreement)" section after the Milestone 7 section)

**Interfaces:**
- Consumes: `cobroke_request` table and its `status` column (from `0007_cobroke_request.sql`), `match` table (from `0006_matching.sql`), `listing`/`requirement`/`negotiator` tables (from earlier migrations).
- Produces: `agreement` table (`agreement_id`, `request_id`, `initiator_id`, `split_initiator`, `split_counterparty`, `terms`, `status`, `accepted_at`, `created_at`) with RLS, used by Task 3's `AgreementRepository`.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/0009_agreement.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0008.
--
-- Written to be re-runnable from the start, same pattern as
-- 0006_matching.sql / 0007_cobroke_request.sql / 0008_messaging.sql
-- (create table if not exists, drop policy/trigger/index if exists before
-- each create).

create table if not exists agreement (
  agreement_id uuid primary key default gen_random_uuid(),
  request_id uuid not null references cobroke_request(request_id) on delete cascade,
  initiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  split_initiator numeric(5,2) not null check (split_initiator > 0 and split_initiator < 100),
  split_counterparty numeric(5,2) not null check (split_counterparty > 0 and split_counterparty < 100),
  terms text,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  check (split_initiator + split_counterparty = 100)
);

-- At most one OPEN (pending or accepted) agreement per request at a time.
-- A declined agreement's status is neither 'pending' nor 'accepted', so it
-- doesn't collide with this index -- re-proposing after a decline is
-- possible, deliberately, same point-in-time pattern as
-- cobroke_request_one_open_per_match.
drop index if exists agreement_one_open_per_request;
create unique index agreement_one_open_per_request
  on agreement(request_id) where status in ('pending', 'accepted');

-- accepted_at is set by the database, never supplied by the client --
-- "recorded immutably with a timestamp" per the proposal means the
-- timestamp itself must be trustworthy, not just the row's existence.
create or replace function agreement_set_accepted_at() returns trigger as $$
begin
  if new.status = 'accepted' and old.status != 'accepted' then
    new.accepted_at := now();
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists agreement_set_accepted_at_trigger on agreement;
create trigger agreement_set_accepted_at_trigger
  before update on agreement for each row
  execute function agreement_set_accepted_at();

alter table agreement enable row level security;

-- Select: viewer must be a party to the underlying cobroke_request (its
-- initiator, or whichever side of the match's listing/requirement they
-- own), AND the request must be status = 'accepted'. Same pattern as
-- message_select.
drop policy if exists agreement_select on agreement;
create policy agreement_select on agreement for select
  to authenticated using (
    exists (
      select 1 from cobroke_request cr
      join match m on m.match_id = cr.match_id
      where cr.request_id = agreement.request_id
        and cr.status = 'accepted'
        and (
          cr.initiator_id = auth.uid()
          or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = auth.uid())
          or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = auth.uid())
        )
    )
  );

-- Insert: initiator must be the current user, and the same accepted-request
-- party check as select.
drop policy if exists agreement_insert on agreement;
create policy agreement_insert on agreement for insert
  to authenticated with check (
    initiator_id = auth.uid()
    and exists (
      select 1 from cobroke_request cr
      join match m on m.match_id = cr.match_id
      where cr.request_id = agreement.request_id
        and cr.status = 'accepted'
        and (
          cr.initiator_id = auth.uid()
          or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = auth.uid())
          or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = auth.uid())
        )
    )
  );

-- Update: ONLY the receiving party (never the agreement's own initiator)
-- may accept/decline, and only while it's still pending. USING gates
-- which EXISTING rows can be touched (must still be pending). WITH CHECK
-- gates what the PROPOSED NEW ROW must look like -- these must be
-- separate, per the lesson from cobroke_request_update_by_recipient's
-- Critical bug: a FOR UPDATE policy that omits WITH CHECK has Postgres
-- reuse USING against the new row too, and the whole point of an
-- accept/decline is to move status AWAY from 'pending' -- so a
-- USING-only policy would reject every one.
drop policy if exists agreement_update_by_recipient on agreement;
create policy agreement_update_by_recipient on agreement for update
  to authenticated using (
    status = 'pending'
    and initiator_id != auth.uid()
    and exists (
      select 1 from cobroke_request cr
      join match m on m.match_id = cr.match_id
      where cr.request_id = agreement.request_id
        and cr.status = 'accepted'
        and (
          cr.initiator_id = auth.uid()
          or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = auth.uid())
          or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = auth.uid())
        )
    )
  )
  with check (
    status in ('accepted', 'declined')
    and initiator_id != auth.uid()
    and exists (
      select 1 from cobroke_request cr
      join match m on m.match_id = cr.match_id
      where cr.request_id = agreement.request_id
        and cr.status = 'accepted'
        and (
          cr.initiator_id = auth.uid()
          or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = auth.uid())
          or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = auth.uid())
        )
    )
  );

revoke insert on agreement from authenticated;
grant insert (request_id, initiator_id, split_initiator, split_counterparty, terms) on agreement to authenticated;

revoke update on agreement from authenticated;
grant update (status) on agreement to authenticated;
```

- [ ] **Step 2: Append README setup section**

Read `app/README.md`, find the "Milestone 7 setup (messaging)" section, and append immediately after it:

```markdown
### Milestone 8 setup (agreement)

Run `supabase/migrations/0009_agreement.sql` in the Supabase SQL Editor after 0001-0008. This creates the `agreement` table, its RLS policies, and a trigger that sets `accepted_at` server-side when an agreement's status moves to `accepted` -- no manual dashboard step beyond running the SQL.
```

- [ ] **Step 3: Verify with grep**

Run:
```bash
cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY"
grep -c "^create table" supabase/migrations/0009_agreement.sql
grep -c "^create policy" supabase/migrations/0009_agreement.sql
grep -c "create trigger" supabase/migrations/0009_agreement.sql
```
Expected: `1`, `3`, `1` (3 policies: `agreement_select`, `agreement_insert`, `agreement_update_by_recipient`).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0009_agreement.sql app/README.md
git commit -m "feat: add agreement Supabase migration with accepted_at trigger"
```

---

### Task 2: Agreement model + unit test

**Files:**
- Create: `app/lib/features/collaboration/models/agreement.dart`
- Test: `app/test/features/collaboration/models/agreement_test.dart`

**Interfaces:**
- Consumes: nothing (leaf model).
- Produces: `Agreement` class with `agreementId`, `requestId`, `initiatorId`, `splitInitiator` (`double`), `splitCounterparty` (`double`), `terms` (`String?`), `status`, `acceptedAt` (`DateTime?`), `createdAt` fields and `Agreement.fromJson(Map<String, dynamic>)` factory -- used by Task 3's `AgreementRepository`, Task 4's providers, and Task 6's `_AgreementSection`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/collaboration/models/agreement_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/collaboration/models/agreement.dart';

void main() {
  group('Agreement.fromJson', () {
    test('parses a pending row with null terms and accepted_at', () {
      final agreement = Agreement.fromJson({
        'agreement_id': 'agr-1',
        'request_id': 'req-1',
        'initiator_id': 'n-1',
        'split_initiator': 60,
        'split_counterparty': 40,
        'terms': null,
        'status': 'pending',
        'accepted_at': null,
        'created_at': '2026-08-24T10:00:00.000Z',
      });

      expect(agreement.agreementId, 'agr-1');
      expect(agreement.requestId, 'req-1');
      expect(agreement.initiatorId, 'n-1');
      expect(agreement.splitInitiator, 60.0);
      expect(agreement.splitCounterparty, 40.0);
      expect(agreement.terms, isNull);
      expect(agreement.status, 'pending');
      expect(agreement.acceptedAt, isNull);
      expect(agreement.createdAt, DateTime.parse('2026-08-24T10:00:00.000Z'));
    });

    test('parses an accepted row with terms and accepted_at', () {
      final agreement = Agreement.fromJson({
        'agreement_id': 'agr-2',
        'request_id': 'req-2',
        'initiator_id': 'n-2',
        'split_initiator': 55.5,
        'split_counterparty': 44.5,
        'terms': 'Standard split after marketing fee',
        'status': 'accepted',
        'accepted_at': '2026-08-24T12:00:00.000Z',
        'created_at': '2026-08-24T10:00:00.000Z',
      });

      expect(agreement.splitInitiator, 55.5);
      expect(agreement.splitCounterparty, 44.5);
      expect(agreement.terms, 'Standard split after marketing fee');
      expect(agreement.status, 'accepted');
      expect(agreement.acceptedAt, DateTime.parse('2026-08-24T12:00:00.000Z'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/collaboration/models/agreement_test.dart`
Expected: FAIL -- `Agreement` is not defined (file doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/features/collaboration/models/agreement.dart

/// A row from the `agreement` table.
class Agreement {
  final String agreementId;
  final String requestId;
  final String initiatorId;
  final double splitInitiator;
  final double splitCounterparty;
  final String? terms;
  final String status;
  final DateTime? acceptedAt;
  final DateTime createdAt;

  const Agreement({
    required this.agreementId,
    required this.requestId,
    required this.initiatorId,
    required this.splitInitiator,
    required this.splitCounterparty,
    this.terms,
    required this.status,
    this.acceptedAt,
    required this.createdAt,
  });

  factory Agreement.fromJson(Map<String, dynamic> json) {
    return Agreement(
      agreementId: json['agreement_id'] as String,
      requestId: json['request_id'] as String,
      initiatorId: json['initiator_id'] as String,
      splitInitiator: (json['split_initiator'] as num).toDouble(),
      splitCounterparty: (json['split_counterparty'] as num).toDouble(),
      terms: json['terms'] as String?,
      status: json['status'] as String,
      acceptedAt: json['accepted_at'] == null ? null : DateTime.parse(json['accepted_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/collaboration/models/agreement_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/collaboration/models/agreement.dart app/test/features/collaboration/models/agreement_test.dart
git commit -m "feat: add Agreement model"
```

---

### Task 3: AgreementRepository

**Files:**
- Create: `app/lib/features/collaboration/agreement_repository.dart`

**Interfaces:**
- Consumes: `Agreement`/`Agreement.fromJson` (Task 2).
- Produces: `AgreementRepository` with `createAgreement({required String requestId, required String initiatorId, required double splitInitiator, required double splitCounterparty, String? terms})`, `acceptAgreement(String agreementId)`, `declineAgreement(String agreementId)`, `fetchAgreementForRequest(String requestId) -> Future<Agreement?>` -- used by Task 4's providers and Task 5/6's UI.

This repository is NOT unit-tested directly -- same established convention as `CobrokeRequestRepository`/`MessageRepository` (Supabase-calling code). No test file for this task.

- [ ] **Step 1: Write the repository**

```dart
// app/lib/features/collaboration/agreement_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/agreement.dart';

/// The only file in this app that talks to Supabase for the agreement
/// feature. Unlike CobrokeRequestRepository/MessageRepository, this one
/// composes nothing else -- an agreement row carries only split
/// percentages and terms, and needs no owner-name lookup (the
/// counterparty's name is already shown by the surrounding
/// CobrokeRequestCandidate row it's nested inside).
class AgreementRepository {
  AgreementRepository(this._client);

  final SupabaseClient _client;

  Future<void> createAgreement({
    required String requestId,
    required String initiatorId,
    required double splitInitiator,
    required double splitCounterparty,
    String? terms,
  }) async {
    await _client.from('agreement').insert({
      'request_id': requestId,
      'initiator_id': initiatorId,
      'split_initiator': splitInitiator,
      'split_counterparty': splitCounterparty,
      'terms': terms,
    });
  }

  Future<void> acceptAgreement(String agreementId) {
    return _client.from('agreement').update({'status': 'accepted'}).eq('agreement_id', agreementId);
  }

  Future<void> declineAgreement(String agreementId) {
    return _client.from('agreement').update({'status': 'declined'}).eq('agreement_id', agreementId);
  }

  /// The most recent agreement for a request, if any -- including a
  /// declined one if no newer proposal has been made yet, so the UI can
  /// tell "never proposed" apart from "was declined."
  Future<Agreement?> fetchAgreementForRequest(String requestId) async {
    final row = await _client
        .from('agreement')
        .select()
        .eq('request_id', requestId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return Agreement.fromJson(row);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/features/collaboration/agreement_repository.dart
git commit -m "feat: add AgreementRepository"
```

---

### Task 4: agreement_providers.dart

**Files:**
- Create: `app/lib/features/collaboration/agreement_providers.dart`

**Interfaces:**
- Consumes: `AgreementRepository` (Task 3); `authStateProvider` (`app/lib/features/auth/auth_providers.dart`, same as every other feature's own `currentNegotiatorIdProvider` copy).
- Produces: `agreementRepositoryProvider`, `currentNegotiatorIdProvider` (this feature's own copy), `agreementForRequestProvider = FutureProvider.autoDispose.family<Agreement?, String>` -- used by Task 5's dialog and Task 6's `_AgreementSection`.

- [ ] **Step 1: Write the providers**

```dart
// app/lib/features/collaboration/agreement_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import 'agreement_repository.dart';
import 'models/agreement.dart';

final agreementRepositoryProvider = Provider<AgreementRepository>((ref) {
  return AgreementRepository(Supabase.instance.client);
});

/// Same session-state read as the copies in listing_providers.dart,
/// requirement_providers.dart, matching_providers.dart,
/// cobroke_request_providers.dart, and message_providers.dart --
/// duplicated here rather than imported from a sibling feature, same
/// established reasoning as those files.
final currentNegotiatorIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.session?.user.id;
});

/// The current agreement for one cobroke_request, if any. The
/// .autoDispose HERE IS REQUIRED, not the default -- in the Riverpod
/// version this project is pinned to (2.6.1), `.family` alone does NOT
/// default to autoDispose (that's a Riverpod 3.x behavior, confirmed the
/// hard way during Messaging's final review -- see
/// message_providers.dart's messagesStreamProvider comment). Without it,
/// a stale fetch for a previously-viewed row would never be discarded.
final agreementForRequestProvider = FutureProvider.autoDispose.family<Agreement?, String>((ref, requestId) {
  return ref.watch(agreementRepositoryProvider).fetchAgreementForRequest(requestId);
});
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/features/collaboration/agreement_providers.dart
git commit -m "feat: add agreement Riverpod providers"
```

---

### Task 5: ProposeAgreementDialog + l10n keys

**Files:**
- Create: `app/lib/features/collaboration/propose_agreement_dialog.dart`
- Modify: `app/assets/translations/en.json`, `app/assets/translations/ms.json` (add new keys, see Step 1)

**Interfaces:**
- Consumes: `agreementRepositoryProvider`, `agreementForRequestProvider` (Task 4).
- Produces: `ProposeAgreementDialog({required String requestId, required String initiatorId})` -- used by Task 6's `_AgreementSection`, opened via `showDialog`.

This is the first `showDialog`/`AlertDialog` anywhere in this codebase -- no existing in-repo pattern to match, so this follows Flutter's own idiomatic `AlertDialog` + `Form` + `GlobalKey<FormState>` shape.

- [ ] **Step 1: Add l10n keys**

In `app/assets/translations/en.json`, find the line `"cobroke_request_chat_button": "Chat"` (the last key in the file) and add a comma after it, then add these new keys immediately after:

```json
  "agreement_propose_title": "Propose Agreement",
  "agreement_propose_button": "Propose Agreement",
  "agreement_split_initiator_label": "Your share (%)",
  "agreement_split_counterparty_label": "Counterparty's share (%)",
  "agreement_terms_label": "Terms (optional)",
  "agreement_split_invalid": "Enter a percentage between 0 and 100",
  "agreement_split_sum_error": "Shares must add up to 100",
  "agreement_submit": "Submit",
  "agreement_cancel": "Cancel",
  "agreement_accept": "Accept",
  "agreement_decline": "Decline",
  "agreement_waiting_response": "Waiting for response",
  "agreement_accepted_on": "Accepted on"
```

In `app/assets/translations/ms.json`, same position (after `"cobroke_request_chat_button": "Sembang"`), add:

```json
  "agreement_propose_title": "Cadang Perjanjian",
  "agreement_propose_button": "Cadang Perjanjian",
  "agreement_split_initiator_label": "Bahagian anda (%)",
  "agreement_split_counterparty_label": "Bahagian pihak satu lagi (%)",
  "agreement_terms_label": "Terma (pilihan)",
  "agreement_split_invalid": "Masukkan peratusan antara 0 dan 100",
  "agreement_split_sum_error": "Bahagian mesti berjumlah 100",
  "agreement_submit": "Hantar",
  "agreement_cancel": "Batal",
  "agreement_accept": "Terima",
  "agreement_decline": "Tolak",
  "agreement_waiting_response": "Menunggu respons",
  "agreement_accepted_on": "Diterima pada"
```

- [ ] **Step 2: Write the dialog**

```dart
// app/lib/features/collaboration/propose_agreement_dialog.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agreement_providers.dart';

class ProposeAgreementDialog extends ConsumerStatefulWidget {
  const ProposeAgreementDialog({super.key, required this.requestId, required this.initiatorId});

  final String requestId;
  final String initiatorId;

  @override
  ConsumerState<ProposeAgreementDialog> createState() => _ProposeAgreementDialogState();
}

class _ProposeAgreementDialogState extends ConsumerState<ProposeAgreementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _initiatorController = TextEditingController();
  final _counterpartyController = TextEditingController();
  final _termsController = TextEditingController();
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _initiatorController.dispose();
    _counterpartyController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  String? _percentageValidator(String? value) {
    final parsed = double.tryParse(value ?? '');
    if (parsed == null || parsed <= 0 || parsed >= 100) {
      return 'agreement_split_invalid'.tr();
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final splitInitiator = double.parse(_initiatorController.text);
    final splitCounterparty = double.parse(_counterpartyController.text);
    // Compare as integer cents, never as a raw double `==` check --
    // floating-point arithmetic can make an exact-100 sum fail an exact
    // equality comparison even when both inputs are individually valid
    // (e.g. 33.33 + 66.67 is not guaranteed to equal exactly 100.0 in
    // double precision).
    final sumInCents = (splitInitiator * 100).round() + (splitCounterparty * 100).round();
    if (sumInCents != 10000) {
      setState(() => _submitError = 'agreement_split_sum_error'.tr());
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref.read(agreementRepositoryProvider).createAgreement(
            requestId: widget.requestId,
            initiatorId: widget.initiatorId,
            splitInitiator: splitInitiator,
            splitCounterparty: splitCounterparty,
            terms: _termsController.text.trim().isEmpty ? null : _termsController.text.trim(),
          );
      ref.invalidate(agreementForRequestProvider(widget.requestId));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitError = 'listing_error_generic'.tr();
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('agreement_propose_title'.tr()),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _initiatorController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'agreement_split_initiator_label'.tr()),
              validator: _percentageValidator,
            ),
            TextFormField(
              controller: _counterpartyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'agreement_split_counterparty_label'.tr()),
              validator: _percentageValidator,
            ),
            TextFormField(
              controller: _termsController,
              decoration: InputDecoration(labelText: 'agreement_terms_label'.tr()),
              maxLines: 3,
            ),
            if (_submitError != null) ...[
              const SizedBox(height: 8),
              Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('agreement_cancel'.tr()),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: Text('agreement_submit'.tr()),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Run flutter analyze**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter analyze`
Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/collaboration/propose_agreement_dialog.dart app/assets/translations/en.json app/assets/translations/ms.json
git commit -m "feat: add ProposeAgreementDialog and agreement l10n keys"
```

---

### Task 6: Wire _AgreementSection into MyRequestsScreen + widget tests

**Files:**
- Modify: `app/lib/features/collaboration/my_requests_screen.dart`
- Modify: `app/test/features/collaboration/my_requests_screen_test.dart`

**Interfaces:**
- Consumes: `ProposeAgreementDialog` (Task 5); `agreementForRequestProvider`, `agreementRepositoryProvider` (Task 4); `Agreement` (Task 2); existing `_RequestList`/`CobrokeRequestCandidate` shapes (unchanged).
- Produces: nothing new consumed by later tasks -- this is the last task.

- [ ] **Step 1: Add imports to my_requests_screen.dart**

In `app/lib/features/collaboration/my_requests_screen.dart`, add these three imports alphabetically with the existing `collaboration/` imports (after `import 'cobroke_request_providers.dart';`, before `import 'models/cobroke_request_candidate.dart';`):

```dart
import 'agreement_providers.dart';
import 'models/agreement.dart';
import 'propose_agreement_dialog.dart';
```

- [ ] **Step 2: Add the _AgreementSection widget**

Currently the last block inside `_RequestList`'s `Card` > `Padding` > `Column` `children` is:

```dart
                      if (candidate.request.status == 'accepted') ...[
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => context.push('/messages/${candidate.request.requestId}'),
                          child: Text('cobroke_request_chat_button'.tr()),
                        ),
                      ],
```

Change it to append `_AgreementSection` inside the SAME `if` block, right after the Chat button:

```dart
                      if (candidate.request.status == 'accepted') ...[
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => context.push('/messages/${candidate.request.requestId}'),
                          child: Text('cobroke_request_chat_button'.tr()),
                        ),
                        const SizedBox(height: 8),
                        _AgreementSection(
                          requestId: candidate.request.requestId,
                          currentNegotiatorId: currentNegotiatorId,
                        ),
                      ],
```

Then add this new private widget at the end of the file, after the closing brace of the `_RequestList` class:

```dart
class _AgreementSection extends ConsumerWidget {
  const _AgreementSection({required this.requestId, required this.currentNegotiatorId});

  final String requestId;
  final String? currentNegotiatorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (currentNegotiatorId == null) return const SizedBox.shrink();
    final agreementAsync = ref.watch(agreementForRequestProvider(requestId));

    return agreementAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (agreement) {
        if (agreement == null || agreement.status == 'declined') {
          return OutlinedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ProposeAgreementDialog(
                requestId: requestId,
                initiatorId: currentNegotiatorId!,
              ),
            ),
            child: Text('agreement_propose_button'.tr()),
          );
        }

        final splitText =
            '${agreement.splitInitiator.toStringAsFixed(0)}% / ${agreement.splitCounterparty.toStringAsFixed(0)}%';
        final isRecipient = agreement.initiatorId != currentNegotiatorId;

        if (agreement.status == 'pending' && isRecipient) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(splitText),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        await ref.read(agreementRepositoryProvider).acceptAgreement(agreement.agreementId);
                        ref.invalidate(agreementForRequestProvider(requestId));
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('listing_error_generic'.tr())),
                          );
                        }
                      }
                    },
                    child: Text('agreement_accept'.tr()),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () async {
                      try {
                        await ref.read(agreementRepositoryProvider).declineAgreement(agreement.agreementId);
                        ref.invalidate(agreementForRequestProvider(requestId));
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('listing_error_generic'.tr())),
                          );
                        }
                      }
                    },
                    child: Text('agreement_decline'.tr()),
                  ),
                ],
              ),
            ],
          );
        }

        if (agreement.status == 'pending') {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(splitText),
              const SizedBox(height: 4),
              Text('agreement_waiting_response'.tr()),
            ],
          );
        }

        // status == 'accepted'
        final acceptedAt = agreement.acceptedAt!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(splitText),
            const SizedBox(height: 4),
            Text('${'agreement_accepted_on'.tr()} ${acceptedAt.day}/${acceptedAt.month}/${acceptedAt.year}'),
          ],
        );
      },
    );
  }
}
```

Note: `_AgreementSection` does NOT reuse `_RequestList`'s private `_statusLabel` method (that method is scoped to `cobroke_request`'s own pending/accepted/declined vocabulary, and is a private instance method on a different class -- it isn't callable from here anyway). The 4 branches above render their own explicit copy instead of a shared status-label switch, since each branch's content differs by more than just a label (split display, action buttons, or a date all vary together).

- [ ] **Step 3: Extend the test file's `_wrap` helper**

In `app/test/features/collaboration/my_requests_screen_test.dart`, add these imports after the existing `cobroke_request_providers.dart` import:

```dart
import 'package:renly/features/collaboration/agreement_providers.dart';
import 'package:renly/features/collaboration/models/agreement.dart';
```

Change the `_wrap` function signature and body from:

```dart
Widget _wrap(GoRouter router, {List<CobrokeRequestCandidate>? received, List<CobrokeRequestCandidate>? sent}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      receivedRequestsProvider.overrideWith((ref) async => received ?? _fixtureReceived),
      sentRequestsProvider.overrideWith((ref) async => sent ?? const []),
    ],
```

to:

```dart
Widget _wrap(
  GoRouter router, {
  List<CobrokeRequestCandidate>? received,
  List<CobrokeRequestCandidate>? sent,
  String? agreementRequestId,
  Agreement? agreement,
}) {
  return ProviderScope(
    overrides: [
      currentNegotiatorIdProvider.overrideWithValue('n-1'),
      receivedRequestsProvider.overrideWith((ref) async => received ?? _fixtureReceived),
      sentRequestsProvider.overrideWith((ref) async => sent ?? const []),
      if (agreementRequestId != null)
        agreementForRequestProvider(agreementRequestId).overrideWith((ref) async => agreement),
    ],
```

The rest of `_wrap` (the `EasyLocalization`/`MaterialApp.router` body) is unchanged. Existing tests that don't pass `agreementRequestId` get no override for `_AgreementSection`'s provider -- since `Supabase.instance` is never initialized in this test file, that provider throws synchronously, Riverpod catches it into an `AsyncError`, and `_AgreementSection`'s `error: (error, stack) => const SizedBox.shrink()` branch renders nothing. This is safe and intentional (same pattern already accepted for `ChatScreen`'s `_senderNameProvider` in the Messaging milestone) -- it means the 4 existing tests in this file need NO changes themselves.

- [ ] **Step 4: Add the new tests**

Add these 5 tests inside `main()`, after the existing 4 tests:

```dart
  testWidgets('shows Propose Agreement button when accepted request has no agreement', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-4',
          matchId: 'm-4',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, received: accepted, agreementRequestId: 'req-4'));
    await tester.pumpAndSettle();

    expect(find.text('Propose Agreement'), findsOneWidget);
  });

  testWidgets('shows split and Accept/Decline when viewer is the agreement recipient', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-5',
          matchId: 'm-5',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final agreement = Agreement(
      agreementId: 'agr-1',
      requestId: 'req-5',
      initiatorId: 'n-2',
      splitInitiator: 60,
      splitCounterparty: 40,
      status: 'pending',
      createdAt: DateTime(2026, 8, 24),
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, received: accepted, agreementRequestId: 'req-5', agreement: agreement));
    await tester.pumpAndSettle();

    expect(find.text('60% / 40%'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
  });

  testWidgets('shows waiting-for-response label when viewer is the agreement initiator', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-6',
          matchId: 'm-6',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final agreement = Agreement(
      agreementId: 'agr-2',
      requestId: 'req-6',
      initiatorId: 'n-1',
      splitInitiator: 50,
      splitCounterparty: 50,
      status: 'pending',
      createdAt: DateTime(2026, 8, 24),
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, received: accepted, agreementRequestId: 'req-6', agreement: agreement));
    await tester.pumpAndSettle();

    expect(find.text('Waiting for response'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
  });

  testWidgets('shows final split and accepted date when agreement is accepted', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-7',
          matchId: 'm-7',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final agreement = Agreement(
      agreementId: 'agr-3',
      requestId: 'req-7',
      initiatorId: 'n-2',
      splitInitiator: 70,
      splitCounterparty: 30,
      status: 'accepted',
      acceptedAt: DateTime(2026, 8, 25),
      createdAt: DateTime(2026, 8, 24),
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, received: accepted, agreementRequestId: 'req-7', agreement: agreement));
    await tester.pumpAndSettle();

    expect(find.text('70% / 30%'), findsOneWidget);
    expect(find.text('Accepted on 25/8/2026'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
  });

  testWidgets('propose dialog validates that shares sum to 100', (tester) async {
    final accepted = [
      CobrokeRequestCandidate(
        request: CobrokeRequest(
          requestId: 'req-8',
          matchId: 'm-8',
          initiatorId: 'n-2',
          status: 'accepted',
          createdAt: DateTime(2026, 8, 24),
        ),
        match: _matchCandidate,
      ),
    ];
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const MyRequestsScreen()),
    ]);

    await tester.pumpWidget(_wrap(router, received: accepted, agreementRequestId: 'req-8'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Propose Agreement'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '60');
    await tester.enterText(find.byType(TextFormField).at(1), '30');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Shares must add up to 100'), findsOneWidget);
  });
```

- [ ] **Step 5: Run the tests**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test test/features/collaboration/my_requests_screen_test.dart`
Expected: PASS (9 tests -- the 4 existing plus 5 new).

- [ ] **Step 6: Run the full suite to confirm zero regression**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter test`
Expected: all tests pass (prior suite count 136 + this plan's new tests: Task 2's 2 + Task 6's 5 = 7 new tests = 143 total).

- [ ] **Step 7: Run flutter analyze**

Run: `cd "/Users/unxpected/Desktop/Semester 4/Mobile Application/RENLY/app" && flutter analyze`
Expected: no issues.

- [ ] **Step 8: Commit**

```bash
git add app/lib/features/collaboration/my_requests_screen.dart app/test/features/collaboration/my_requests_screen_test.dart
git commit -m "feat: wire agreement propose/accept/decline UI into MyRequestsScreen"
```
