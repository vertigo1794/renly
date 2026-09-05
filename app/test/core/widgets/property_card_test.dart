import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/core/widgets/property_card.dart';
import 'package:renly/features/listing/models/listing.dart';

const _listing = Listing(
  listingId: 'l-1',
  negotiatorId: 'n-1',
  title: 'Modern Villa',
  description: 'd',
  propertyType: 'house',
  transactionType: 'sale',
  state: 'Selangor',
  area: '124 Maple St, Downtown',
  price: 2450000,
  bedrooms: 4,
  bathrooms: 3,
  photoUrls: [],
  status: 'active',
);

void main() {
  testWidgets('renders listing price, area, and bed/bath counts', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PropertyCard(listing: _listing, onTap: () {}),
          ),
        ),
      ),
    );

    expect(find.textContaining('2,450,000'), findsOneWidget);
    expect(find.text('124 Maple St, Downtown'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('tapping the card calls onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PropertyCard(listing: _listing, onTap: () => tapped = true),
                  ),
        ),
      ),
    );

    await tester.tap(find.byType(PropertyCard));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
