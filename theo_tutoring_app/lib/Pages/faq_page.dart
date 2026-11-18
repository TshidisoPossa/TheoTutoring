import 'package:flutter/material.dart';

/// Who a question is for.
enum FaqAudience { everyone, students, tutors }

/// One question and its answer.
class FaqQuestion {
  const FaqQuestion(
    this.question,
    this.answer, {
    this.audience = FaqAudience.everyone,
  });

  final String question;
  final String answer;
  final FaqAudience audience;
}

/// A group of questions, e.g. "Booking lessons".
class FaqTopic {
  const FaqTopic({
    required this.title,
    required this.icon,
    required this.questions,
  });

  final String title;
  final IconData icon;
  final List<FaqQuestion> questions;
}

const String faqContactEmail = 'support@theotutoring.co.za';

const _s = FaqAudience.students;
const _t = FaqAudience.tutors;

/// Every frequently asked question, grouped by topic. Keep these in step
/// with the app (and with the Terms and Privacy Policy).
const List<FaqTopic> faqTopics = [
  FaqTopic(
    title: 'Getting started',
    icon: Icons.rocket_launch_outlined,
    questions: [
      FaqQuestion(
        'What is TheoTutoring?',
        'TheoTutoring connects students with approved tutors for one-on-one '
            'online lessons. You find a tutor, book and pay in the app, chat '
            'with your tutor, and meet on Google Meet.',
      ),
      FaqQuestion(
        'What do I need to register as a student?',
        'Your name, email address and phone number, your institution, course '
            'and year, and a proof of registration at your institution. An '
            'administrator may check your proof of registration.',
        audience: _s,
      ),
      FaqQuestion(
        'What do I need to register as a tutor?',
        'Your bio, years of experience, subjects and qualifications, a clear '
            'scan or photo of your certificate and of your ID document (ID '
            'card, ID book or passport), and your weekly availability. You '
            'can connect Google Meet later from your profile.',
        audience: _t,
      ),
      FaqQuestion(
        'Why do I need to verify my email?',
        'We email you a 6-digit code to confirm your email address belongs '
            'to you. Enter it in the app. If it does not arrive, check your '
            'spam folder or tap Resend code.',
      ),
      FaqQuestion(
        'Why is my tutor account still pending?',
        'Every tutor application is reviewed by an administrator, who checks '
            'your qualifications, certificate and ID document. You can use '
            'the app once it is approved. If it is rejected you will see the '
            "administrator's feedback and can fix your details and resubmit.",
        audience: _t,
      ),
      FaqQuestion(
        'How do I reset my password?',
        'On the login screen, tap Forgot password and follow the link sent '
            'to your email.',
      ),
    ],
  ),
  FaqTopic(
    title: 'Finding a tutor and booking',
    icon: Icons.event_available_outlined,
    questions: [
      FaqQuestion(
        'How do I find a tutor?',
        'Tap the search icon at the top of your dashboard or Find a tutor. '
            "You can search by name or subject. A tutor's profile shows "
            'their subjects, qualifications, reviews and availability: click '
            'on a day to see their free times.',
        audience: _s,
      ),
      FaqQuestion(
        'When can I book a lesson?',
        'Lessons are 60 minutes long and must start at least 2 hours from '
            "now and no more than 90 days ahead, inside the tutor's "
            'availability. All times are South African time (SAST).',
        audience: _s,
      ),
      FaqQuestion(
        'Can I book several lessons, or the same time every week?',
        'Yes. You can choose several times in one booking, and after picking '
            'the first one the app can repeat it weekly for you. A package of '
            '10 or more lessons gets a 10% discount.',
        audience: _s,
      ),
      FaqQuestion(
        'When is my booking confirmed?',
        'As soon as your payment goes through. The lesson then appears in '
            'Lessons and as a dot on your dashboard calendar, and your tutor '
            'is notified. Your chosen times are held for you while you pay.',
        audience: _s,
      ),
      FaqQuestion(
        'Can I message a tutor before booking?',
        "Yes. Open the tutor's profile and tap Message Tutor.",
        audience: _s,
      ),
    ],
  ),
  FaqTopic(
    title: 'Lessons on Google Meet',
    icon: Icons.videocam_outlined,
    questions: [
      FaqQuestion(
        'How do I join my lesson?',
        'Students: open Lessons and tap Start session, then Open Google Meet. '
            'Tutors: open the lesson from your Schedule and tap Join session. '
            'A lesson can be joined from 15 minutes before it starts until it '
            'ends.',
      ),
      FaqQuestion(
        'How do I set up my Google Meet room?',
        'Go to My Profile and tap Connect Google Meet, then sign in with a '
            'Google account. The app creates your room and saves its link. '
            'It is not required to register, but students cannot join your '
            'lessons until it is connected.',
        audience: _t,
      ),
      FaqQuestion(
        'Where do I see my lessons?',
        'Students: the Lessons tab (Upcoming, Completed and Cancelled) and '
            'the calendar on your dashboard. Tap a date to see its lessons. '
            'Tutors: your Schedule and dashboard.',
      ),
    ],
  ),
  FaqTopic(
    title: 'Rescheduling, cancelling and refunds',
    icon: Icons.event_repeat_outlined,
    questions: [
      FaqQuestion(
        'How do I reschedule a lesson?',
        'Open Lessons, tap the menu on a paid, confirmed lesson and choose '
            "Reschedule. Pick another free time in your tutor's availability "
            '(at least 2 hours from now). Your payment moves with the lesson, '
            'so nothing extra is charged, and your tutor is notified.',
        audience: _s,
      ),
      FaqQuestion(
        'How do I cancel, and will I get a refund?',
        'Open Lessons, tap the menu and choose Cancel. For a paid lesson you '
            'get 100% back if you cancel 48 hours or more before it starts, '
            '50% between 24 and 48 hours, and nothing within 24 hours. '
            'Refunds are reviewed by an administrator and go back to the '
            'original payment method.',
        audience: _s,
      ),
      FaqQuestion(
        'What if my tutor cancels?',
        'You are refunded in full, and you are notified with a link to book '
            'a new time with the same tutor.',
        audience: _s,
      ),
      FaqQuestion(
        'What if something went wrong with a lesson?',
        'Open Lessons, tap the menu on the lesson and choose Report. An '
            'administrator reviews every report and may contact both of you.',
        audience: _s,
      ),
    ],
  ),
  FaqTopic(
    title: 'Payments and receipts',
    icon: Icons.payments_outlined,
    questions: [
      FaqQuestion(
        'How much does a lesson cost?',
        'TheoTutoring sets one rate per lesson for all tutors. The total, '
            'including any package discount, is shown before you pay. All '
            'amounts are in South African rand (ZAR).',
        audience: _s,
      ),
      FaqQuestion(
        'How do I pay?',
        'Choose card, PayPal or EFT on the payment page. In this version of '
            'the app payments are demonstration payments: no real money is '
            'charged, and card details you type are never sent to or stored '
            'by TheoTutoring.',
        audience: _s,
      ),
      FaqQuestion(
        'How do I get a receipt?',
        'After a successful payment, tap Download Receipt. You get a PDF with '
            'the receipt number, payment date, tutor, subject, each lesson, '
            'the amount paid and any refunds.',
        audience: _s,
      ),
      FaqQuestion(
        'How are tutors paid?',
        'TheoTutoring deducts a platform commission from each completed '
            'lesson. The rest is paid out to you once an administrator '
            'approves the payout.',
        audience: _t,
      ),
    ],
  ),
  FaqTopic(
    title: 'Messages and notifications',
    icon: Icons.chat_bubble_outline_rounded,
    questions: [
      FaqQuestion(
        'What can I not send in chat?',
        'To keep everyone safe and lessons on the platform, messages may not '
            'contain email addresses, phone numbers, other apps or social '
            'media (such as WhatsApp or Instagram), requests to pay or meet '
            'outside TheoTutoring, or abusive language. Messages are checked '
            'automatically before they are delivered.',
      ),
      FaqQuestion(
        'Why was my message blocked and my chat suspended?',
        'A blocked message is never delivered. Your chat is suspended (you '
            'can still read it) until an administrator reviews the message. '
            'Tap Explain to the admin to say what happened. The administrator '
            'then restores your chat or keeps it suspended, and you are '
            'notified either way.',
      ),
      FaqQuestion(
        "Why does a conversation say the other person's chat is suspended?",
        'One of their messages was blocked and is being reviewed. They cannot '
            'send messages until an administrator restores their chat.',
      ),
      FaqQuestion(
        'What does the number on the Chat icon mean?',
        'It is how many unread messages you have. It goes down as you open '
            'your conversations.',
      ),
      FaqQuestion(
        'How do notifications work?',
        'The bell shows your notifications, such as payments, bookings, '
            'reminders, refunds and messages. While you are using the app, '
            'new ones also pop up at the top of the screen for a few seconds.',
      ),
    ],
  ),
  FaqTopic(
    title: 'For tutors',
    icon: Icons.school_outlined,
    questions: [
      FaqQuestion(
        'How do students find me?',
        'Approved tutors appear in tutor search with their name, photo, '
            'subjects, bio, qualifications, availability and reviews. '
            'Students also see "Available Now" while you are using the app.',
        audience: _t,
      ),
      FaqQuestion(
        'How do I set my availability?',
        'Set your weekly hours in My Profile. You can also change single '
            'dates on the calendar, for example to take a day off. Students '
            'can only book inside your available times.',
        audience: _t,
      ),
      FaqQuestion(
        'How do reviews work?',
        'Students can review a lesson once it is completed. Your average '
            'rating and latest reviews appear on your profile and dashboard.',
        audience: _t,
      ),
      FaqQuestion(
        'How do I report a problem with a student?',
        'Go to My Profile and tap Report a Problem.',
        audience: _t,
      ),
    ],
  ),
  FaqTopic(
    title: 'Account, safety and privacy',
    icon: Icons.manage_accounts_outlined,
    questions: [
      FaqQuestion(
        'Why is my account suspended?',
        'An administrator can suspend an account that breaks the Terms. You '
            'will see the reason and can send one appeal. The administrator '
            'reviews it and either reinstates your account or keeps the '
            'suspension.',
      ),
      FaqQuestion(
        'Who can see my information?',
        'Students see an approved tutor\'s public profile. Tutors see the '
            'name and lesson details of students who book them. '
            'Administrators can see account, booking, payment and document '
            'details to run the platform. See the Privacy Policy for more.',
      ),
      FaqQuestion(
        'How do I see, correct or delete my information?',
        'You can update most details in your profile. For anything else, or '
            'to delete your account, email $faqContactEmail.',
      ),
    ],
  ),
];

