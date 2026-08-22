# renly — Agreement Design

Status: approved (2026-08-23). Eighth milestone, built on Messaging (`docs/superpowers/specs/2026-08-22-renly-messaging-design.md`), merged and live. Third and FINAL of three deliberately-split sub-milestones covering the proposal's "Collaboration Module" — closes out the module started with Co-Broke Request.

## Goal

Let two negotiators with an ACCEPTED co-broke request formally propose, accept, or decline a digital co-broking agreement recording the commission split — the final step of the proposal's own workflow before the transaction proceeds outside the app.

## Source of truth

From `Fakhrullah_Renly_Project_Proposal.pdf` Table 6.1 (ERD), read directly from the PDF:

> `agreement`: `agreement_id` (PK), `request_id` (FK), `split_initiator`, `split_counterparty`, `terms`, `accepted_at`. Relationship: 1 request : at most 1 agreement.

Proposal §5.3 (workflow, steps 9-10): "9. Agreement: both parties accept the digital co-broking agreement, which is recorded immutably with a timestamp. 10. Completion: the transaction proceeds outside the application, and the deal record is closed."

**Resolved with the user, four decisions:**
1. **Accept mechanics:** the ERD's single `accepted_at` column reflects a single decisive accept action, not two independent confirmations. One party proposes (as `initiator_id`); the other party's single accept action sets `accepted_at`. This mirrors `cobroke_request`'s own initiator-proposes/recipient-responds pattern, already established twice in this codebase.
2. **Reject flow:** unlike the literal ERD (no status column), this milestone adds a `status` column (`pending`/`accepted`/`declined`), matching `cobroke_request`'s own shape. A declined agreement can be followed by a new proposal on the same request — the same point-in-time (not lifetime) interpretation already resolved for `cobroke_request`'s own "1 match : at most 1 request" ERD wording.
3. **Split semantics:** `split_initiator`/`split_counterparty` are commission percentages, required to sum to exactly 100.
4. **Completion scope:** strictly per the proposal — accepting an agreement only records it. No automatic status change to `listing`/`requirement`/`cobroke_request` follows from it. The deal's real-world completion (step 10) is explicitly outside this app's scope; the owner updates listing/requirement status manually afterward, same as every prior milestone.

Technically simpler than Messaging: no Supabase Realtime, no new external tech risk — a plain fetch-and-refresh screen, matching every module before Messaging.

## Data model

```sql
create table agreement (
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

-- At most one OPEN (pending or accepted) agreement per request at a time --
-- same point-in-time pattern as cobroke_request_one_open_per_match. A
-- declined agreement's status is neither 'pending' nor 'accepted', so it
-- doesn't collide with this index -- re-proposing after a decline is
-- possible, deliberately.
create unique index agreement_one_open_per_request
  on agreement(request_id) where status in ('pending', 'accepted');

-- accepted_at is set by the database, never supplied by the client --
-- "recorded immutably with a timestamp" per the proposal means the
-- timestamp itself must be trustworthy, not just the row's existence.
create function agreement_set_accepted_at() returns trigger as $$
begin
  if new.status = 'accepted' and old.status != 'accepted' then
    new.accepted_at := now();
  end if;
  return new;
end;
$$ language plpgsql;

create trigger agreement_set_accepted_at_trigger
  before update on agreement for each row
  execute function agreement_set_accepted_at();
```

No update/delete on `terms`/`split_initiator`/`split_counterparty` once created — an agreement's proposed terms are immutable; only `status` (and, via the trigger, `accepted_at`) ever changes after insert. Renegotiation happens by declining and creating a new agreement row, not by editing one in place.

## RLS

Same ownership-join pattern as `message`/`cobroke_request` — party membership resolved by joining `agreement` → `cobroke_request` → `match` → `listing`/`requirement`, gated on `cobroke_request.status = 'accepted'`:

