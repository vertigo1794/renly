import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('privacy_title'.tr())),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text('privacy_body'.tr()),
      ),
    );
  }
}
