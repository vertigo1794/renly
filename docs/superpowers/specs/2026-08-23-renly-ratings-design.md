# renly — Ratings/Reviews Design

Status: approved (2026-08-23). Tenth milestone, built on Profile Management (`docs/superpowers/specs/2026-08-23-renly-profile-design.md`), merged and live. This closes the "Trust Score" gap left explicitly open by Profile Management's own scope decision.

## Goal

Let two negotiators who completed an accepted co-broking agreement rate and optionally review each other — once each — feeding a public average "Trust Score" shown on the rated negotiator's `ProfileScreen`, with a full reviews list screen for reading individual reviews.

## Source of truth

**None from the proposal.** This feature has no basis in the original proposal's ERD or module descriptions — it originates entirely from the Stitch UI mockup (`stitch_renly_property_agent_network/profile_settings/code.html`), which shows a static "4.9" Trust Score stat card with no explanation of where the number comes from. When this gap was surfaced during Profile Management's brainstorm, the user explicitly chose to build the full rating system rather than skip it or leave a placeholder. Every design decision below was therefore resolved directly with the user in this brainstorm, not derived from proposal text.

**Resolved with the user, six decisions:**
1. **Trigger:** rating opens once an `agreement` reaches `status = 'accepted'`. Either party to that agreement may rate the other, once per agreement.
2. **Shape:** a 1-5 star rating, plus optional free-text review.
3. **Aggregate:** computed live (fetch all of a negotiator's received `stars` values, average client-side) — not cached/triggered on `negotiator`, matching the existing Active Listings/Deals Closed count pattern of live queries over stored aggregates.
4. **Visibility:** public — any authenticated user can read any rating/review (same trust-signal reasoning as agency/owner-name lookups already being public in this app).
5. **Mutability:** editable by the original rater for 24 hours after submission, then permanent. This deliberately reopens the UPDATE+WITH CHECK risk class that has produced this project's most consequential bugs twice already (Co-Broke Request's Critical missing-WITH-CHECK bug, and a near-miss grant regression in Profile Management) — the RLS section below is designed with that history explicit, not discovered again in review.
6. **Entry point:** a "Rate" button added to the same `MyRequestsScreen` accepted-agreement row that already hosts Chat/Propose-Agreement/Accept-Decline — not a new standalone flow.

**Also resolved:** this milestone includes a full reviews-list screen (not just the aggregate number), since review text is public and there needs to be somewhere to read it.

## Data model

```sql
create table rating (
  rating_id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references agreement(agreement_id) on delete cascade,
  rater_id uuid not null references negotiator(negotiator_id) on delete cascade,
  rated_id uuid not null references negotiator(negotiator_id) on delete cascade,
  stars int not null check (stars between 1 and 5),
  review_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  check (rater_id != rated_id)
);

-- At most one rating per rater per agreement, for the life of the
-- agreement -- not a point-in-time cap like cobroke_request/agreement's
-- own partial-unique-index pattern, because editing (within 24h) already
-- covers "I made a mistake," so there's no re-rate-after-decline case to
-- accommodate here.
create unique index rating_one_per_rater_per_agreement on rating(agreement_id, rater_id);
```

