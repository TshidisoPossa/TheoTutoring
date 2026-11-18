import 'package:flutter/material.dart';

class TermsAndConditionsPage extends StatelessWidget {
  const TermsAndConditionsPage({super.key});

  static const String contactEmail = 'support@theotutoring.co.za';

  /// When these terms last changed (shown at the top).
  static const String lastUpdated = '18 November 2026';

  static const List<_TermsSection> _sections = [
    _TermsSection(
      title: '1. About TheoTutoring',
      paragraphs: [
        'TheoTutoring is an app that connects students with approved tutors '
            'for one-on-one online lessons. Students find and book tutors, '
            'pay in the app, chat with their tutor and meet on Google Meet. '
            'By creating an account or using the app, you agree to these '
            'Terms and Conditions and to our Privacy Policy. If you do not '
            'agree, please do not use the app.',
      ],
    ),
    _TermsSection(
      title: '2. Accounts',
      paragraphs: [
        'You must give accurate, current information when you register and '
            'keep it up to date. You are responsible for keeping your login '
            'details private and for all activity on your account. You must '
            'confirm your email address with the 6-digit code we send you.',
        'Students must upload a valid proof of registration at an academic '
            'institution, which an administrator may check.',
        'Tutors must give their qualifications and upload a certificate and '
            'an identity document (ID card, ID book or passport). Tutor '
            'accounts stay pending until an administrator approves the '
            'application. An application that is incomplete, inaccurate or '
            'does not meet platform standards may be rejected with feedback, '
            'and the tutor may correct it and resubmit.',
      ],
    ),
    _TermsSection(
      title: '3. Booking Lessons',
      paragraphs: [
        'Each lesson is 60 minutes long. A lesson must start at least 2 '
            "hours after booking, no more than 90 days ahead, and inside the "
            "tutor's published availability. All times are South African "
            'Standard Time (SAST).',
        'Students may book several lessons at once, including the same time '
            'every week. The chosen times are held while the student pays. '
            'A booking is confirmed only once payment has gone through, after '
            'which it appears in the student\'s lessons and the tutor is '
            'notified.',
      ],
    ),
    _TermsSection(
      title: '4. Pricing, Payment and Receipts',
      paragraphs: [
        'The rate per lesson is set by TheoTutoring and is the same for all '
            'tutors. The total, including any discount, is shown before you '
            'pay. A package of 10 or more lessons receives a 10% discount. '
            'All amounts are in South African rand (ZAR).',
        'In this version of the app, payments are demonstration payments: '
            'no real money is charged, and card details entered are not sent '
            'to or stored by TheoTutoring.',
        'After a successful payment you can download a receipt showing the '
            'payment, each lesson and any refunds.',
      ],
    ),
    _TermsSection(
      title: '5. Online Lessons',
      paragraphs: [
        "Lessons take place in the tutor's Google Meet room. A lesson can be "
            'joined from 15 minutes before it starts until it ends. Tutors '
            'must connect Google Meet in the app before students can join '
            'their lessons. Google\'s own terms apply while you use Google '
            'Meet.',
      ],
    ),
    _TermsSection(
      title: '6. Rescheduling',
      paragraphs: [
        'A student may move a paid, confirmed lesson to another free time '
            "with the same tutor and subject, inside the tutor's "
            'availability and at least 2 hours ahead. The payment stays with '
            'the lesson, so nothing extra is charged or refunded, and the '
            'tutor is notified.',
      ],
    ),
    _TermsSection(
      title: '7. Cancellations and Refunds',
      paragraphs: [
        'A student may cancel a lesson before it starts. For a paid lesson '
            'the refund depends on how long before the start it is '
            'cancelled: 100% if 48 hours or more, 50% if between 24 and 48 '
            'hours, and no refund within 24 hours.',
        'If a tutor cancels a lesson, the student is refunded in full and '
            'may book a new time.',
        'Refunds are reviewed by an administrator, who may contact both the '
            'student and the tutor, and approved refunds are returned to the '
            'original payment method. Students may also report a problem with '
            'a lesson or a tutor in the app.',
        'Nothing in these terms limits your rights under the Consumer '
            'Protection Act 68 of 2008.',
      ],
    ),
    _TermsSection(
      title: '8. Tutor Responsibilities and Payouts',
      paragraphs: [
        'Tutors must keep their availability up to date, attend every '
            'confirmed lesson on time and conduct lessons professionally.',
        'TheoTutoring deducts a platform commission from each completed '
            'lesson. The rest is paid out to the tutor once an administrator '
            'approves the payout.',
      ],
    ),
    _TermsSection(
      title: '9. Chat Rules and Moderation',
      paragraphs: [
        'In-app chat is for arranging and discussing lessons. You may not '
            'share or ask for personal contact details (such as email '
            'addresses, phone numbers or other messaging and social media '
            'apps), arrange to meet or pay outside TheoTutoring, or use '
            'abusive language.',
        'Messages are checked automatically before they are delivered. A '
            'message that breaks these rules is blocked and not delivered, '
            "and the sender's chat is suspended until an administrator "
            'reviews it. The sender may explain what happened; the '
            'administrator then restores the chat or keeps it suspended. The '
            'other person is told that the sender\'s chat is suspended.',
        'Administrators may also review messages when investigating a '
            'reported issue or a refund request.',
      ],
    ),
    _TermsSection(
      title: '10. Acceptable Use',
      paragraphs: [
        'You agree not to: harass, threaten or discriminate against other '
            'users; share offensive, false or illegal content in chats or '
            'reviews; arrange payment for lessons outside the app; complete '
            "graded assessments on a student's behalf; or try to access "
            "another person's account or interfere with the app.",
      ],
    ),
    _TermsSection(
      title: '11. Suspension and Appeals',
      paragraphs: [
        'TheoTutoring may suspend or deactivate an account that breaks these '
            'terms. A suspended user is told the reason and may send one '
            'appeal for each suspension. An administrator reviews the appeal '
            'and either reinstates the account or keeps the suspension, and '
            'the user is notified of the decision.',
      ],
    ),
    _TermsSection(
      title: '12. Reviews',
      paragraphs: [
        'Students may review a lesson once it is completed. Reviews must be '
            'honest and based on the lesson. TheoTutoring may remove reviews '
            'that are abusive, misleading or unrelated to the lesson.',
      ],
    ),
    _TermsSection(
      title: '13. Privacy and Your Information',
      paragraphs: [
        'TheoTutoring processes your personal information in line with the '
            'Protection of Personal Information Act 4 of 2013 (POPIA), as '
            'explained in our Privacy Policy. We never sell your information.',
      ],
    ),
    _TermsSection(
      title: '14. Limitation of Liability',
      paragraphs: [
        'Tutors are independent and are not employees of TheoTutoring. While '
            'we review tutor applications, we do not guarantee specific '
            'academic results. To the extent allowed by law, TheoTutoring is '
            'not liable for indirect losses arising from your use of the app.',
      ],
    ),
    _TermsSection(
      title: '15. Changes to These Terms',
      paragraphs: [
        'We may update these terms from time to time; the date at the top '
            'shows the latest version. Continuing to use the app after a '
            'change means you accept the updated terms.',
      ],
    ),
    _TermsSection(
      title: '16. Governing Law and Contact',
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
                const SizedBox(height: 6),
                Text(
                  'Last updated: $lastUpdated',
                  style: theme.textTheme.bodySmall,
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
