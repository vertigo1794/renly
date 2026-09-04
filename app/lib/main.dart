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

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // Keeps the native splash (logo + tagline baked in, see pubspec.yaml's
  // flutter_native_splash config) on screen through engine boot, the async
  // init below, and the fixed 2s wait -- there is no separate Flutter-side
  // splash widget/route to hand off to. The native splash IS the splash;
  // by the time runApp() below ever paints a frame, it's already onboarding.
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

  // Fixed minimum splash duration, on top of whatever the init above took
  // -- matches the previous Flutter-side SplashScreen widget's own
  // Future.delayed pattern, just moved here now that the native splash
  // covers this whole window by itself.
  await Future.delayed(const Duration(seconds: 2));
  FlutterNativeSplash.remove();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ms')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: ProviderScope(child: RenlyApp(firebaseReady: firebaseReady)),
    ),
  );
}

class RenlyApp extends ConsumerStatefulWidget {
  const RenlyApp({required this.firebaseReady, super.key});

  final bool firebaseReady;

  @override
  ConsumerState<RenlyApp> createState() => _RenlyAppState();
}

class _RenlyAppState extends ConsumerState<RenlyApp> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
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
    ref.read(appRouterProvider).go(route);
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
