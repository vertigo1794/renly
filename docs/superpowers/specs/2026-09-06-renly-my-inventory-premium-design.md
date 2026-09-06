# renly — My Inventory Premium Restyle Design

## Goal

Restyle `MyInventoryScreen` (currently a bare AppBar+SegmentedButton+ListTile screen) from Stitch's "Renly - My Inventory (Premium Co-Broking Management)" mockup, building every interactive element with real function per direct request — no decorative dead buttons, no fabricated numbers. This is the largest restyle this session: it adds a real Drafts system, a real Bump-to-top feature, a real Share action, a real Edit-listing flow, and three new negotiator-set listing fields (title-verified self-attestation, exclusive-mandate self-attestation, commission-split percentage).

## Source of truth

Stitch mockup: branded header (same RStarBadge+wordmark+REN-pill+bell pattern already established for Dashboard/Marketplace/Messages), "My Inventory" title + "N Units" black pill + "Post Property" pill button, subtitle, a live ticker ("N Co-Broke Inquiries waiting for your verification" + "Review →"), search bar, 4 filter tabs (Active/Co-Broke in Review/Closed·Sold/Drafts), premium hard-shadow cards (photo banner with status badge + days-on-market + a self-attestation tag, guide price + property-type tag, location, specs row, a co-broke insight pill, action buttons: Edit / Bump Listing / Share / more-menu), and a dashed "Post New Listing" card at the end of the grid.

**Visual language**: this app's Urby/neo-brutalist system, matching this mockup's own `border-2 border-black` + hard-offset-shadow card style — the same adaptation approach already used for Dashboard/Marketplace/Messages this session, not re-litigated here. Header row reused verbatim from those screens (`RStarBadge(size: 28)` + wordmark + REN pill + bell).

## New backend fields (migration `0020_listing_premium_fields.sql`)

Three new nullable/defaulted columns on `listing`:

