import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/asset_webview_screen.dart';

/// Renders the real HTML5+CSS3 terms_of_service.html document (with a real
/// hyperlink back to Privacy Policy) inside a WebView -- see
/// AssetWebViewScreen's own doc comment. Previously there was no Terms of
/// Service screen at all; AuthSelectionScreen's footer mention of it was
/// styled text only, not tappable.
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AssetWebViewScreen(
      titleText: 'terms_of_service_title'.tr(),
      assetDirectory: 'assets/web',
      initialAssetFileName: 'terms_of_service.html',
    );
  }
}
