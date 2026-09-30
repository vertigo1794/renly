// app/lib/features/tools/commission_calculator_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/asset_webview_screen.dart';

/// Loads the real HTML5+CSS3+JavaScript commission_calculator.html tool
/// into an in-app WebView -- a live-calculating (oninput events, DOM
/// manipulation) split calculator, not a Dart re-implementation. Reachable
/// from Property Detail / Requirement Detail's "Commission Calculator"
/// action and from Profile's App & Support card.
class CommissionCalculatorScreen extends StatelessWidget {
  const CommissionCalculatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AssetWebViewScreen(
      titleText: 'commission_calculator_title'.tr(),
      assetDirectory: 'assets/web',
      initialAssetFileName: 'commission_calculator.html',
    );
  }
}