- `bumped_at timestamptz` (nullable) — set by the new "Bump Listing" action. Kept **separate** from `created_at` deliberately: `created_at` is the listing's true age (backs "N Days on Market" on this screen and the Dashboard's "Nm/h/d ago" Recent Listings timestamp) and must never change after creation. `bumped_at` is a distinct "last resurfaced" signal. `ListingRepository.fetchMarketplaceListings`/`fetchOwnListings` both change their ordering to `order('bumped_at', ascending: false, nullsFirst: false).order('created_at', ascending: false)` (a listing that was never bumped sorts by its real creation time; a bumped listing jumps to the top by its bump time) — Postgrest supports multiple `.order()` calls composing into a single multi-key ORDER BY.
- `commission_split_percent numeric(5,2)` (nullable, `check (commission_split_percent > 0 and commission_split_percent <= 100)` when set) — the percentage of the eventual transaction commission this listing's owner is offering to whichever co-broker brings a qualifying buyer. Standalone from `Agreement.splitInitiator/splitCounterparty`, which only exists once a specific co-broke request is formalized into a deal — this field is the owner's own upfront, self-set advertised split, shown on the card only when non-null (never a fabricated fallback).
- `title_verified boolean not null default false`, `exclusive_mandate boolean not null default false` — both **self-attested by the listing's own owner**, not third-party-verified. The mockup's "Verified Title" copy could misleadingly imply an external legal check; this design keeps the boolean (real, owner-set, real function) but reframes the in-app copy/caption honestly: the badge still reads "Verified Title" (matching the mockup visually) but the toggle in the posting form is captioned "I confirm I hold clear, verified title to this property" / "I confirm this is an exclusive mandate" — an explicit self-declaration, not a claim of third-party verification. This is the same honesty-first principle already applied throughout this session (never fabricate a claim the data doesn't support) applied to copy framing rather than to omission.

```sql
-- supabase/migrations/0020_listing_premium_fields.sql
-- Run this once in the Supabase project's SQL Editor, AFTER 0001-0019.
--
-- Three new negotiator-set fields for the My Inventory Premium Restyle:
-- bumped_at (a real "resurface to top of feed" signal, kept separate from
-- created_at so a bump never falsifies a listing's true age elsewhere in
-- the app -- e.g. Dashboard's Recent Listings relative timestamp),
-- commission_split_percent (the owner's own advertised co-broke split,
-- standalone from Agreement's post-deal formal split), and
-- title_verified/exclusive_mandate (self-attested by the owner -- NOT
-- third-party verified; the in-app posting form's own caption makes this
-- explicit, this migration only adds the storage for it).
alter table listing add column if not exists bumped_at timestamptz;
alter table listing add column if not exists commission_split_percent numeric(5,2)
  check (commission_split_percent is null or (commission_split_percent > 0 and commission_split_percent <= 100));
alter table listing add column if not exists title_verified boolean not null default false;
alter table listing add column if not exists exclusive_mandate boolean not null default false;
```

## Model & repository changes

`Listing` gains 4 new fields: `bumpedAt` (`DateTime?`), `commissionSplitPercent` (`double?`), `titleVerified` (`bool`, default `false` parsed from `json['title_verified'] as bool? ?? false`), `exclusiveMandate` (`bool`, same pattern). `createListing(...)` gains optional `commissionSplitPercent`, `titleVerified`, `exclusiveMandate` params (all optional, default to null/false — posting a listing without opting into any of these stays exactly as simple as today).

New `ListingRepository` methods:
```dart
Future<void> bumpListing(String listingId) {
  return _client.from('listing').update({'bumped_at': DateTime.now().toIso8601String()}).eq('listing_id', listingId);
}

Future<void> updateListingDetails({
  required String listingId,
  required String title,
  required String description,
  required String propertyType,
  required String transactionType,
  required String state,
  required String area,
  required double price,
  int? bedrooms,
  int? bathrooms,
  double? commissionSplitPercent,
  required bool titleVerified,
  required bool exclusiveMandate,
}) {
  return _client.from('listing').update({
    'title': title,
    'description': description,
    'property_type': propertyType,
    'transaction_type': transactionType,
    'state': state,
    'area': area,
    'price': price,
    'bedrooms': bedrooms,
    'bathrooms': bathrooms,
    'commission_split_percent': commissionSplitPercent,
    'title_verified': titleVerified,
    'exclusive_mandate': exclusiveMandate,
  }).eq('listing_id', listingId);
}
```
Neither method touches `negotiator_id`, `status`, `photo_urls`, `created_at`, or `bumped_at` (the latter three have their own dedicated update paths: photos via `updateListingPhotos`, status via `updateListingStatus`, bump via `bumpListing`).

`fetchMarketplaceListings`/`fetchOwnListings` both add the `bumped_at`-then-`created_at` ordering described above.

## PostListingScreen: dual create/edit mode

`PostListingScreen` gains an optional constructor param `final Listing? existingListing`. When non-null:
- All controllers/dropdowns are pre-filled from `existingListing`'s current values in `initState`.
- Two new form fields render (both optional): a `TextFormField` for `commission_split_percent` (numeric, nullable — empty stays null) and two `SwitchListTile`s for `title_verified`/`exclusive_mandate`, each with the honest self-attestation caption from the migration section above. These two new fields render in BOTH create and edit mode (a negotiator can declare them at posting time, not only when editing later).
- The submit button's label changes to `listing_edit_save`.tr() (new key) and its handler calls `updateListingDetails(...)` instead of `createListing(...)` + skips the free-tier active-listing-cap check entirely (editing an existing listing never adds to the count).
- Photo management (`_pickPhotos`/photo grid) is unaffected — editing an existing listing's photos is out of scope for this pass (the mockup's own Edit button doesn't surface a photo-management flow either); the existing photos stay as-is unless the negotiator uses the same "Add Photo" flow already on the form, appending to (not replacing) the existing `photo_urls`.
- Route: `GoRoute(path: '/property/:listingId/edit', builder: (context, state) => ... loads listingDetailProvider(listingId) then renders PostListingScreen(existingListing: listing))` — a small loading wrapper widget resolves the listing before handing it to `PostListingScreen`, mirroring `ChatScreen`'s own `:requestId`-param-then-fetch pattern.

## Drafts (local-only, real function)

No backend concept — implemented as device-local persistence, same precedent as `LoginScreen`'s `has_dismissed_biometric_prompt` and `ConversationListScreen`'s archived-conversations `StateNotifier`.

- A `_ListingDraft` model (title, description, propertyType, transactionType, state, area, price, bedrooms, bathrooms, commissionSplitPercent, titleVerified, exclusiveMandate, plus a generated `draftId` and `savedAt` — photos are NOT persisted in a draft, since `XFile`/picked-image bytes aren't meaningfully serializable to SharedPreferences; a resumed draft starts with an empty photo grid, which is an accepted, disclosed limitation, not a silent gap).
- `PostListingScreen` gains a "Save as Draft" action (a secondary button next to "Post Now", enabled once the title field is non-empty) that serializes current form state to JSON and appends it to a `SharedPreferences` string list under key `listing_drafts` (each entry itself a JSON string), then `context.go('/my-inventory')`.
- A new `_draftsProvider` (`StateNotifierProvider<_DraftsNotifier, List<_ListingDraft>>`) loads/persists this list, with `remove(draftId)` and `add(draft)` methods.
- My Inventory's Drafts tab lists these draft summaries (title + price preview + "Saved Nm/h/d ago" via the same relative-time formatter pattern already used in `ConversationListScreen`). Tapping a draft pushes `PostListingScreen` with a new `initialDraft` param (pre-fills the form from the draft instead of from a real `Listing`, and removes the draft from local storage once the form actually submits successfully — an abandoned draft simply stays in the list until the negotiator resumes or explicitly deletes it via a swipe/trailing delete icon).
- A draft never becomes a real `Listing` row until "Post Now" is tapped from the resumed form — it carries zero server-side existence at any point, consistent with "no half-validated row belongs in the `listing` table."

## Tab semantics (mutually exclusive, sums to the real total)

- **Active**: `status == 'active'` AND this listing has zero PENDING received co-broke requests against it.
- **Co-Broke in Review**: `status == 'active'` AND this listing has ≥1 PENDING received co-broke request against it (cross-referencing `receivedRequestsProvider`'s candidates by `candidate.match.listing.listingId == listing.listingId` — no new backend query, client-side join of two already-fetched lists, same pattern as the Dashboard's Radar filter).
- **Closed / Sold**: `status == 'sold' || status == 'withdrawn'` — preserves this project's own established principle (this file's current doc comment) that withdrawn listings must stay visible to their owner, just grouped under the mockup's "Closed / Sold" label rather than hidden.
- **Drafts**: the local `_draftsProvider` list (not `Listing` rows at all).
- The "N Units" header pill counts real `Listing` rows only (`myListingsProvider` length) — drafts are explicitly NOT counted as units, since they aren't listings yet.

## Live ticker

"N Co-Broke Inquiries waiting for your verification" — real count: `receivedRequestsProvider`'s candidates filtered to `status == 'pending'` AND `candidate.match.listing.negotiatorId == currentNegotiatorId` (pending requests specifically targeting one of the negotiator's own listings, a subset of the same provider the Dashboard already reads). "Review →" pushes the existing `/my-requests` route (`MyRequestsScreen`, already built).

