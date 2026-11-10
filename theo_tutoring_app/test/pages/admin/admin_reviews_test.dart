import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_reviews_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_reviews.dart';

Map<String, dynamic> _review(
  int id,
  int rating, {
  String? comment,
  int reports = 0,
}) => {
  'reviewId': id,
  'rating': rating,
  'comment': comment,
  'bookingId': 40 + id,
  'createdAt': '2026-10-2${id}T16:08:19',
  'subject': 'Mathematics',
  'tutor': {'tutorId': 1, 'name': 'Thabo Mokoena', 'photoUrl': null},
  'student': {'studentId': 11, 'name': 'Jafta Ndlovu', 'photoUrl': null},
  'reportCount': reports,
};

/// In-memory stand-in for the /admin/reviews endpoints.
class _Backend {
  final requests = <http.Request>[];
  bool missingEndpoints = false;
  List<Map<String, dynamic>> reviews = [
    _review(1, 5, comment: 'Explained derivatives really clearly.'),
    _review(2, 2, comment: 'Arrived late.', reports: 1),
  ];

  late final client = MockClient((request) async {
    requests.add(request);
    expect(request.headers['Authorization'], 'Bearer admin-token');
    if (missingEndpoints) return http.Response('Route not found', 404);
    final segments = request.url.pathSegments;
    if (segments.length == 3) {
      return http.Response(
        jsonEncode({
          ..._review(2, 2, comment: 'Arrived late.', reports: 1),
          'tutor': {
            'tutorId': 1,
            'name': 'Thabo Mokoena',
            'email': 'thabo@example.com',
            'status': 'Active',
            'averageRating': 3.5,
            'reviewCount': 2,
          },
          'student': {
            'studentId': 11,
            'name': 'Jafta Ndlovu',
            'email': 'jafta@example.com',
            'institution': 'University of Pretoria',
          },
          'booking': {
            'bookingId': 42,
            'date': '2026-10-19',
            'startTime': '09:00',
            'endTime': '10:00',
            'status': 'Completed',
          },
          'highlights': ['Clear explanations', 'Patient with questions'],
          'privateNote': 'The tutor joined 30 minutes late.',
          'reports': [
            {
              'reportId': 5,
              'category': null,
              'reason': 'The tutor arrived 30 minutes late.',
              'status': 'Open',
              'createdAt': '2026-10-19T11:00:00',
              'reporterName': 'Jafta Ndlovu',
              'reporterRole': 'student',
            },
          ],
        }),
        200,
      );
    }
    return http.Response(
      jsonEncode({
        'adminName': 'Admin Tester',
        'total': reviews.length,
        'page': int.parse(request.url.queryParameters['page'] ?? '1'),
        'pageSize': 10,
        'summary': {
          'totalReviews': reviews.length,
          'averageRating': reviews.isEmpty ? 0 : 3.5,
          'lowRatingsLast30Days': reviews.isEmpty ? 0 : 1,
          'reviewsThisMonth': 0,
        },
        'distribution': {
          '5': reviews.isEmpty ? 0 : 1,
          '4': 0,
          '3': 0,
          '2': reviews.isEmpty ? 0 : 1,
          '1': 0,
        },
        'needsAttention': reviews.isEmpty
            ? []
            : [
                {
                  'tutorId': 3,
                  'name': 'Sipho Dlamini',
                  'photoUrl': null,
                  'status': 'Active',
                  'averageRating': 2.33,
                  'reviewCount': 3,
                },
              ],
        'reviews': reviews,
      }),
      200,
    );
  });

  AdminReviewsService service() => AdminReviewsService(
    client: client,
    tokenProvider: () async => 'admin-token',
  );

  Map<String, String> get lastListQuery => requests
      .lastWhere((r) => r.url.pathSegments.length == 2)
      .url
      .queryParameters;
}

