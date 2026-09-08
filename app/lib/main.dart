import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/notifications/deep_link.dart';
import 'features/notifications/foreground_suppression.dart';
import 'features/notifications/notification_providers.dart';
import 'features/profile/profile_providers.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
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
  await EasyLocalization.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final supabaseConfig = SupabaseConfig.fromEnvironment(dotenv.env);
  await Supabase.initialize(
    url: supabaseConfig.url,
    publishableKey: supabaseConfig.anonKey,
  );

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
    );
  }
}
