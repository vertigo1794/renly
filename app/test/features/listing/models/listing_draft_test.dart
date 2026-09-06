import 'package:flutter_test/flutter_test.dart';
import 'package:renly/features/listing/models/listing_draft.dart';

void main() {
  test('toJson/fromJson round-trips every field', () {
    final draft = ListingDraft(
      draftId: 'd-1',
      savedAt: DateTime(2026, 9, 6, 12, 0, 0),
      title: 'Test Condo',
      description: 'A nice place',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: 'Petaling Jaya',
      price: '450000',
      bedrooms: '3',
      bathrooms: '2',
      sqft: '1450',
      commissionSplitPercent: '1.5',
      titleVerified: true,
      exclusiveMandate: false,
    );

    final roundTripped = ListingDraft.fromJson(draft.toJson());

    expect(roundTripped.draftId, draft.draftId);
    expect(roundTripped.savedAt, draft.savedAt);
    expect(roundTripped.title, draft.title);
    expect(roundTripped.description, draft.description);
    expect(roundTripped.propertyType, draft.propertyType);
    expect(roundTripped.transactionType, draft.transactionType);
    expect(roundTripped.state, draft.state);
    expect(roundTripped.area, draft.area);
    expect(roundTripped.price, draft.price);
    expect(roundTripped.bedrooms, draft.bedrooms);
    expect(roundTripped.bathrooms, draft.bathrooms);
    expect(roundTripped.sqft, draft.sqft);
    expect(roundTripped.commissionSplitPercent, draft.commissionSplitPercent);
    expect(roundTripped.titleVerified, draft.titleVerified);
    expect(roundTripped.exclusiveMandate, draft.exclusiveMandate);
  });

  test('nullable fields round-trip as null when omitted', () {
    final draft = ListingDraft(
      draftId: 'd-2',
      savedAt: DateTime(2026, 9, 6),
      title: 'Bare Draft',
      description: '',
      propertyType: 'apartment',
      transactionType: 'sale',
      state: 'Selangor',
      area: '',
      price: null,
      bedrooms: null,
      bathrooms: null,
      sqft: null,
      commissionSplitPercent: null,
      titleVerified: false,
      exclusiveMandate: false,
    );

    final roundTripped = ListingDraft.fromJson(draft.toJson());

    expect(roundTripped.price, isNull);
    expect(roundTripped.bedrooms, isNull);
    expect(roundTripped.bathrooms, isNull);
    expect(roundTripped.sqft, isNull);
    expect(roundTripped.commissionSplitPercent, isNull);
  });
}
