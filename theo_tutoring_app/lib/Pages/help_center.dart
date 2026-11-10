import 'package:flutter/material.dart';

/// Frequently asked questions for students and tutors, grouped by topic.
/// Each question expands to show its answer.
class HelpCenterPage extends StatelessWidget {
  const HelpCenterPage({super.key});

  static const String contactEmail = 'support@theotutoring.co.za';

  static const List<_HelpTopic> _topics = [
    _HelpTopic(
      title: 'Getting Started',
      icon: Icons.rocket_launch_outlined,
      questions: [
        _HelpQuestion(
          'What is TheoTutoring?',
          'TheoTutoring connects students with approved tutors for '
              'one-on-one lessons. Lessons take place online on Google Meet.',
        ),
        _HelpQuestion(
          'Why is my tutor account still pending?',
          'Every tutor application is reviewed by an administrator before '
              'the account becomes active. Make sure you have uploaded your '
              'qualifications, certificates and identity documents. You can '
              'use the app once your application is approved.',
        ),
        _HelpQuestion(
          'What do students need to register?',
          'Students must upload valid proof of registration at an academic '
              'institution.',
        ),
      ],
    ),
    _HelpTopic(
      title: 'Booking Lessons',
      icon: Icons.event_available_outlined,
      questions: [
        _HelpQuestion(
          'How long is a lesson?',
          'Every lesson is 60 minutes long. All times are shown in South '
              'African Standard Time.',
        ),
        _HelpQuestion(
          'When can I book a lesson?',
          'Lessons must be booked at least 2 hours before the start time and '
              'no more than 90 days in advance, inside the tutor\'s weekly '
              'availability.',
        ),
        _HelpQuestion(
          'When is my booking confirmed?',
          'A booking is confirmed once payment is complete and the lesson '
              'appears in your lessons.',
        ),
      ],
    ),
    _HelpTopic(
      title: 'Joining a Lesson on Google Meet',
      icon: Icons.videocam_outlined,
      questions: [
        _HelpQuestion(
          'How do I join my lesson?',
          'Students: open Lessons and tap Start session. Tutors: open the '
              'lesson from your Schedule and tap Join session. Google Meet '
              'opens in the Meet app or your browser.',
        ),
        _HelpQuestion(
          'Why can\'t I join yet?',
          'A lesson opens 15 minutes before it starts and closes when it '
              'ends. Only Confirmed or Postponed lessons can be joined, and a '
              'Postponed lesson must be paid first.',
        ),
        _HelpQuestion(
          'Tutors: how do I set up my Meet room?',
          'Go to My Profile and tap Connect Google Meet. Sign in with Google '
              'once and the app creates your room. Students cannot join your '
              'lessons until it is connected.',
        ),
      ],
    ),
    _HelpTopic(
      title: 'Payments and Refunds',
      icon: Icons.payments_outlined,
      questions: [
        _HelpQuestion(
          'How much does a lesson cost?',
          'TheoTutoring sets one hourly rate for all tutors. The price is '
              'shown before you confirm a booking. All amounts are in South '
              'African Rand (ZAR).',
        ),
        _HelpQuestion(
          'Are there discounts?',
          'Packages of 10 or more lessons receive a 10% discount.',
        ),
        _HelpQuestion(
          'How do I get a refund?',
          'If a lesson does not take place as booked, submit a refund request '
              'in the app. An administrator reviews every request and may '
              'contact both the student and the tutor. Approved refunds go '
              'back to the original payment method.',
        ),
        _HelpQuestion(
          'Tutors: how do payouts work?',
          'TheoTutoring deducts a platform commission from each completed '
              'lesson. The rest is paid out to you once an administrator '
              'approves the payout.',
        ),
      ],
    ),
    _HelpTopic(
      title: 'For Tutors',
      icon: Icons.school_outlined,
      questions: [
        _HelpQuestion(
          'How do students find me?',
          'Approved tutors appear in the student tutor search with their '
              'name, photo, subjects, bio, availability and reviews. Keep '
              'your profile and subjects up to date.',
        ),
        _HelpQuestion(
          'How do I set my availability?',
          'Update your weekly availability from My Profile. Students can '
              'only book lessons inside the times you publish.',
        ),
      ],
    ),
    _HelpTopic(
      title: 'Account and Privacy',
      icon: Icons.manage_accounts_outlined,
      questions: [
        _HelpQuestion(
          'How do I reset my password?',
          'On the login screen, tap Forgot password and follow the link '
              'sent to your email.',
        ),
        _HelpQuestion(
          'Who can see my messages?',
          'Chats are between you and the other person. An administrator may '
              'review messages only when investigating a reported issue or '
              'refund request.',
        ),
        _HelpQuestion(
          'How do I see, correct or delete my information?',
          'You can update most details in your profile. For anything else, '
              'email $contactEmail.',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Help Center')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Text(
                  'How can we help?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Answers to common questions about lessons, payments and '
                  'your account.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                for (final topic in _topics) ...[
                  Row(
                    children: [
                      Icon(topic.icon, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          topic.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final q in topic.questions)
                          ExpansionTile(
                            title: Text(q.question),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              14,
                            ),
                            expandedAlignment: Alignment.centerLeft,
                            children: [
                              Text(
                                q.answer,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                ],
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Still need help?',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Email our support team and we will get back to '
                          'you.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Icons.mail_outline,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(child: SelectableText(contactEmail)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpTopic {
  const _HelpTopic({
    required this.title,
    required this.icon,
    required this.questions,
  });

  final String title;
  final IconData icon;
  final List<_HelpQuestion> questions;
}

class _HelpQuestion {
  const _HelpQuestion(this.question, this.answer);

  final String question;
  final String answer;
}
