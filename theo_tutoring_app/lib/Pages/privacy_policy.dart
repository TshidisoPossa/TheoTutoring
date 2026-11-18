import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const String contactEmail = 'support@theotutoring.co.za';

  /// When this policy last changed (shown at the top).
  static const String lastUpdated = '18 November 2026';

  static const List<_PolicySection> _sections = [
    _PolicySection(
      title: '1. Who We Are',
      paragraphs: [
        'TheoTutoring is an app that connects students with approved tutors '
            'for one-on-one online lessons. This Privacy Policy explains what '
            'personal information we collect, why we collect it, who we share '
            'it with and how we protect it.',
        'We process personal information in line with the Protection of '
            'Personal Information Act 4 of 2013 (POPIA).',
      ],
    ),
    _PolicySection(
      title: '2. Information We Collect',
      paragraphs: [
        'Account information: your name, email address, phone number, '
            'profile photo, and whether you are a student, a tutor or an '
            'administrator.',
        'Student information: your institution, course and year, address, '
            'subject of interest and proof of registration.',
        'Tutor information: your bio, experience, subjects, qualifications, '
            'certificate, identity document, weekly availability and any '
            'date changes to it, and your Google Meet room link.',
        'Activity information: your bookings, lessons, rescheduled and '
            'cancelled lessons, payments, receipts, refunds, payouts, '
            'reviews, reports, notifications and in-app chat messages.',
        'Safety information: messages blocked by our chat filter, any '
            'explanation you send about them, account suspensions and '
            'appeals, and the decisions made.',
        'Usage information: when a tutor was last active in the app, which '
            'is used to show students whether the tutor is "Available Now".',
      ],
    ),
    _PolicySection(
      title: '3. How We Use Your Information',
      paragraphs: [
        'We use your information to create and manage your account, confirm '
            'your email address, verify tutor applications and student '
            'registration, match students with tutors, schedule, reschedule '
            'and cancel lessons, process payments, refunds and payouts, '
            'create receipts, and send you notifications about your '
            'bookings, payments and messages.',
        'We automatically check chat messages before they are delivered, to '
            'stop the sharing of contact details and abusive language. A '
            'blocked message is kept so that an administrator can review it.',
        'We also use your information to investigate reports, refund '
            'requests and appeals, and to keep the platform safe and working '
            'properly.',
      ],
    ),
    _PolicySection(
      title: '4. Who Can See Your Information',
      paragraphs: [
        "Students can see an approved tutor's public profile, including their "
            'name, photo, subjects, bio, qualifications, availability, '
            'reviews and whether they are available now.',
        'Tutors can see the name and lesson details of students who book '
            'them, and the messages students send them.',
        'Administrators can see account, booking, payment, refund and payout '
            'information and uploaded documents (such as proof of '
            'registration, certificates and identity documents) so they can '
            'verify accounts. They can see blocked chat messages and '
            'explanations, and may review other chat messages when '
            'investigating a reported issue or refund request.',
        "If your chat is suspended, the person you were chatting with is told "
            'that it is suspended, but not what your message said.',
      ],
    ),
    _PolicySection(
      title: '5. Service Providers',
      paragraphs: [
        'We use the following providers to run the app. They only process '
            'your information to deliver their service to TheoTutoring:',
        '• Firebase Authentication (Google) handles sign-in and passwords.',
        '• Cloud Firestore (Google) stores chat messages, notifications and '
            'chat moderation records.',
        '• A MySQL database hosted by Aiven stores accounts, profiles, '
            'bookings, payments and other app records.',
        '• Cloudinary stores uploaded files such as profile photos, '
            'certificates, identity documents and proofs of registration.',
        '• Brevo sends the emails containing your verification codes.',
        '• Google Meet hosts video lessons. Each tutor signs in with Google '
            'once so the app can create their Meet room. TheoTutoring saves '
            "only the room link and keeps no access to the tutor's Google "
            "account. During a lesson, Google's own privacy policy applies.",
        'We never sell your personal information to third parties.',
      ],
    ),
    _PolicySection(
      title: '6. How We Protect Your Information',
      paragraphs: [
        'Your password is managed by Firebase and is never stored by '
            'TheoTutoring. Information is sent over encrypted connections, '
            'and access to administrator tools is limited to authorised '
            'staff with the right permissions.',
        'In this version of the app, payments are demonstration payments: '
            'card details you enter are not sent to or stored by '
            'TheoTutoring.',
        'No system is completely secure. If we become aware of a breach '
            'that affects your personal information, we will notify you and '
            'the Information Regulator as required by POPIA.',
      ],
    ),
    _PolicySection(
      title: '7. How Long We Keep It',
      paragraphs: [
        'We keep your information for as long as your account is active. '
            'Booking, payment and refund records may be kept for longer where '
            'the law requires us to keep financial records. Moderation, '
            'suspension and appeal records are kept so that decisions can be '
            'reviewed.',
      ],
    ),
    _PolicySection(
      title: '8. Your Rights',
      paragraphs: [
        'You may ask to see the personal information we hold about you, ask '
            'us to correct or delete it, or object to how we process it. You '
            "can update most of your details yourself in the app's profile "
            'and settings pages.',
        'If you are unhappy with how we handle your information, you may '
            'lodge a complaint with the Information Regulator of South '
            'Africa.',
      ],
    ),
    _PolicySection(
      title: '9. Changes to This Policy',
      paragraphs: [
        'We may update this policy from time to time; the date at the top '
            'shows the latest version. Continuing to use the app after a '
            'change means you accept the updated policy.',
      ],
    ),
    _PolicySection(
      title: '10. Contact Us',
      paragraphs: [
        'Questions or requests about your personal information can be sent '
            'to $contactEmail.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Text(
                  'TheoTutoring Privacy Policy',
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

class _PolicySection {
  const _PolicySection({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}
