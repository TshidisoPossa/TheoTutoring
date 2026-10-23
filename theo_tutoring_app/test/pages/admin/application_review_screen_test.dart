import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Admin/application_review_screen.dart';
import 'package:theo_tutoring_app/Pages/Admin/models/Tutapplication.dart';

TutorApplication _application({
  String status = 'Pending',
  String? certificateUrl,
  String? idDocumentUrl,
  String? adminFeedback,
  String? reviewerName,
  String? reviewedAt,
}) => TutorApplication(
  id: '12',
  fullName: 'Tutor Example',
  photoUrl: null,
  status: status,
  appliedAt: DateTime(2026),
  qualifications: const ['BSc Mathematics - Example University'],
  subjects: const ['Mathematics'],
  email: 'tutor@example.test',
  adminFeedback: adminFeedback,
  reviewerName: reviewerName,
  reviewedAt: reviewedAt,
  certificateUrl: certificateUrl,
  idDocumentUrl: idDocumentUrl,
);

void main() {
  testWidgets('shows only document controls for stored URLs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminApplicationReviewScreen(
          application: _application(
            certificateUrl: 'https://files.test/cert.pdf',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('View Qualification certificate'), findsOneWidget);
    expect(find.text('Identity document: not provided'), findsOneWidget);
    expect(find.text('View Identity document'), findsNothing);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('hides decision actions after an application is reviewed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminApplicationReviewScreen(
          application: _application(
            status: 'Rejected',
            adminFeedback: 'Please add a clearer certificate.',
            reviewerName: 'Admin Example',
            reviewedAt: '2026-05-02 10:15:00',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Please add a clearer certificate.'),
      findsOneWidget,
    );
    expect(find.text('Reviewed by: Admin Example'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });
}
