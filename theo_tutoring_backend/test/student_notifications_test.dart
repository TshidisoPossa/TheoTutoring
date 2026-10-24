import 'package:test/test.dart';
import 'package:theo_tutoring_backend/notifications.dart';
import 'package:theo_tutoring_backend/student_notifications.dart';

void main() {
  test('rands formats money', () {
    expect(rands('250'), 'R250.00');
    expect(rands('125.5'), 'R125.50');
    expect(rands(null), 'R0.00');
  });

  group('paidNotice', () {
    test('one lesson', () {
      final n = paidNotice(
        purchaseId: 27,
        tutorName: 'Thabo Mokoena',
        subject: 'Maths',
        amount: '250.00',
        lessons: [(bookingId: 41, date: '2026-10-27', startTime: '14:00')],
      );
      expect(n.id, 'paid-27');
      expect(n.type, NotificationType.paymentReceived);
      expect(n.title, 'Payment successful');
      expect(
        n.body,
        'Your payment of R250.00 went through. Your Maths lesson with Thabo '
        'Mokoena on Tue 27 Oct, 14:00 is confirmed.',
      );
      expect(n.bookingId, 41);
    });

    test('several lessons', () {
      final n = paidNotice(
        purchaseId: 28,
        tutorName: 'Thabo Mokoena',
        subject: 'Maths',
        amount: '900',
        lessons: [
          (bookingId: 50, date: '2026-10-27', startTime: '14:00'),
          (bookingId: 51, date: '2026-11-03', startTime: '14:00'),
        ],
      );
      expect(
        n.body,
        'Your payment of R900.00 went through. Your 2 Maths lessons with '
        'Thabo Mokoena are confirmed, starting Tue 27 Oct, 14:00.',
      );
      expect(n.bookingId, 50);
    });
  });

  group('studentUpcomingNotice', () {
    Notice upcoming(int minutesUntil, {int daysAway = 0}) =>
        studentUpcomingNotice(
          bookingId: 41,
          tutorName: 'Theophilus Nkhabu',
          subject: 'Maths',
          startTime: '14:00',
          minutesUntil: minutesUntil,
          daysAway: daysAway,
        );

    test('within the hour', () {
      final n = upcoming(55);
      expect(n.id, 'upcoming-41-hour');
      expect(n.type, NotificationType.upcomingSession);
      expect(n.title, 'Upcoming lesson');
      expect(
        n.body,
        'Your Maths lesson with Theophilus Nkhabu starts in an hour.',
      );
    });

    test('later today or tomorrow', () {
      expect(upcoming(200).id, 'upcoming-41-day');
      expect(
        upcoming(200).body,
        'Your Maths lesson with Theophilus Nkhabu is today at 14:00.',
      );
      expect(
        upcoming(1300, daysAway: 1).body,
        'Your Maths lesson with Theophilus Nkhabu is tomorrow at 14:00.',
      );
    });
  });

  group('refundNotice', () {
    Notice refund({
      required bool approved,
      String? amount,
      String? percentage,
      String? reason,
    }) => refundNotice(
      refundId: 9,
      approved: approved,
      bookingId: 41,
      subject: 'Maths',
      tutorName: 'Thabo Mokoena',
      date: '2026-10-27',
      startTime: '14:00',
      amount: amount,
      percentage: percentage,
      reason: reason,
    );

    test('approved with money back', () {
      final n = refund(approved: true, amount: '125.00', percentage: '50.00');
      expect(n.id, 'refund-9');
      expect(n.type, NotificationType.refundApproved);
      expect(n.title, 'Refund approved');
      expect(
        n.body,
        'Your refund of R125.00 (50%) for the Maths lesson with Thabo Mokoena '
        'on Tue 27 Oct, 14:00 was approved.',
      );
      expect(n.bookingId, 41);
    });

    test('approved but nothing is due', () {
      final n = refund(approved: true, amount: '0.00', percentage: '0.00');
      expect(n.body, endsWith('no money is due back.'));
    });

    test('declined with the reason', () {
      final n = refund(approved: false, reason: 'Cancelled after the lesson');
      expect(n.type, NotificationType.refundDenied);
      expect(n.title, 'Refund declined');
      expect(
        n.body,
        'Your refund for the Maths lesson with Thabo Mokoena on Tue 27 Oct, '
        '14:00 was declined. Reason: Cancelled after the lesson',
      );
    });
  });
}