`updated_at` is set only by a trigger (mirroring `agreement.accepted_at`'s pattern), never the client:

```sql
create function rating_set_updated_at() returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

create trigger rating_set_updated_at_trigger
  before update on rating for each row
  execute function rating_set_updated_at();
```

## RLS

A `rater_id`/`rated_id` pair must both be genuine parties to the same accepted agreement, and distinct from each other (no self-rating). Rather than repeat the `agreement -> cobroke_request -> match -> listing/requirement` join chain three times inline (as `agreement`'s own RLS does twice per policy), this milestone extracts it into a reusable helper function — checking "is this ONE negotiator a party to this ONE agreement" is simpler to get right than trying to pair two negotiators against two sides inline, and since every `cobroke_request` has exactly two parties, confirming both `rater_id` and `rated_id` are independently party members (and distinct) is sufficient to prove they're the two opposite sides — no explicit pairing logic needed:

```sql
create function is_agreement_party(p_agreement_id uuid, p_negotiator_id uuid) returns boolean
language sql stable as $$
  select exists (
    select 1 from agreement a
    join cobroke_request cr on cr.request_id = a.request_id
    join match m on m.match_id = cr.match_id
    where a.agreement_id = p_agreement_id
      and (
        cr.initiator_id = p_negotiator_id
        or exists (select 1 from listing l where l.listing_id = m.listing_id and l.negotiator_id = p_negotiator_id)
        or exists (select 1 from requirement r where r.requirement_id = m.requirement_id and r.negotiator_id = p_negotiator_id)
      )
  );
$$;

alter table rating enable row level security;

-- Public: any authenticated user can read any rating/review.
create policy rating_select on rating for select
  to authenticated using (true);

-- Insert: sender must be themselves, target must be someone else, the
-- agreement must be accepted, and BOTH must genuinely be parties to it.
create policy rating_insert on rating for insert
  to authenticated with check (
    rater_id = auth.uid()
    and rated_id != rater_id
    and exists (select 1 from agreement a where a.agreement_id = rating.agreement_id and a.status = 'accepted')
    and is_agreement_party(rating.agreement_id, rater_id)
    and is_agreement_party(rating.agreement_id, rated_id)
  );

-- Update: only the original rater, only within 24 hours of creation.
-- USING and WITH CHECK are IDENTICAL here -- unlike cobroke_request's
-- Critical bug (where USING encoded a "before" status the update was
-- specifically designed to move away from), the 24-hour window condition
-- doesn't change between the old and new row states, so there's no
-- transition to gate asymmetrically. rater_id/created_at are excluded
-- from the UPDATE grant entirely, so neither can be touched to extend
-- the window or reassign the rating.
create policy rating_update_by_rater on rating for update
  to authenticated using (
    rater_id = auth.uid()
    and now() - created_at < interval '24 hours'
  )
  with check (
    rater_id = auth.uid()
    and now() - created_at < interval '24 hours'
  );

revoke insert on rating from authenticated;
grant insert (agreement_id, rater_id, rated_id, stars, review_text) on rating to authenticated;

revoke update on rating from authenticated;
grant update (stars, review_text) on rating to authenticated;
```

No delete policy — a rating past its 24-hour edit window is permanent, matching every other immutable-after-a-point row in this codebase.

## Repository

- `createRating({required agreementId, required raterId, required ratedId, required stars, String? reviewText})`
- `updateRating({required ratingId, required stars, String? reviewText})` — only reachable within the 24h window; a rejected UPDATE (window expired) must be detected the same way `AgreementRepository`'s final-review fix does — chain `.select()` after the update and throw if the result is empty, since PostgREST returns 204 on a zero-row RLS-rejected UPDATE just like it does elsewhere in this codebase.
- `fetchMyRatingForAgreement({required agreementId, required raterId})` — used by `MyRequestsScreen` to decide whether to show "Rate" or "Edit rating" on a given accepted-agreement row.
- `fetchRatingsForNegotiator(String negotiatorId)` — all ratings where `rated_id = negotiatorId`, used by both the average-computation (Profile screen) and the full list (Reviews screen). One query serves both call sites; the average is computed client-side over the returned `stars` values, not a second query.

## Screens

1. **`MyRequestsScreen`'s accepted-agreement row** gains a "Rate" button (next to the existing Agreement section), visible when `agreement.status == 'accepted'`. If the current viewer hasn't rated that agreement yet, tapping opens a `RateDialog` (star picker + optional review text, following `ProposeAgreementDialog`'s established dialog pattern). If they already have (within the edit window), the button instead reads "Edit rating" and opens the same dialog pre-filled, calling `updateRating` instead of `createRating`. Past the 24-hour window, the button disappears entirely (no dead edit affordance).
2. **`ProfileScreen` gains a THIRD stat card** (Trust Score) — no such card exists yet; `ProfileScreen` currently has exactly two (Active Listings, Deals Closed), built on the shared `_StatCard` widget. The new card shows the live average of the viewer's own received ratings (or a placeholder like "No ratings yet" if none exist) and is tappable, navigating to the new Reviews screen. `_StatCard`'s `value` field is currently typed `int` (the two existing cards pass whole counts) — it needs widening to accept a `String` display value instead, so the caller formats the average (e.g. `"4.9"`) or the empty-state text before passing it in; the two existing call sites change from `value: counts.$1` to `value: '${counts.$1}'` (and `$2` likewise) to keep compiling against the widened signature.
3. **New `ReviewsScreen`** (route `/reviews`) — lists every rating the current negotiator has received, newest first, each showing the rater's name (resolved the same way `ListingOwner`/counterparty names are resolved elsewhere), star count, and review text if present.

## File structure

```
lib/features/ratings/
  rating_repository.dart      # createRating, updateRating, fetchMyRatingForAgreement, fetchRatingsForNegotiator
  rating_providers.dart
  rate_dialog.dart             # RateDialog(agreementId, raterId, ratedId, existingRating)
  reviews_screen.dart
  models/
    rating.dart                # ratingId, agreementId, raterId, ratedId, stars, reviewText, createdAt, updatedAt
```

## Router

New route, requiring a session: `/reviews` → `ReviewsScreen`. No new route for the Rate dialog (it's a `showDialog`, same as `ProposeAgreementDialog`).

## Manual setup

`supabase/migrations/0011_rating.sql` — single file, same hardened-from-the-start re-runnable pattern as every prior migration. No storage bucket, no Auth-dashboard changes, no Realtime.

## Testing approach

Same boundary as every prior milestone: `RatingRepository` untested directly. `Rating.fromJson` gets a real unit test. `RateDialog`, the `MyRequestsScreen` row addition, `ProfileScreen`'s stat card update, and `ReviewsScreen` all get widget tests via provider override, following established conventions.

**Given this milestone's history-informed risk (the UPDATE+WITH CHECK class has broken twice already):** the final whole-branch review must specifically trace the `rating_update_by_rater` policy's USING/WITH CHECK symmetry and the `is_agreement_party` helper's self-rating and cross-agreement-party exclusion logic by hand — this is flagged here explicitly so it isn't treated as routine boilerplate during review.

## Explicitly deferred / out of scope for this milestone

- Viewing another negotiator's reviews from their public profile (this milestone's `ReviewsScreen` only shows the CURRENT viewer's own received reviews — a "view negotiator X's public profile" screen doesn't exist yet anywhere in this app).
- Moderation/reporting of abusive reviews.
- Rating deletion (only edit-within-24h, no retraction).
- Any notification on receiving a new rating.
- Weighting the average by recency or agreement value.
