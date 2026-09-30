import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/asset_webview_screen.dart';

/// Renders the real HTML5+CSS3 privacy_policy.html document (with a real
/// hyperlink to Terms of Service) inside a WebView, rather than a plain
/// `.tr()`d Text body -- see AssetWebViewScreen's own doc comment.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AssetWebViewScreen(
      titleText: 'privacy_title'.tr(),
      assetDirectory: 'assets/web',
      initialAssetFileName: 'privacy_policy.html',
    );
  }
}
