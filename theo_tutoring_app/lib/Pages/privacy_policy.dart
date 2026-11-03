import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const String contactEmail = 'support@theotutoring.co.za';

  static const List<_PolicySection> _sections = [
    _PolicySection(
      title: '1. Who We Are',
      paragraphs: [
        'TheoTutoring is a mobile platform that connects students with '
            'approved tutors for one-on-one tutoring lessons. This Privacy '
            'Policy explains what personal information we collect, why we '
            'collect it and how we protect it.',
        'We process personal information in line with the Protection of '
            'Personal Information Act 4 of 2013 (POPIA).',
      ],
    ),
    _PolicySection(
      title: '2. Information We Collect',
      paragraphs: [
        'Account information: your name, email address, phone number and '
            'whether you are a student or a tutor.',
        'Student information: your academic institution and proof of '
            'registration.',
        'Tutor information: your qualifications, certificates, identity '
            'documents, subjects, bio, experience and weekly availability.',
        'Activity information: your bookings, lesson history, payments, '
            'refund requests, reviews and in-app chat messages.',
      ],
    ),
    _PolicySection(
      title: '3. How We Use Your Information',
      paragraphs: [
        'We use your information to create and manage your account, verify '
            'tutor applications and student registration, match students with '
            'tutors, schedule lessons, process payments and payouts, and '
            'send you notifications about your bookings and messages.',
        'We also use it to investigate reported issues and refund requests, '
            'and to keep the platform safe and working properly.',
      ],
    ),
    _PolicySection(
      title: '4. Who Can See Your Information',
      paragraphs: [
        'Students can see an approved tutor\'s public profile, including '
            'their name, photo, subjects, bio, availability and reviews.',
        'Tutors can see the name and lesson details of students who book '
            'them.',
        'Administrators can see account, booking and payment information, '
            'and may review chat messages when investigating a reported '
            'issue or refund request.',
      ],
    ),
    _PolicySection(
      title: '5. Service Providers',
      paragraphs: [
        'Sign-in is handled by Firebase Authentication, and push '
            'notifications are delivered through Firebase Cloud Messaging. '
            'Uploaded files such as profile photos and certificates are '
            'stored with Cloudinary.',
        'Video lessons take place on Google Meet. Each tutor signs in with '
            'Google once so the app can create their Meet room. '
            'TheoTutoring saves only the room link and does not keep access '
            'to the tutor\'s Google account. During a lesson, Google\'s own '
            'privacy policy applies.',
        'These providers only process your information to deliver their '
            'service to TheoTutoring. We never sell your personal '
            'information to third parties.',
      ],
    ),
    _PolicySection(
      title: '6. How We Protect Your Information',
      paragraphs: [
        'Your password is managed by Firebase and is never stored by '
            'TheoTutoring. Information is sent over encrypted connections, '
            'and access to administrator tools is limited to authorised '
            'staff.',
        'No system is completely secure. If we become aware of a breach '
            'that affects your personal information, we will notify you and '
            'the Information Regulator as required by POPIA.',
      ],
    ),
    _PolicySection(
      title: '7. How Long We Keep It',
      paragraphs: [
        'We keep your information for as long as your account is active. '
            'Booking and payment records may be kept for longer where the '
            'law requires us to keep financial records.',
      ],
    ),
    _PolicySection(
      title: '8. Your Rights',
      paragraphs: [
        'You may ask to see the personal information we hold about you, ask '
            'us to correct or delete it, or object to how we process it. You '
            'can update most of your details yourself in the app\'s profile '
            'and settings pages.',
        'If you are unhappy with how we handle your information, you may '
            'lodge a complaint with the Information Regulator of South '
            'Africa.',
      ],
    ),
    _PolicySection(
      title: '9. Changes to This Policy',
      paragraphs: [
        'We may update this policy from time to time. Continuing to use the '
            'app after a change means you accept the updated policy.',
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
