// app/lib/core/widgets/asset_webview_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Loads a real HTML5+CSS3+JavaScript document (assets/web/*.html) into an
/// in-app WebView -- used for the Privacy Policy, Terms of Service, and
/// (separately) the Commission Calculator tool. Not a wrapper around
/// PrivacyScreen/whatever else used to just render `.tr()`d body text as a
/// plain `Text` widget: these are genuine HTML pages with real markup,
/// styling, and (privacy/terms) a real hyperlink between the two.
///
/// [assetDirectory] + [initialAssetFileName] are split apart (rather than
/// one combined path) because navigating between the two legal documents
/// needs to resolve a bare relative href like `terms_of_service.html`
/// against the same directory -- see [_handleNavigation].
class AssetWebViewScreen extends StatefulWidget {
  const AssetWebViewScreen({
    super.key,
    required this.titleText,
    required this.assetDirectory,
    required this.initialAssetFileName,
  });

  final String titleText;
  final String assetDirectory;
  final String initialAssetFileName;

  @override
  State<AssetWebViewScreen> createState() => _AssetWebViewScreenState();
}

class _AssetWebViewScreenState extends State<AssetWebViewScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(onNavigationRequest: _handleNavigation),
      )
      ..loadFlutterAsset('${widget.assetDirectory}/${widget.initialAssetFileName}');
  }

  /// Tapping the `<a href="terms_of_service.html">`/`<a
  /// href="privacy_policy.html">` link inside either document fires a real
  /// navigation request the WebView can't resolve on its own (there's no
  /// HTTP server behind a Flutter asset) -- intercepted here and re-issued
  /// as another loadFlutterAsset call for the SAME html file the link
  /// names, keeping the hyperlink genuinely functional rather than a dead
  /// click. Anything that isn't a bare `*.html` file name (an external
  /// link, if one is ever added) falls through to the platform's normal
  /// handling instead.
  NavigationDecision _handleNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    final fileName = uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : null;
    if (fileName != null && fileName.endsWith('.html')) {
      _controller.loadFlutterAsset('${widget.assetDirectory}/$fileName');
      return NavigationDecision.prevent;
    }
    // mailto: links (e.g. the Privacy Policy's support contact) can't be
    // loaded by the WebView itself -- hand them to the OS mail app instead,
    // same as a real browser would.
    if (uri?.scheme == 'mailto') {
      launchUrl(uri!);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titleText)),
      body: WebViewWidget(controller: _controller),
    );
  }
}
