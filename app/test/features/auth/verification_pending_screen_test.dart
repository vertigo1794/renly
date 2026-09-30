import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:renly/core/theme/app_theme.dart';
import 'package:renly/core/widgets/brutalist_button.dart';
import 'package:renly/features/auth/auth_providers.dart';
import 'package:renly/features/auth/auth_repository.dart';
import 'package:renly/features/auth/models/negotiator.dart';
import 'package:renly/features/auth/verification_pending_screen.dart';

/// _handleBackHome's fetchOwnNegotiator (and, on a rejected status, its
/// signOut) call through this instead of a real Supabase-backed
/// AuthRepository, which has no live backend to reach in a widget test.
/// `implements` (not `extends`) AuthRepository deliberately -- extending it
/// runs the REAL constructor, which unconditionally subscribes to
/// `_client.auth.onAuthStateChange` for biometric-token upkeep and needs a
/// real, network-capable SupabaseClient to attach to. Constructing one
/// (even pointed at a fake URL) was observed to hang the entire test run
/// (a real GoTrue client spins up its own JSON isolate + auth machinery on
/// construction, regardless of `autoRefreshToken`). `implements` sidesteps
/// all of that: it only has to satisfy AuthRepository's public method
/// signatures, never runs its constructor, and needs no SupabaseClient at
/// all. Every method _handleBackHome doesn't call throws if reached, so a
/// test exercising a new code path here is a clear signal to extend this.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._negotiator);

  final Negotiator? _negotiator;

  @override
  Future<Negotiator?> fetchOwnNegotiator(String negotiatorId) async => _negotiator;

  @override
  Future<void> signOut() async {}

  @override
  Future<User> signUp({required String email, required String password}) => throw UnimplementedError();
  @override
  Future<void> insertNegotiator({
    required String negotiatorId,
    required String fullName,
    required String icNumber,
    required String phoneNumber,
  }) =>
      throw UnimplementedError();
  @override
  Future<String> findOrCreateAgency(String firmName) => throw UnimplementedError();
  @override
  Future<String> uploadTagPhoto({required String negotiatorId, required Uint8List bytes}) =>
      throw UnimplementedError();
  @override
  Future<void> completeProfessionalDetails({
    required String negotiatorId,
    required String renNumber,
    required String agencyId,
  }) =>
      throw UnimplementedError();
  @override
  Future<void> insertVerificationRecord({required String negotiatorId, required String tagPhotoUrl}) =>
      throw UnimplementedError();
  @override
  Future<AuthResponse> signIn({required String email, required String password}) => throw UnimplementedError();
  @override
  Future<void> resetPasswordForEmail(String email) => throw UnimplementedError();
  @override
  Future<void> updatePassword(String newPassword) => throw UnimplementedError();
  @override
  Future<bool> isBiometricAvailable() => throw UnimplementedError();
  @override
  Future<void> enableBiometricLogin({required String localizedReason}) => throw UnimplementedError();
  @override
  Future<void> disableBiometricLogin() => throw UnimplementedError();
  @override
  Future<bool> hasBiometricLoginEnabled() => throw UnimplementedError();
  @override
  Future<AuthResponse> signInWithBiometrics({required String localizedReason}) => throw UnimplementedError();
}

Widget _wrap(GoRouter router, {required Negotiator? negotiator}) {
  return ProviderScope(
    overrides: [
      // _handleBackHome reads authStateProvider (not Supabase.instance
      // directly) to get the current user id -- override it here with a
      // fake signed-in session so the "approved -> navigates home" path
      // and the "rejected -> signs out" path can both be exercised
      // without a live Supabase instance.
      authStateProvider.overrideWith(
        (ref) => Stream.value(
          AuthState(
            AuthChangeEvent.signedIn,
            Session(
              accessToken: 'fake-access-token',
              tokenType: 'bearer',
              user: User(
                id: 'fake-user-id',
                appMetadata: const {},
                userMetadata: const {},
                aud: 'authenticated',
                createdAt: DateTime.now().toIso8601String(),
              ),
            ),
          ),
        ),
      ),
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository(negotiator)),
    ],
    child: EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ms')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: Builder(
        builder: (context) => Consumer(
          // Pre-warms authStateProvider (a StreamProvider) by giving it a
          // watcher during the initial build -- _handleBackHome only ever
          // `ref.read`s it synchronously inside the button's tap callback,
          // which is too late: a StreamProvider (even one overridden with
          // `Stream.value(...)`) starts in AsyncLoading until its stream
          // actually delivers a first event through a real microtask, and
          // nothing else in this screen's own tree watches it to kick that
          // off earlier. Without this, the read inside the tap handler
          // sees `valueOrNull == null`, userId resolves null, and
          // _handleBackHome takes the "no negotiator" branch instead of
          // the one this test means to exercise.
          builder: (context, ref, _) {
            ref.watch(authStateProvider);
            return MaterialApp.router(
              theme: AppTheme.light,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              routerConfig: router,
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await EasyLocalization.ensureInitialized();
  });

  // Same rootBundle-cache-vs-FakeAsync-zone issue documented across every
  // other auth screen test in this project -- clear before every test.
  setUp(() => rootBundle.clear());

  testWidgets('renders localized verification pending copy and status badge', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const VerificationPendingScreen()),
      GoRoute(path: '/home', builder: (context, state) => const Placeholder()),
    ]);

    // pumpAndSettle() would hang forever here: the hourglass's
    // AnimationController repeats infinitely (real motion, not a
    // one-shot), so Flutter never sees "no more frames scheduled". A
    // couple of fixed pumps is enough to let go_router build its first
    // real route and settle the animation into steady state.
    await tester.pumpWidget(_wrap(router, negotiator: null));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Your Account is Being Verified'), findsOneWidget);
    expect(
      find.text('The REN verification process takes 24-48 hours. We will notify you as soon as your profile is approved.'),
      findsOneWidget,
    );
    expect(find.text('IN PROGRESS'), findsOneWidget);
    expect(find.text('renly'), findsOneWidget);
  });

  testWidgets('tapping Back to Home navigates to /home once approved', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, state) => const VerificationPendingScreen()),
      GoRoute(path: '/home', builder: (context, state) => const Text('home-screen')),
    ]);

    await tester.pumpWidget(
      _wrap(
        router,
        negotiator: const Negotiator(negotiatorId: 'fake-user-id', fullName: 'Test User', verificationStatus: 'approved'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(BrutalistButton, 'Back to Home'));
    // _handleBackHome awaits fetchOwnNegotiator (a real Future, even
    // though the fake resolves instantly) before navigating.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('home-screen'), findsOneWidget);
  });
}
