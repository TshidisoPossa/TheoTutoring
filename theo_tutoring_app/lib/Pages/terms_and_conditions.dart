import 'package:flutter/material.dart';

class TermsAndConditionsPage extends StatelessWidget {
  const TermsAndConditionsPage({super.key});

  static const String contactEmail = 'support@theotutoring.co.za';

  static const List<_TermsSection> _sections = [
    _TermsSection(
      title: '1. About TheoTutoring',
      paragraphs: [
        'TheoTutoring is a mobile platform that connects students with '
            'approved tutors for one-on-one tutoring lessons. By creating an '
            'account or using the app, you agree to these Terms and '
            'Conditions. If you do not agree, please do not use the app.',
      ],
    ),
    _TermsSection(
      title: '2. Accounts',
      paragraphs: [
        'You must provide accurate, current information when you register '
            'and keep it up to date. You are responsible for keeping your '
            'login details private and for all activity on your account.',
        'Students must upload valid proof of registration at an academic '
            'institution. Tutors must submit their qualifications, '
            'certificates and identity documents for review.',
        'Tutor accounts remain pending until an administrator approves the '
            'application. TheoTutoring may reject an application that is '
            'incomplete, inaccurate or does not meet platform standards.',
      ],
    ),
    _TermsSection(
      title: '3. Booking Lessons',
      paragraphs: [
        'Each lesson is 60 minutes long. Lessons must be booked at least '
            '2 hours before the start time and no more than 90 days in '
            'advance. All times are shown in South African Standard Time.',
        'A lesson can only be booked inside the tutor\'s published weekly '
            'availability. A booking is confirmed once payment has been '
            'completed and the booking appears in your lessons.',
      ],
    ),
    _TermsSection(
      title: '4. Pricing and Payment',
      paragraphs: [
        'The hourly tutoring rate is set by TheoTutoring and is the same for '
            'all tutors. The price you pay is shown before you confirm a '
            'booking.',
        'Students may buy a single lesson or a package of lessons. Packages '
            'of 10 or more lessons receive a 10% discount.',
        'All amounts are in South African Rand (ZAR).',
      ],
    ),
    _TermsSection(
      title: '5. Cancellations, Refunds and Issues',
      paragraphs: [
        'If a lesson does not take place as booked, or you experience a '
            'problem with a tutor or a payment, you may submit a refund '
            'request or report an issue through the app.',
        'Every request is reviewed by an administrator, who may contact '
            'both the student and the tutor before making a decision. '
            'Approved refunds are returned to the original payment method.',
        'Nothing in these terms limits your rights under the Consumer '
            'Protection Act 68 of 2008.',
      ],
    ),
    _TermsSection(
      title: '6. Tutor Responsibilities and Payouts',
      paragraphs: [
        'Tutors must keep their availability up to date, attend every '
            'confirmed lesson on time and conduct lessons professionally.',
        'TheoTutoring deducts a platform commission from each completed '
            'lesson. The remaining amount is paid out to the tutor once the '
            'payout has been approved by an administrator.',
      ],
    ),
    _TermsSection(
      title: '7. Acceptable Use',
      paragraphs: [
        'You agree not to: harass, threaten or discriminate against other '
            'users; share offensive, false or illegal content in chats or '
            'reviews; arrange payment for lessons outside the app; complete '
            'graded assessments on a student\'s behalf; or try to access '
            'another person\'s account or interfere with the app.',
        'TheoTutoring may suspend or deactivate any account that breaks '
            'these rules.',
      ],
    ),
    _TermsSection(
      title: '8. Messages and Reviews',
      paragraphs: [
        'In-app chat is provided so students and tutors can arrange and '
            'discuss lessons. Messages may be reviewed by an administrator '
            'when investigating a reported issue or refund request.',
        'Reviews must be honest and based on a real lesson. TheoTutoring may '
            'remove reviews that are abusive, misleading or unrelated to the '
            'lesson.',
      ],
    ),
    _TermsSection(
      title: '9. Privacy and Your Information',
      paragraphs: [
        'TheoTutoring processes your personal information in line with the '
            'Protection of Personal Information Act 4 of 2013 (POPIA). We '
            'collect only the information needed to run the platform, such '
            'as your name, contact details, academic information and '
            'uploaded documents.',
        'Sign-in is handled by Firebase Authentication, and uploaded files '
            'such as profile photos and certificates are stored with '
            'Cloudinary. Your information is never sold to third parties.',
        'You may ask to see, correct or delete your personal information by '
            'contacting us at the address below.',
      ],
    ),
    _TermsSection(
      title: '10. Limitation of Liability',
      paragraphs: [
        'Tutors are independent and are not employees of TheoTutoring. While '
            'we review tutor applications, we do not guarantee specific '
            'academic results. To the extent allowed by law, TheoTutoring is '
            'not liable for indirect losses arising from your use of the app.',
      ],
    ),
    _TermsSection(
      title: '11. Changes to These Terms',
      paragraphs: [
        'We may update these terms from time to time. Continuing to use the '
            'app after a change means you accept the updated terms.',
      ],
    ),
    _TermsSection(
      title: '12. Governing Law and Contact',
      paragraphs: [
        'These terms are governed by the laws of the Republic of South '
            'Africa.',
        'Questions about these terms can be sent to $contactEmail.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms and Conditions'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Text(
                  'TheoTutoring Terms and Conditions',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                for (final section in _sections) ...[
                  Text(
                    section.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  for (final paragraph in section.paragraphs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        paragraph,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(height: 1.5),
                      ),
                    ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TermsSection {
  const _TermsSection({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}
