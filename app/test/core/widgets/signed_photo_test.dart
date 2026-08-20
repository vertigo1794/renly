// app/test/core/widgets/signed_photo_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renly/core/widgets/signed_photo.dart';

/// Test harness that hosts a [SignedPhoto] and lets the test change the
/// `path` passed to it (or force a no-op rebuild) via [GlobalKey] access,
/// without ever remounting the [SignedPhoto] widget itself. This is what
/// lets the test exercise `didUpdateWidget`'s caching guard on the SAME
/// State object, rather than always re-triggering `initState`.
class _SignedPhotoHarness extends StatefulWidget {
  const _SignedPhotoHarness({super.key, required this.initialPath, required this.fetcher});

  final String initialPath;
  final Future<String> Function(String path) fetcher;

  @override
  State<_SignedPhotoHarness> createState() => _SignedPhotoHarnessState();
}

class _SignedPhotoHarnessState extends State<_SignedPhotoHarness> {
  late String path;

  @override
  void initState() {
    super.initState();
    path = widget.initialPath;
  }

  void setPath(String newPath) {
    setState(() {
      path = newPath;
    });
  }

  void rebuildOnly() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SignedPhoto(path: path, signedUrlFetcher: widget.fetcher);
  }
}

void main() {
  testWidgets('shows the placeholder container while the signed URL future is pending', (tester) async {
    final completer = Completer<String>();

    await tester.pumpWidget(
      MaterialApp(
        home: SignedPhoto(path: 'negotiator/req/1.jpg', signedUrlFetcher: (path) => completer.future),
      ),
    );

    // Do not settle: the future is still pending at this point.
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    final container = tester.widget<Container>(find.byType(Container));
    final context = tester.element(find.byType(SignedPhoto));
    expect(container.color, Theme.of(context).colorScheme.surfaceContainerHighest);

    // Let the pending future resolve so it doesn't leak across tests.
    completer.complete('https://example.test/negotiator/req/1.jpg');
    await tester.pumpAndSettle();
  });

  testWidgets('shows Image.network once the signed URL future resolves', (tester) async {
    Future<String> fetcher(String path) => Future.value('https://example.test/$path');

    await tester.pumpWidget(
      MaterialApp(
        home: SignedPhoto(path: 'negotiator/req/1.jpg', signedUrlFetcher: fetcher),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.url, 'https://example.test/negotiator/req/1.jpg');
  });

  testWidgets('rebuilding with the same path does not re-invoke signedUrlFetcher', (tester) async {
    var callCount = 0;
    Future<String> fetcher(String path) {
      callCount++;
      return Future.value('https://example.test/$path');
    }

    final key = GlobalKey<_SignedPhotoHarnessState>();

    await tester.pumpWidget(
      MaterialApp(
        home: _SignedPhotoHarness(key: key, initialPath: 'negotiator/req/1.jpg', fetcher: fetcher),
      ),
    );
    await tester.pumpAndSettle();
    expect(callCount, 1);

    // Rebuild the same State object (no path change) via setState -- this
    // must not re-request a signed URL.
    key.currentState!.rebuildOnly();
    await tester.pumpAndSettle();

    key.currentState!.setPath('negotiator/req/1.jpg');
    await tester.pumpAndSettle();

    expect(callCount, 1);
  });

  testWidgets('rebuilding with a different path DOES re-invoke signedUrlFetcher', (tester) async {
    var callCount = 0;
    Future<String> fetcher(String path) {
      callCount++;
      return Future.value('https://example.test/$path');
    }

    final key = GlobalKey<_SignedPhotoHarnessState>();

    await tester.pumpWidget(
      MaterialApp(
        home: _SignedPhotoHarness(key: key, initialPath: 'negotiator/req/1.jpg', fetcher: fetcher),
      ),
    );
    await tester.pumpAndSettle();
    expect(callCount, 1);

    key.currentState!.setPath('negotiator/req/2.jpg');
    await tester.pumpAndSettle();

    expect(callCount, 2);
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.url, 'https://example.test/negotiator/req/2.jpg');
  });
}
