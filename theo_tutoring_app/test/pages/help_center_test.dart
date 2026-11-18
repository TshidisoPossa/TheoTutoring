import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/faq_page.dart';
import 'package:theo_tutoring_app/Pages/help_center.dart';
import 'package:theo_tutoring_app/Pages/privacy_policy.dart';
import 'package:theo_tutoring_app/Pages/terms_and_conditions.dart';

// The FAQ (also shown as the Help Center), and the Terms and Privacy
// Policy it sits next to in Settings.

Future<void> _pump(WidgetTester tester, Widget page) async {
  // Tall enough that the list builds every topic.
  tester.view.physicalSize = const Size(800, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
}

void main() {
  testWidgets('the FAQ lists topics and expands an answer', (tester) async {
    await _pump(tester, const FaqPage());

    expect(find.text('FAQ'), findsOneWidget);
    expect(find.text('Getting started'), findsOneWidget);
    expect(find.text('Lessons on Google Meet'), findsOneWidget);
    expect(find.text('Rescheduling, cancelling and refunds'), findsOneWidget);

    const question = 'When can I book a lesson?';
    final answer = find.textContaining('at least 2 hours from now');
    expect(answer, findsNothing);
    await tester.tap(find.text(question));
    await tester.pumpAndSettle();
    expect(answer, findsOneWidget);
  });

  testWidgets('searching shows only matching questions, opened', (
    tester,
  ) async {
    await _pump(tester, const FaqPage());
    await tester.enterText(find.byKey(const ValueKey('faq-search')), 'refund');
    await tester.pumpAndSettle();

    expect(find.text('How do I cancel, and will I get a refund?'), findsOneWidget);
    expect(find.textContaining('100% back'), findsOneWidget); // expanded
    expect(find.text('How do I join my lesson?'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('faq-search')),
      'zzzz no match',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No questions match'), findsOneWidget);
  });

  testWidgets('the Tutors filter hides student-only questions', (
    tester,
  ) async {
    await _pump(tester, const FaqPage(initialAudience: FaqAudience.tutors));
    expect(find.text('How do I set up my Google Meet room?'), findsOneWidget);
    expect(find.text('How do I reschedule a lesson?'), findsNothing);
    expect(find.text('What is TheoTutoring?'), findsOneWidget); // everyone

    await tester.tap(find.text('Students'));
    await tester.pumpAndSettle();
    expect(find.text('How do I reschedule a lesson?'), findsOneWidget);
    expect(find.text('How do I set up my Google Meet room?'), findsNothing);
  });

  testWidgets('the Help Center shows the same FAQ', (tester) async {
    await _pump(tester, const HelpCenterPage());
    expect(find.text('Help Center'), findsOneWidget);
    expect(find.text('Frequently asked questions'), findsOneWidget);
    expect(find.text(faqContactEmail), findsOneWidget);
  });

  testWidgets('the Terms cover the current rules', (tester) async {
    await _pump(tester, const TermsAndConditionsPage());
    expect(
      find.text('Last updated: ${TermsAndConditionsPage.lastUpdated}'),
      findsOneWidget,
    );
    for (final title in [
      '6. Rescheduling',
      '7. Cancellations and Refunds',
      '9. Chat Rules and Moderation',
      '11. Suspension and Appeals',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.textContaining('100% if 48 hours or more'), findsOneWidget);
  });

  testWidgets('the Privacy Policy names every service and data type', (
    tester,
  ) async {
    await _pump(tester, const PrivacyPolicyPage());
    expect(
      find.text('Last updated: ${PrivacyPolicyPage.lastUpdated}'),
      findsOneWidget,
    );
    for (final text in [
      'Cloud Firestore',
      'Aiven',
      'Brevo',
      'Cloudinary',
      'identity document',
      'Available Now',
    ]) {
      expect(find.textContaining(text), findsWidgets, reason: text);
    }
    // The app has no push notifications
    expect(find.textContaining('Cloud Messaging'), findsNothing);
  });
}
