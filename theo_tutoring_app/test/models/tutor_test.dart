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
    // Absent from older backends: stays null rather than a guessed ID.
    expect(tutor.userId, isNull);
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

  Map<String, dynamic> withUserId(Object? userId) => {
    'tutorId': 12,
    'userId': userId,
    'name': 'Example Tutor',
    'profilePhoto': null,
    'bio': null,
    'experience': null,
    'hourlyRate': null,
    'averageRating': null,
    'reviewCount': 0,
    'subjects': [],
  };

  test('parses the tutor User ID separately from tutorId', () {
    final tutor = Tutor.fromJson(withUserId(42));
    expect(tutor.userId, 42);
    expect(tutor.tutorId, 12);
  });

  test('rejects a malformed userId instead of inventing one', () {
    for (final bad in <Object>['42', 'unknown', 4.5, true]) {
      expect(
        () => Tutor.fromJson(withUserId(bad)),
        throwsFormatException,
        reason: 'userId: $bad',
      );
    }
  });
}
