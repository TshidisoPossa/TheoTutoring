import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/models/tutor.dart';

void main() {
  test('parses real IDs while preserving nullable profile and review data', () {
    final tutor = Tutor.fromJson({
      'tutorId': 12,
      'name': 'Example Tutor',
      'profilePhoto': null,
      'bio': null,
      'experience': null,
      'hourlyRate': null,
      'averageRating': null,
      'reviewCount': 0,
      'subjects': [
        {'subjectId': 5, 'subjectName': 'Physics'},
      ],
    });

    expect(tutor.tutorId, 12);
    expect(tutor.profilePhoto, isNull);
    expect(tutor.averageRating, isNull);
    expect(tutor.reviewCount, 0);
    expect(tutor.subjects.single.subjectId, 5);
  });

  test('rejects malformed IDs instead of inventing defaults', () {
    expect(
      () => Tutor.fromJson({
        'tutorId': 'unknown',
        'name': 'Example Tutor',
        'profilePhoto': null,
        'bio': null,
        'experience': null,
        'hourlyRate': null,
        'averageRating': null,
        'reviewCount': 0,
        'subjects': [],
      }),
      throwsFormatException,
    );
  });
}