/// The FAQ: every question grouped by topic, with a search box and a
/// filter for students or tutors. Each question expands to its answer.
/// Also shown as the Help Center.
class FaqPage extends StatefulWidget {
  const FaqPage({super.key, this.title = 'FAQ', this.initialAudience});

  /// The app bar title ("FAQ", or "Help Center").
  final String title;

  /// Pre-selects Students or Tutors (null shows everything).
  final FaqAudience? initialAudience;

  @override
  State<FaqPage> createState() => _FaqPageState();
}

class _FaqPageState extends State<FaqPage> {
  late FaqAudience? _audience = widget.initialAudience;
  String _query = '';

  bool _matches(FaqQuestion q) {
    final audience = _audience;
    if (audience != null &&
        q.audience != FaqAudience.everyone &&
        q.audience != audience) {
      return false;
    }
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return q.question.toLowerCase().contains(query) ||
        q.answer.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topics = [
      for (final topic in faqTopics)
        if (topic.questions.where(_matches).toList() case final qs
            when qs.isNotEmpty)
          (topic: topic, questions: qs),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Text(
                  'Frequently asked questions',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Answers about booking, lessons, payments, chat and your '
                  'account.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('faq-search'),
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Search questions',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (label, audience) in [
                      ('All', null),
                      ('Students', FaqAudience.students),
                      ('Tutors', FaqAudience.tutors),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _audience == audience,
                        onSelected: (_) =>
                            setState(() => _audience = audience),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (topics.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No questions match "$_query". Try another word, or '
                      'email us below.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                for (final (:topic, :questions) in topics) ...[
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
                        for (final q in questions)
                          ExpansionTile(
                            // Searching opens the matches
                            key: ValueKey('${q.question}|${_query.isNotEmpty}'),
                            initiallyExpanded: _query.trim().isNotEmpty,
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
                            const Expanded(
                              child: SelectableText(faqContactEmail),
                            ),
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
