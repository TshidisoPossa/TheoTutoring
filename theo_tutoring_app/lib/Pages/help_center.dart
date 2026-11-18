import 'package:flutter/material.dart';

import 'faq_page.dart';

/// The Help Center: the FAQ (faq_page.dart) under the Help Center title,
/// so there is one list of questions to keep up to date.
class HelpCenterPage extends StatelessWidget {
  const HelpCenterPage({super.key});

  static const String contactEmail = faqContactEmail;

  @override
  Widget build(BuildContext context) => const FaqPage(title: 'Help Center');
}