Future<void> _pump(WidgetTester tester, _Backend backend) async {
  // Below the shell's 900px sidebar breakpoint (its fixed-width header
  // overflows with the wide Ahem test font, which real fonts do not).
  tester.view.physicalSize = const Size(880, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: AdminReviewsScreen(service: backend.service())),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the summary, breakdown, attention list and reviews', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    expect(find.text('Reviews'), findsWidgets);
    expect(find.text('Admin Tester'), findsOneWidget);
    expect(find.text('TOTAL REVIEWS'), findsOneWidget);
    expect(find.text('3.50'), findsOneWidget);
    expect(find.text('Rating breakdown'), findsOneWidget);
    expect(find.text('Sipho Dlamini'), findsOneWidget);
    expect(find.text('2.33'), findsOneWidget);
    expect(find.text('Explained derivatives really clearly.'), findsOneWidget);
    expect(find.text('Arrived late.'), findsOneWidget);
    // The reported lesson is flagged
    expect(find.byIcon(Icons.flag), findsOneWidget);
    expect(find.text('Showing 1–2 of 2 reviews'), findsOneWidget);
    expect(backend.lastListQuery['sort'], 'newest');
    expect(backend.lastListQuery['range'], 'all');
  });

  testWidgets('the star filter and breakdown rows filter by rating', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await tester.tap(find.text('2★').first);
    await tester.pumpAndSettle();
    expect(backend.lastListQuery['rating'], '2');
    expect(backend.lastListQuery['page'], '1');

    await tester.tap(find.byKey(const ValueKey('breakdown-5')));
    await tester.pumpAndSettle();
    expect(backend.lastListQuery['rating'], '5');

    // Tapping the selected row again clears the filter
    await tester.tap(find.byKey(const ValueKey('breakdown-5')));
    await tester.pumpAndSettle();
    expect(backend.lastListQuery.containsKey('rating'), isFalse);
  });

  testWidgets('"With a comment" and search are sent to the backend', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    await tester.tap(find.text('With a comment'));
    await tester.pumpAndSettle();
    expect(backend.lastListQuery['withComment'], 'true');

    await tester.enterText(
      find.widgetWithText(TextField, 'Search tutor, student or subject...'),
      'Thabo',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(backend.lastListQuery['search'], 'Thabo');
  });

  testWidgets('opening a review shows the lesson, people and reports', (
    tester,
  ) async {
    final backend = _Backend();
    await _pump(tester, backend);

    final view = find.byTooltip('View review').at(1);
    await tester.ensureVisible(view);
    await tester.pumpAndSettle();
    await tester.tap(view);
    await tester.pumpAndSettle();

    expect(find.text('Review #2'), findsOneWidget);
    expect(find.text('19 Oct 2026, 09:00–10:00'), findsOneWidget);
    expect(find.text('thabo@example.com'), findsOneWidget);
    expect(find.text('3.50★ from 2 reviews'), findsOneWidget);
    expect(find.text('University of Pretoria'), findsOneWidget);
    expect(find.text('Reports on this lesson (1)'), findsOneWidget);
    expect(find.text('The tutor arrived 30 minutes late.'), findsOneWidget);
    // The badges and private note from the Leave a Review page (admin only)
    expect(find.text('What made it great'), findsOneWidget);
    expect(find.text('Clear explanations'), findsOneWidget);
    expect(find.text('Patient with questions'), findsOneWidget);
    expect(find.text('The tutor joined 30 minutes late.'), findsOneWidget);
    expect(
      find.textContaining('the tutor cannot see this'),
      findsOneWidget,
    );
    expect(backend.requests.last.url.path, endsWith('/admin/reviews/2'));
    // Read-only: no way to edit or delete the review
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Hide'), findsNothing);
  });

  testWidgets('shows an empty state when there are no reviews', (tester) async {
    final backend = _Backend()..reviews = [];
    await _pump(tester, backend);

    expect(find.text('No reviews yet'), findsOneWidget);
    expect(find.text('No tutors need attention right now.'), findsOneWidget);
  });

  testWidgets('shows a clear state when the backend has no review API', (
    tester,
  ) async {
    final backend = _Backend()..missingEndpoints = true;
    await _pump(tester, backend);

    expect(find.text('Reviews are not available yet.'), findsOneWidget);
    expect(find.text('TOTAL REVIEWS'), findsNothing);
  });
}
