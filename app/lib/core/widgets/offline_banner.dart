import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Slim app-wide banner shown at the top of the screen whenever the device
/// has no network connection. Wrapped around the whole app in main.dart's
/// `MaterialApp.router` builder so it stays visible no matter which
/// screen/tab is active.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({required this.child, super.key});

  final Widget child;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(_updateFromResult);
    Connectivity().onConnectivityChanged.listen(_updateFromResult);
  }

  void _updateFromResult(List<ConnectivityResult> results) {
    final offline = results.every((r) => r == ConnectivityResult.none);
    if (mounted && offline != _offline) setState(() => _offline = offline);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_offline)
          Container(
            width: double.infinity,
            color: Colors.red,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SafeArea(
              bottom: false,
              child: Text(
                'offline_banner_message'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
