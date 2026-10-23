import 'package:test/test.dart';
import 'package:theo_tutoring_backend/student_lessons.dart';

void main() {
  group('refundPercentFor (documentation 4.6)', () {
    test('48 hours or more is a full refund', () {
      expect(refundPercentFor(48 * 60), 100);
      expect(refundPercentFor(7 * 24 * 60), 100);
    });

    test('24 hours or more, but less than 48, is half', () {
      expect(refundPercentFor(24 * 60), 50);
      expect(refundPercentFor(48 * 60 - 1), 50);
    });

    test('less than 24 hours is no refund', () {
      expect(refundPercentFor(24 * 60 - 1), 0);
      expect(refundPercentFor(1), 0);
    });
  });
}
