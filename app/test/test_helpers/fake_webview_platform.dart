// test/test_helpers/fake_webview_platform.dart
//
// webview_flutter has no real platform implementation registered in the
// widget-test host process (no Android/iOS platform channel), so any test
// that pumps AssetWebViewScreen (or a screen that embeds it -- Privacy,
// Terms of Service, Commission Calculator) must first register this fake
// as `WebViewPlatform.instance`, or WebViewController's constructor throws
// `WebViewPlatform.instance != null`. Covers only the handful of methods
// AssetWebViewScreen actually calls (setJavaScriptMode,
// setNavigationDelegate/setOnNavigationRequest, loadFlutterAsset,
// widget.build) -- enough to let the widget tree build and render without
// error; it never actually loads or executes any HTML/CSS/JS, so it can't
// verify page content, only that the screen scaffolds correctly.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => FakePlatformWebViewController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => FakePlatformNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => FakePlatformWebViewWidget(params);
}

class FakePlatformWebViewController extends PlatformWebViewController {
  FakePlatformWebViewController(PlatformWebViewControllerCreationParams params) : super.implementation(params);

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async {}

  @override
  Future<void> loadFlutterAsset(String key) async {}
}

class FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  FakePlatformNavigationDelegate(PlatformNavigationDelegateCreationParams params) : super.implementation(params);

  @override
  Future<void> setOnNavigationRequest(
    FutureOr<NavigationDecision> Function(NavigationRequest request) onNavigationRequest,
  ) async {}
}

class FakePlatformWebViewWidget extends PlatformWebViewWidget {
  FakePlatformWebViewWidget(PlatformWebViewWidgetCreationParams params) : super.implementation(params);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
