# renly — Co-Broke Request Design

Status: approved (2026-08-23). Sixth milestone, built on Matching Engine (`docs/superpowers/specs/2026-08-22-renly-matching-design.md`), merged and live. First of three deliberately-split sub-milestones covering the proposal's "Collaboration Module" — this doc covers `cobroke_request` only. Messaging (`message`, Supabase Realtime) and digital agreements (`agreement`) are each their own future design+plan+implementation cycle, not part of this scope.

## Goal

Turn a computed `match` into a real negotiator-to-negotiator interaction: either party to a match can send a formal co-broke request, the other party accepts or declines, and both sides can see the state of every request they've sent or received.

## Source of truth

From `Fakhrullah_Renly_Project_Proposal.pdf` Table 6.1 (ERD), read directly from the PDF, not a secondhand summary:

> `cobroke_request`: `request_id` (PK), `match_id` (FK), `initiator_id` (FK), `status`, `created_at`. Relationship: 1 match : at most 1 request.

Proposal §5.3 (workflow, step 7): "Co-broking request: a negotiator initiates a formal request to the counterparty, which may be accepted or declined."

The ERD's "1 match : at most 1 request" is ambiguous about whether that's a lifetime cap or a point-in-time cap — the proposal text doesn't resolve it. **Resolved with the user: point-in-time.** A match may have many `cobroke_request` rows over its lifetime (one per attempt), but at most one may be `pending` at a time — a declined request doesn't permanently close off that match. This departs from a literal one-row-per-match reading of the ERD; the design doc it belongs to notes it as a deliberate interpretation.

## Data model

```sql
create table cobroke_request (
  request_id uuid primary key default gen_random_uuid(),
  match_id uuid not null references match(match_id) on delete cascade,
  initiator_id uuid not null references negotiator(negotiator_id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now()
);

-- At most one PENDING request per match at a time. Does not block a new
-- request after a prior one on the same match was declined -- that row's
-- status is 'declined', not 'pending', so it doesn't collide with this
-- index. This is what makes "re-request after decline" possible.
create unique index cobroke_request_one_pending_per_match
  on cobroke_request(match_id) where status = 'pending';
```

Either party to the match may initiate — the listing owner or the requirement owner, symmetric with how both already see the same match in their own Matches screens. No `withdraw`/`cancel` status: an initiator cannot retract a pending request in this milestone (deferred — see below).

## RLS

```sql
alter table cobroke_request enable row level security;

-- Both parties to the underlying match can see a request: the initiator,
-- or whichever of the match's listing/requirement they own.
create policy cobroke_request_select on cobroke_request for select
  to authenticated using (
    initiator_id = auth.uid()
    or exists (
      select 1 from match m
      join listing l on l.listing_id = m.listing_id
      where m.match_id = cobroke_request.match_id and l.negotiator_id = auth.uid()
    )
    or exists (
      select 1 from match m
      join requirement r on r.requirement_id = m.requirement_id
      where m.match_id = cobroke_request.match_id and r.negotiator_id = auth.uid()
    )
  );

-- Insert: must be the initiator, and must actually be a party to the match
-- (own the listing or the requirement side) -- not an uninvolved third party
-- inserting a request on someone else's match.
create policy cobroke_request_insert on cobroke_request for insert
  to authenticated with check (
    initiator_id = auth.uid()
    and (
      exists (
        select 1 from match m
        join listing l on l.listing_id = m.listing_id
        where m.match_id = cobroke_request.match_id and l.negotiator_id = auth.uid()
      )
      or exists (
        select 1 from match m
        join requirement r on r.requirement_id = m.requirement_id
        where m.match_id = cobroke_request.match_id and r.negotiator_id = auth.uid()
      )
    )
  );

-- Update: ONLY the receiving party (the other side of the match, never the
-- initiator) may change status, and only while it's still pending. The
-- initiator cannot accept/decline their own request.
create policy cobroke_request_update_by_recipient on cobroke_request for update
  to authenticated using (
    status = 'pending'
    and initiator_id != auth.uid()
    and (
      exists (
        select 1 from match m
        join listing l on l.listing_id = m.listing_id
        where m.match_id = cobroke_request.match_id and l.negotiator_id = auth.uid()
      )
      or exists (
        select 1 from match m
        join requirement r on r.requirement_id = m.requirement_id
        where m.match_id = cobroke_request.match_id and r.negotiator_id = auth.uid()
      )
    )
  );

revoke insert on cobroke_request from authenticated;
grant insert (match_id, initiator_id) on cobroke_request to authenticated;

revoke update on cobroke_request from authenticated;
grant update (status) on cobroke_request to authenticated;
```