```sql
alter table agreement enable row level security;

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

-- Only the RECIPIENT (never the agreement's own initiator) may accept or
-- decline, and only while it's still pending. Explicit WITH CHECK,
-- genuinely different from USING -- the lesson from cobroke_request's
-- Critical bug: a missing WITH CHECK defaults to the USING clause, which
-- requires 'pending', so every accept/decline (which moves status AWAY
-- from pending) would be silently rejected by Postgres.
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

`accepted_at` is never in either grant — only the trigger sets it, so no client write path can forge it.

## Data-fetching architecture

Two approaches considered:

- **Chosen: a separate per-row provider.** `agreementForRequestProvider = FutureProvider.family<Agreement?, String>(requestId)`, fetched only for rows `MyRequestsScreen` renders as `status == 'accepted'`. Mirrors the established per-row `_senderNameProvider` pattern from Messaging's `ChatScreen`. New files only (`agreement_repository.dart`, `agreement_providers.dart`) — `cobroke_request_repository.dart` and its providers, already shipped and reviewed across 3 prior milestones, are untouched.
- **Rejected: embed `agreement(*)` into `CobrokeRequestRepository`'s existing fetch queries.** Fewer round-trips, but edits already-reviewed code for a benefit that only applies to the subset of rows that are `accepted` — not worth the added regression surface on a file three milestones deep.

## Screens

No new screen or route. All UI lives inside `MyRequestsScreen`'s existing accepted-row `Card`, via a new small `ConsumerWidget` (`_AgreementSection`) added per row, watching `agreementForRequestProvider(requestId)`:

- **No agreement yet, or the existing one was declined:** a "Propose Agreement" button (both Received and Sent tabs, same `status == 'accepted'` gate as the existing Chat button — no `isReceived` restriction, since either party to the underlying request may propose). Tapping it opens `ProposeAgreementDialog` — two numeric percentage inputs (validated to sum to 100) plus an optional free-text terms field.
- **Status `pending`, viewer is the recipient** (`agreement.initiatorId != currentNegotiatorId`): shows the proposed split, the terms text if any was entered, and an Accept/Decline button pair, same interaction shape as `cobroke_request`'s own Accept/Decline.
- **Status `pending`, viewer is the initiator:** shows the proposed split and terms, read-only, with a "waiting for response" label — no action available.
- **Status `accepted`:** shows the final split, terms, and the accepted timestamp, read-only. No further action — this request's agreement is done.

The split percentages must render without lossy rounding — `numeric(5,2)` allows decimals (e.g. `55.5`/`44.5`), and truncating both to whole numbers can display a pair that doesn't sum to 100 (`56%`/`45%`). The terms field is shown in every non-propose state precisely because "recorded immutably with a timestamp" (the proposal's own wording) implies the recipient must be able to read what they're accepting before they accept it — collecting terms in the propose dialog but never displaying them anywhere would defeat that.

This is a direct continuation of the row-level accept/decline pattern already used for `cobroke_request` itself — one more layer nested inside the same card, not a new interaction paradigm.

## File structure

```
lib/features/collaboration/
  agreement_repository.dart      # sole Supabase touchpoint: createAgreement, acceptAgreement, declineAgreement, fetchAgreementForRequest
  agreement_providers.dart       # agreementRepositoryProvider, agreementForRequestProvider.family<Agreement?, String>
  propose_agreement_dialog.dart  # split-percentage + terms input form, shown via showDialog
  models/
    agreement.dart                # agreementId, requestId, initiatorId, splitInitiator, splitCounterparty, terms, status, acceptedAt, createdAt
```

## Router

No new routes. Everything happens inline on `/my-requests`.

## Manual setup

`supabase/migrations/0009_agreement.sql` — single file, same hardened-from-the-start re-runnable pattern (`create table if not exists`, `drop policy if exists`/`drop trigger if exists` before each create) as `0006`-`0008`. No storage bucket, no Auth-dashboard changes, no Realtime publication needed (this milestone is plain fetch/refresh, not live).

## Testing approach

Same boundary as every prior milestone: `AgreementRepository` untested directly (Supabase-calling code, established convention). `Agreement.fromJson` gets a real unit test. The new UI additions to `MyRequestsScreen` get widget tests via provider override (propose-dialog opens and validates sum-to-100; Accept/Decline visibility differs correctly between initiator and recipient views; accepted state renders read-only) — following the established `rootBundle.clear()`/`pumpAndSettle` pattern.

## Explicitly deferred / out of scope for this milestone

- Editing an agreement's terms/split in place once created (renegotiate via decline + new proposal instead).
- Automatic status changes to `listing`/`requirement`/`cobroke_request` upon agreement acceptance (deal completion is explicitly outside the app per the proposal's own step 10).
- PDF export or any document generation of the agreement.
- Push notification on propose/accept/decline (same FCM-not-wired-up reason every prior milestone deferred it).
- Any post-agreement analytics or reporting.
