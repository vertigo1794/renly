import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/offline_banner.dart';
import 'features/auth/password_recovery_state.dart';
import 'features/notifications/deep_link.dart';
import 'features/notifications/foreground_suppression.dart';
import 'features/notifications/notification_providers.dart';
import 'features/profile/profile_providers.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Safety net for uncaught errors anywhere else in the app (Crashlytics is
  // additionally wired onto these same handlers below, once Firebase is up).
  FlutterError.onError = FlutterError.presentError;
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true;
  };
  // Keeps the native splash (white bg + square logo tile, see
  // pubspec.yaml's flutter_native_splash config) on screen through
  // Flutter's engine boot and this async init, so there is no unbranded
  // gap before SplashScreen's own first frame is ready underneath it.
  // Removed below, a fixed 600ms after runApp() -- deliberately separate
  // from SplashScreen's own on-screen duration (see splash_screen.dart),
  // since these two delays now control two visually distinct screens
  // (native splash, then the Flutter-side lime splash) rather than one
  // combined handoff.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Unlike Stripe/Firebase below, these three are core to the app actually
  // working (locale, .env, Supabase) -- a failure here must show a real
  // error screen instead of a crash/blank screen, since
  // SupabaseConfig.fromEnvironment already throws a helpful descriptive
  // message for the most common cause (missing .env keys).
  try {
    await EasyLocalization.ensureInitialized();
    await dotenv.load(fileName: '.env');

    final supabaseConfig = SupabaseConfig.fromEnvironment(dotenv.env);
    await Supabase.initialize(
      url: supabaseConfig.url,
      publishableKey: supabaseConfig.anonKey,
    );
  } catch (e) {
    FlutterNativeSplash.remove();
    runApp(_BootstrapErrorApp(message: e.toString()));
    return;
  }

  // Subscribed immediately after initialize() -- before runApp(), before any
  // Riverpod provider exists -- so it is live in time to catch a
  // passwordRecovery event fired by a cold-start "reset password" deep
  // link. appRouterProvider's redirect callback reads this flag on every
  // navigation attempt to lock the app to '/reset-password' until a new
  // password is saved (see PasswordRecoveryState's doc comment).
  Supabase.instance.client.auth.onAuthStateChange.listen((state) {
    if (state.event == AuthChangeEvent.passwordRecovery) {
      PasswordRecoveryState.isRecovering = true;
    }
  });

  // Optional: every other screen in this app works with zero Stripe
  // configuration. Only the Subscription screen's upgrade flow needs
  // this -- a missing key must never crash app startup for everyone
  // else.
  final stripePublishableKey = dotenv.env['STRIPE_PUBLISHABLE_KEY'];
  if (stripePublishableKey != null && stripePublishableKey.isNotEmpty) {
    Stripe.publishableKey = stripePublishableKey;
    await Stripe.instance.applySettings();
  }

  // Optional, same non-crashing guard as Stripe above: a fresh clone with
  // no google-services.json yet must still be able to flutter run for
  // every other feature. Firebase.initializeApp() throws if the config
  // file is missing/malformed -- catch and skip rather than crash.
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
    // Crashlytics needs Crashlytics enabled for this Firebase project in the
    // Firebase console (one-time toggle) for reports to actually appear
    // there -- wiring it here only prepares the app to send them. Wrapped
    // inside this same try so a Crashlytics setup failure never crashes the
    // app either, consistent with Firebase itself being best-effort above.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    // No google-services.json yet, or Firebase project not configured --
    // push notifications are simply unavailable this run.
    debugPrint('Firebase.initializeApp() failed: $e');
  }

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ms')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: ProviderScope(child: RenlyApp(firebaseReady: firebaseReady)),
    ),
  );

  // runApp() doesn't block on the first frame actually painting, but by
  // 600ms the engine has always long since rendered it -- removing any
  // earlier risks a brief blank frame between the native splash going
  // away and SplashScreen's own Scaffold appearing underneath it.
  await Future.delayed(const Duration(milliseconds: 600));
  FlutterNativeSplash.remove();
}

