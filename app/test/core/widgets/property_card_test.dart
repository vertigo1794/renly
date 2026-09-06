import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/core/widgets/property_card.dart';
import 'package:renly/features/listing/models/listing.dart';

final _listing = Listing(
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
  createdAt: DateTime(2024, 1, 1),
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

  testWidgets('does not render trailing content when omitted', (tester) async {
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

    // Regression guard: existing callers (e.g. marketplace_screen.dart) don't
    // pass `trailing`, so nothing extra should render beyond the card's
    // existing content.
    expect(find.text('18m ago'), findsNothing);
  });

  testWidgets('renders trailing widget when provided', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PropertyCard(
              listing: _listing,
              onTap: () {},
              trailing: const Text('18m ago'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('18m ago'), findsOneWidget);
  });
}
