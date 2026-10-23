import 'package:test/test.dart';
import 'package:theo_tutoring_backend/tutor_presence.dart';
import 'package:theo_tutoring_backend/tutor_public_profile.dart';

void main() {
  group('reviewerName', () {
    test('first name and surname initial', () {
      expect(reviewerName('Lerato Mokoena'), 'Lerato M.');
      expect(reviewerName('  sipho  van  khumalo '), 'sipho K.');
    });

    test('single or missing names', () {
      expect(reviewerName('Dumisani'), 'Dumisani');
      expect(reviewerName(''), 'Student');
      expect(reviewerName(null), 'Student');
    });
  });

  test('available now uses the presence window', () {
    expect(
      tutorAvailableNowSql('tp'),
      contains('INTERVAL $tutorOnlineWindowMinutes MINUTE'),
    );
  });
}