## Per-card content (real data, reusing existing providers/patterns)

- Photo banner: `ListingPhoto` (existing widget) or a neutral placeholder.
- Status badge: "Co-Broking Active" (has ≥1 accepted received request, no agreement yet) / "In Deal Review" (has ≥1 accepted received request AND an `Agreement` with `status == 'pending'` via `agreementForRequestProvider`) — same two-state mapping already built for the Messages restyle's Active-Deals/Inquiries split, reused here per-listing instead of per-conversation. No badge when the listing has neither.
- "N Days on Market": `DateTime.now().difference(listing.createdAt).inDays` (always `createdAt`, never `bumpedAt`).
- Self-attestation tag ("Verified Title" / "Exclusive Mandate"): rendered only when `listing.titleVerified`/`listing.exclusiveMandate` is `true` — real, owner-declared data, never shown for a listing where the owner didn't opt in.
- Guide price, property-type tag, location, bed/bath specs row: existing `Listing` fields (`ListingFormatting.formatPrice`), sqft omitted (no such field, consistent with every other screen this session).
- Co-Broke insight pill: real pending-inquiry count for this specific listing (same cross-reference as the tab split above) OR, when this listing has a real `MatchCandidate` in `myMatchesProvider` (i.e. some other negotiator's requirement matches it), "Buyer Match: Agent {name}" + the real match score — whichever is more relevant is decided per-listing: prefer the co-broke-inquiry pill when `pendingCount > 0` (an actual person has already reached out), otherwise show the top match if one exists, otherwise omit the pill entirely (never a fabricated "0 inquiries" pill).
- Commission split shown only when `listing.commissionSplitPercent != null` ("{value}% Split").
- Action row: **Edit** (pushes `/property/{id}/edit`) · **Bump Listing** (calls `bumpListing`, then invalidates `myListingsProvider`/`marketplaceListingsProvider` so the reordering is immediately visible, shows a confirmation snackbar) · **Share** (`share_plus`, real listing text) · **⋮ more-menu** (`PopupMenuButton` reusing `property_detail_screen.dart`'s exact Mark Sold/Withdraw/Reactivate gating: only the actions valid from the listing's current status appear, `atCap` disables Reactivate the same way).
- Trailing "Post New Listing" dashed card: unchanged action, pushes `/post-listing`.

## Error handling

Every async cross-reference (`receivedRequestsProvider`, `myMatchesProvider`, `agreementForRequestProvider`) uses `.maybeWhen(data: ..., orElse: () => <safe empty/null default>)` — a loading/error state for any of these hides that specific piece of UI (a badge, a pill, a tab count) rather than blocking the whole screen or showing a placeholder value, consistent with every prior restyle this session.

## Testing approach

Following this project's established convention: Supabase-boundary calls (`bumpListing`, `updateListingDetails`, the ordering change) are not unit-tested, manually verified instead. Pure logic gets real tests:
- A pure `_ListingDraft.toJson`/`fromJson` round-trip test.
- A pure tab-partition function (`_partitionListings(listings, receivedRequests) -> ({active, coBrokeReview, closedSold})`) extracted the same way `mergeAcceptedConversations` was extracted for Messages — testable without widgets.
- Widget tests for `MyInventoryScreen`: provider overrides per tab (empty/populated), the "N Units" pill count, the ticker's real count and hidden-when-zero behavior (constraint: never a placeholder "0" — actually the ticker here differs from Dashboard's Market Pulse: the mockup always shows the ticker row even when N=0 conceptually is fine here since "0 Co-Broke Inquiries waiting" is still a true, real statement, not a fabricated one — unlike Dashboard's Market Pulse which fully hides at zero. Keep the ticker always visible with the real count, including "0").
- `PostListingScreen`'s dual-mode: a test confirming edit-mode pre-fills fields from `existingListing` and calls `updateListingDetails` not `createListing` on submit.

## Explicitly deferred / out of scope

- Editing photos on an existing listing (append-only via the existing picker, no replace/reorder/delete-existing-photo flow).
- A "delete draft" confirmation dialog (a plain delete icon is enough for a local-only, low-stakes list).
- Any change to `Agreement`/the formal deal-split flow — `commissionSplitPercent` is a separate, standalone field.
- Third-party title/mandate verification of any kind — both remain honest self-attestations, never implied as externally checked.
- Real-time updates to the ticker/tab counts (pull-to-refresh only, matching every other screen this session).
