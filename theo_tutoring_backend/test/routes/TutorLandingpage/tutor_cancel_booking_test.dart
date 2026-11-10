import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/booking_tutor.dart';
import 'package:theo_tutoring_backend/notifications.dart';
import 'package:theo_tutoring_backend/student_lessons.dart';
import 'package:theo_tutoring_backend/tutor_cancel_booking.dart';

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late List<http.Request> firestore;
  late bool firestoreFails;
  late List<(int, int, TutorCancelKind)> calls;

  setUp(() {
    firestore = [];
    firestoreFails = false;
    calls = [];
  });

  NotificationStore store() => NotificationStore(
    projectId: 'demo',
    accessToken: () async => 'token',
    client: MockClient((request) async {
      firestore.add(request);
      if (firestoreFails) return http.Response('down', 503);
      return http.Response(
        jsonEncode({
          'name':
              'projects/demo/databases/(default)/documents/'
              'notifications/u/items/n1',
          'fields': <String, dynamic>{},
        }),
        200,
      );
    }),
  );

  RequestContext contextFor(String method) {
    final context = _MockRequestContext();
    when(() => context.request).thenReturn(
      Request(
        method,
        Uri.parse('http://localhost/TutorLandingpage/bookings/110/cancel'),
      ),
    );
    when(() => context.read<NotificationStore>()).thenReturn(store());
    return context;
  }

  TutorCancellation booking({
    String? refund = '250.00',
    String? studentUid = 'student-uid',
  }) => (
    subjectId: 7,
    subject: 'Calculus',
    date: '2026-11-17', // a Tuesday
    startTime: '13:00',
    studentFirebaseUid: studentUid,
    refundAmount: refund,
  );

  Future<Response> send(
    TutorCancelKind kind, {
    String method = 'POST',
    String id = '110',
    TutorCancellation? result,
    Exception? error,
  }) => handleTutorCancelBooking(
    contextFor(method),
    id,
    tutorId: 3,
    kind: kind,
    cancel: (tutorId, bookingId, k) async {
      calls.add((tutorId, bookingId, k));
      if (error != null) throw error;
      return result ?? booking();
    },
    tutorName: (_) async => 'Thabo',
  );

  Map<String, dynamic> sentFields() =>
      (jsonDecode(firestore.single.body) as Map<String, dynamic>)['fields']
          as Map<String, dynamic>;

  test('only POST is allowed', () async {
    final response = await send(TutorCancelKind.cancel, method: 'GET');
    expect(response.statusCode, 405);
    expect(calls, isEmpty);
  });

  test('a bad booking id is a 400', () async {
    final response = await send(TutorCancelKind.cancel, id: 'abc');
    expect(response.statusCode, 400);
    expect(calls, isEmpty);
  });

  test('Cancel: cancels the session and tells the student', () async {
    final response = await send(TutorCancelKind.cancel);
    expect(response.statusCode, 200);
    expect(await response.json(), {
      'bookingId': 110,
      'status': 'Cancelled',
      'refundAmount': '250.00',
      'studentNotified': true,
    });
    expect(calls, [(3, 110, TutorCancelKind.cancel)]);

    expect(firestore.single.url.path, contains('notifications/student-uid'));
    final fields = sentFields();
    expect(fields['type'], {'stringValue': 'BookingCancelled'});
    expect(fields['title'], {'stringValue': 'Session cancelled'});
    expect(fields['body'], {
      'stringValue':
          'Thabo cancelled your Calculus session on Tue 17 Nov, 13:00. '
          'Your R 250.00 payment will be refunded in full.',
    });
    expect(fields['bookingId'], {'integerValue': '110'});
    // nothing to book again from a plain cancellation
    expect(fields.containsKey('tutorId'), isFalse);
  });

  test('Reschedule: asks the student to book again with this tutor', () async {
    final response = await send(TutorCancelKind.reschedule);
    expect(response.statusCode, 200);
    expect(calls, [(3, 110, TutorCancelKind.reschedule)]);

    final fields = sentFields();
    expect(fields['type'], {'stringValue': 'BookingRescheduled'});
    expect(fields['title'], {'stringValue': 'Session rescheduled'});
    expect(
      (fields['body'] as Map)['stringValue'],
      'Thabo needs to reschedule your Calculus session on Tue 17 Nov, '
      '13:00. Please book again at a time that suits you. '
      'Your R 250.00 payment will be refunded in full.',
    );
    // the "Book a new time" link
    expect(fields['tutorId'], {'integerValue': '3'});
    expect(fields['subjectId'], {'integerValue': '7'});
  });

  test('an unpaid session mentions no refund', () async {
    await send(TutorCancelKind.cancel, result: booking(refund: null));
    expect(
      (sentFields()['body'] as Map)['stringValue'],
      'Thabo cancelled your Calculus session on Tue 17 Nov, 13:00.',
    );
  });

  test('a session that cannot be cancelled returns its error', () async {
    final response = await send(
      TutorCancelKind.reschedule,
      error: const PostponeException(
        409,
        'This session has already started, so it cannot be rescheduled.',
      ),
    );
    expect(response.statusCode, 409);
    expect((await response.json() as Map)['error'], contains('started'));
    expect(firestore, isEmpty);
  });

  test('a database failure is a 500 and notifies nobody', () async {
    final response = await send(
      TutorCancelKind.cancel,
      error: Exception('db down'),
    );
    expect(response.statusCode, 500);
    expect(firestore, isEmpty);
  });

  test('Firestore failing does not undo the cancellation', () async {
    firestoreFails = true;
    final response = await send(TutorCancelKind.cancel);
    expect(response.statusCode, 200);
    expect((await response.json() as Map)['studentNotified'], isFalse);
  });

  test('a student without a Firebase account is not notified', () async {
    final response = await send(
      TutorCancelKind.cancel,
      result: booking(studentUid: null),
    );
    expect(response.statusCode, 200);
    expect((await response.json() as Map)['studentNotified'], isFalse);
    expect(firestore, isEmpty);
  });

  test('the cancellation reason the student sees', () {
    expect(
      tutorCancellationReason(TutorCancelKind.cancel),
      'Cancelled by your tutor.',
    );
    expect(
      tutorCancellationReason(TutorCancelKind.reschedule),
      'Your tutor asked to reschedule. Please book a new time.',
    );
  });

  test('refund amounts', () {
    expect(refundAmountOf('250.00', 100), '250.00');
    expect(refundAmountOf('250.00', 50), '125.00');
    expect(refundAmountOf('99.99', 50), '49.99');
    expect(refundAmountOf('300', 0), '0.00');
  });

  test('the notification JSON carries the booking link ids', () {
    final n = AppNotification(
      id: 'n1',
      type: NotificationType.bookingRescheduled,
      title: 'Session rescheduled',
      body: 'Please book again.',
      read: false,
      createdAt: DateTime.utc(2026, 11, 6),
      bookingId: 110,
      tutorId: 3,
      subjectId: 7,
    );
    final json = n.toJson(now: DateTime.utc(2026, 11, 6));
    expect(json['tutorId'], 3);
    expect(json['subjectId'], 7);

    final back = AppNotification.fromFirestore({
      'name': 'x/items/n1',
      'fields': n.toFirestoreFields(),
    });
    expect(back.tutorId, 3);
    expect(back.subjectId, 7);
  });
}
