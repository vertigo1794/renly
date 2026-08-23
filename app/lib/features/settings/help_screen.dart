import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  Widget _faqEntry(BuildContext context, String question, String answer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(answer),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('help_title'.tr())),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('help_faq_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _faqEntry(context, 'help_faq_q1'.tr(), 'help_faq_a1'.tr()),
            _faqEntry(context, 'help_faq_q2'.tr(), 'help_faq_a2'.tr()),
            _faqEntry(context, 'help_faq_q3'.tr(), 'help_faq_a3'.tr()),
            const SizedBox(height: 20),
            Text('help_contact_title'.tr(), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('help_contact_body'.tr()),
          ],
        ),
      ),
    );
  }
}
