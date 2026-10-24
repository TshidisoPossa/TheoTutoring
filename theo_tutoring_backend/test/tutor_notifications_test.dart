import 'package:test/test.dart';
import 'package:theo_tutoring_backend/notifications.dart';
import 'package:theo_tutoring_backend/tutor_notifications.dart';

void main() {
  group('bookedNotice', () {
    test('one lesson', () {
      final n = bookedNotice(
        purchaseId: 27,
        studentName: 'Lesego Mokoena',
        subject: 'Maths',
        lessons: [(bookingId: 41, date: '2026-10-27', startTime: '14:00')],
      );
      expect(n.id, 'booked-27');
      expect(n.type, NotificationType.bookingConfirmed);
      expect(n.title, 'New lesson booked');
      expect(
        n.body,
        'Lesego Mokoena booked a lesson in Maths for Tue 27 Oct, 14:00.',
      );
      expect(n.bookingId, 41);
    });

    test('several lessons open the first one', () {
      final n = bookedNotice(
        purchaseId: 28,
        studentName: 'Lesego Mokoena',
        subject: 'Maths',
        lessons: [
          (bookingId: 50, date: '2026-10-27', startTime: '14:00'),
          (bookingId: 51, date: '2026-11-03', startTime: '14:00'),
        ],
      );
      expect(
        n.body,
        'Lesego Mokoena booked 2 lessons in Maths, starting Tue 27 Oct, 14:00.',
      );
      expect(n.bookingId, 50);
    });
  });

  group('upcomingNotice', () {
    Notice upcoming(int minutesUntil, {int daysAway = 0}) =>
        upcomingNotice(
          bookingId: 41,
          studentName: 'Lesego',
          subject: 'Maths',
          startTime: '14:00',
          minutesUntil: minutesUntil,
          daysAway: daysAway,
        );

    test('within the hour it is the hour reminder', () {
      final n = upcoming(58);
      expect(n.id, 'upcoming-41-hour');
      expect(n.type, NotificationType.upcomingSession);
      expect(n.title, 'Upcoming lesson');
      expect(n.body, "You're tutoring Lesego in Maths in an hour.");
      expect(upcoming(60).id, 'upcoming-41-hour');
      expect(
        upcoming(20).body,
        "You're tutoring Lesego in Maths in 20 minutes.",
      );
      expect(upcoming(1).body, "You're tutoring Lesego in Maths in a minute.");
    });

    test('later today or tomorrow it is the day reminder', () {
      final today = upcoming(61);
      expect(today.id, 'upcoming-41-day');
      expect(today.body, "You're tutoring Lesego in Maths today at 14:00.");
      expect(
        upcoming(1300, daysAway: 1).body,
        "You're tutoring Lesego in Maths tomorrow at 14:00.",
      );
    });
  });

  group('reviewNotice', () {
    test('quotes the comment', () {
      final at = DateTime.utc(2026, 10, 20, 14, 8);
      final n = reviewNotice(
        reviewId: 12,
        studentName: 'Lerato Dube',
        rating: 5,
        subject: 'Maths',
        comment: '  Very patient.  ',
        bookingId: 41,
        createdAt: at,
      );
      expect(n.id, 'review-12');
      expect(n.type, NotificationType.newReview);
      expect(n.title, 'New review');
      expect(
        n.body,
        'Lerato Dube gave your Maths lesson 5 stars: “Very patient.”',
      );
      expect(n.bookingId, 41);
      expect(n.createdAt, at);
    });

    test('without a comment or subject', () {
      final n = reviewNotice(reviewId: 3, studentName: 'Sipho', rating: 1);
      expect(n.body, 'Sipho gave your lesson 1 star.');
    });

    test('cuts a long comment', () {
      final n = reviewNotice(
        reviewId: 4,
        studentName: 'Sipho',
        rating: 4,
        comment: 'a' * 200,
      );
      expect(n.body, 'Sipho gave your lesson 4 stars: “${'a' * 77}…”');
    });
  });
}