Same join-through-`match`-to-`listing`/`requirement` ownership pattern the `match` table's own RLS already established (Matching Engine milestone) — reused here, not reinvented. Column-scoped grants follow the established pattern: INSERT only ever writes `match_id`/`initiator_id` (status stays at its `pending` default); UPDATE only ever writes `status` (nothing else about a request is ever edited).

## Screens

1. **`MyRequestsScreen`** (new) — two tabs, **Received** and **Sent**. Received shows requests where the viewer is NOT the initiator (i.e. requests to act on), each row showing the counterparty's info (via the same `MatchCandidate`-style owner lookup already established), the underlying match's score, and Accept/Decline buttons when `status == 'pending'` (a read-only status badge once resolved). Sent shows requests the viewer initiated, status badge only, no actions.
2. **"Request Co-Broke" button** — added to each match row in the three existing screens from Matching Engine: `MatchesForListingScreen`, `MatchesForRequirementScreen`, `MyMatchesScreen`. Each row already corresponds to exactly one `match_id`, so there's no ambiguity about which match a request is for — this keeps the change scoped to adding one button per row rather than touching `PropertyDetailScreen`/`RequirementDetailScreen` (which would need to resolve "which of the viewer's several possible matches does this button mean" if placed there instead).

`HomePlaceholderScreen` gains one more navigation link (My Requests).

## File structure

```
lib/
  features/
    collaboration/
      cobroke_request_repository.dart   # sole Supabase touchpoint: create/fetch/accept/decline
      cobroke_request_providers.dart    # Riverpod: repositoryProvider, receivedRequestsProvider, sentRequestsProvider
      my_requests_screen.dart
      models/
        cobroke_request.dart            # raw row: requestId, matchId, initiatorId, status, createdAt
        cobroke_request_candidate.dart  # repository-composed view: request + the underlying MatchCandidate
```

`CobrokeRequestCandidate` wraps a `CobrokeRequest` plus the `MatchCandidate` it's for (reusing the `MatchCandidate` model from the matching feature directly — same reuse precedent as Requirement reusing `ListingOwner`, and Matching reusing `ListingRepository`/`RequirementRepository`) — screens render the same score/area/owner details `MyMatchesScreen` already knows how to show, without inventing a second representation of "what this match looks like."

New top-level feature folder `collaboration/` (not nested under `matching/`) — this is proposal's own module boundary (§6.1 module 6), and it will grow two more sibling files (`message`, `agreement`) in the next two sub-milestones.

## Router

New routes, requiring a session: `/my-requests` → `MyRequestsScreen`. No detail route — Accept/Decline happen inline in the list, same as Listing/Requirement's status actions happening inline rather than on a separate screen.

## Manual setup

`supabase/migrations/0007_cobroke_request.sql` — single file, same hardened-from-the-start re-runnable pattern as `0006_matching.sql`. No storage bucket, no Auth-dashboard changes.

## Testing approach

Same boundary as every prior milestone: `CobrokeRequestRepository` untested directly (Supabase-calling code). `CobrokeRequest.fromJson` gets a real unit test. `MyRequestsScreen` gets widget tests following the established pattern (`rootBundle.clear()`, `pumpAndSettle` discipline, hardcoded literal test strings). The three match-card edits (adding the "Request Co-Broke" button) get their existing test suites re-run to confirm zero regression, same discipline as the Matching Engine's `SignedPhoto`/compute-on-create hook tasks.

## Explicitly deferred / out of scope for this milestone

- Withdrawing/cancelling a pending request as the initiator (no `withdraw` status, no UI for it).
- Messaging (`message` table, Supabase Realtime) — next sub-milestone, needs an accepted request to exist first.
- Digital agreements (`agreement` table, mutual acceptance, commission split) — third sub-milestone, needs messaging's negotiation step to exist first per the proposal's own workflow ordering.
- Push notification on a new/accepted/declined request (same FCM-not-wired-up reason Matching Engine deferred it).
- Any UI badge/counter for unread or pending request counts.