/// Shown instead of the real app when a required bootstrap step (locale,
/// .env, Supabase) throws -- a plain error screen rather than a crash or an
/// unexplained blank screen. See the try/catch around these calls in main().
class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Renly failed to start',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RenlyApp extends ConsumerStatefulWidget {
  const RenlyApp({required this.firebaseReady, super.key});

  final bool firebaseReady;

  @override
  ConsumerState<RenlyApp> createState() => _RenlyAppState();
}

class _RenlyAppState extends ConsumerState<RenlyApp> with WidgetsBindingObserver {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  Timer? _presenceHeartbeat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startHeartbeat();
    if (!widget.firebaseReady) return;
    _registerToken();
    Supabase.instance.client.auth.onAuthStateChange.listen((_) => _registerToken());
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => _registerToken());
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((message) => _navigateFromMessage(message.data));
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _navigateFromMessage(message.data);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceHeartbeat?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startHeartbeat();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _presenceHeartbeat?.cancel();
      _presenceHeartbeat = null;
    }
  }

  /// Sends an immediate heartbeat and (re)starts the periodic timer. Called
  /// unconditionally from initState -- WidgetsBinding consumes the
  /// platform's initial `resumed` state before initState registers this
  /// observer, and Flutter dedups a same-state transition, so relying on
  /// didChangeAppLifecycleState alone would mean a negotiator who opens the
  /// app and never backgrounds it sends zero heartbeats all session.
  void _startHeartbeat() {
    _sendHeartbeat();
    _presenceHeartbeat ??= Timer.periodic(const Duration(seconds: 60), (_) => _sendHeartbeat());
  }

  /// Best-effort, same reasoning as every other push/notification call site
  /// in this file -- a heartbeat failing (offline, backend hiccup) must
  /// never surface an error or block the app. No-ops when logged out.
  Future<void> _sendHeartbeat() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    try {
      await ref.read(profileRepositoryProvider).updateLastSeen(negotiatorId: session.user.id);
    } catch (_) {
      // Swallowed -- see doc comment above.
    }
  }

  Future<void> _registerToken() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await ref.read(fcmTokenRepositoryProvider).registerToken(
            negotiatorId: session.user.id,
            token: token,
          );
    } catch (_) {
      // Best-effort, same as every push-send call site in this module --
      // e.g. no Google Play Services on this device/emulator. Push
      // notifications are simply unavailable, never a crash.
    }
  }

  Map<String, String> _stringData(Map<String, dynamic> data) =>
      data.map((key, value) => MapEntry(key, value.toString()));

  void _navigateFromMessage(Map<String, dynamic> data) {
    final stringData = _stringData(data);
    final category = stringData['category'] ?? '';
    final route = deepLinkRouteFor(category, stringData);
    // go vs push is not interchangeable now that a StatefulShellRoute owns
    // the 4 bottom-nav branches: `go` to a FLAT route (e.g. '/messages/:id')
    // replaces the whole stack, tearing the shell down and stranding the
    // negotiator on a chat screen with no bottom nav and nothing to pop back
    // to. Push keeps the shell (and its per-branch back-stacks) underneath.
    // A shell-branch path is the opposite case -- it must be switched to,
    // never stacked, or a second MainShell mounts on top of the live one.
    final router = ref.read(appRouterProvider);
    if (isShellBranchRoute(route)) {
      router.go(route);
    } else {
      router.push(route);
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final stringData = _stringData(message.data);
    final category = stringData['category'] ?? '';
    final currentLocation = currentLocationObserver.currentLocation.value;
    if (shouldSuppressForegroundBanner(category: category, currentRouteLocation: currentLocation, data: stringData)) {
      return;
    }
    final notification = message.notification;
    if (notification == null) return;
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('${notification.title}: ${notification.body}'),
        action: SnackBarAction(
          label: 'push_banner_view'.tr(),
          onPressed: () => _navigateFromMessage(message.data),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'renly',
      theme: AppTheme.light,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      routerConfig: router,
      builder: (context, child) => OfflineBanner(child: child ?? const SizedBox.shrink()),
    );
  }
}
