import 'tutor.dart';

/// GET /tutors/{id}: the Tutor Profile page a student opens from search.
class TutorProfileDetails {
  const TutorProfileDetails({
    required this.tutor,
    required this.availableNow,
    required this.qualifications,
    required this.availability,
    required this.reviews,
  });

  /// The same fields as a search result.
  final Tutor tutor;

  /// The tutor is using the app right now.
  final bool availableNow;
  final List<TutorQualification> qualifications;
  final List<TutorAvailabilitySlot> availability;

  /// Newest first.
  final List<TutorReview> reviews;

  factory TutorProfileDetails.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) read) {
      final raw = json[key];
      if (raw is! List) {
        throw FormatException('Tutor profile field "$key" is invalid.');
      }
      return [
        for (final item in raw)
          if (item is Map<String, dynamic>)
            read(item)
          else
            throw FormatException('Tutor profile field "$key" is invalid.'),
      ];
    }

    return TutorProfileDetails(
      tutor: Tutor.fromJson(json),
      availableNow: json['availableNow'] == true,
      qualifications: list('qualifications', TutorQualification.fromJson),
      availability: list('availability', TutorAvailabilitySlot.fromJson),
      reviews: list('reviews', TutorReview.fromJson),
    );
  }
}

class TutorQualification {
  const TutorQualification({required this.degree, required this.institution});

  final String degree;
  final String institution;

  factory TutorQualification.fromJson(Map<String, dynamic> json) =>
      TutorQualification(
        degree: '${json['degree'] ?? ''}',
        institution: '${json['institution'] ?? ''}',
      );
}

/// One weekly slot, e.g. Monday 08:00-15:00.
class TutorAvailabilitySlot {
  const TutorAvailabilitySlot({
    required this.day,
    required this.startTime,
    required this.endTime,
  });

  /// "Monday" ... "Sunday".
  final String day;
  final String startTime;
  final String endTime;

  factory TutorAvailabilitySlot.fromJson(Map<String, dynamic> json) =>
      TutorAvailabilitySlot(
        day: '${json['day'] ?? ''}',
        startTime: '${json['startTime'] ?? ''}',
        endTime: '${json['endTime'] ?? ''}',
      );
}

class TutorReview {
  const TutorReview({
    required this.reviewId,
    required this.studentName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  final int reviewId;

  /// First name and surname initial, e.g. "Lerato M.".
  final String studentName;

  /// 1-5.
  final int rating;
  final String? comment;
  final DateTime? createdAt;

  factory TutorReview.fromJson(Map<String, dynamic> json) {
    final id = json['reviewId'];
    final rating = json['rating'];
    if (id is! int || rating is! int) {
      throw const FormatException('Tutor review is invalid.');
    }
    final comment = (json['comment'] as String?)?.trim();
    return TutorReview(
      reviewId: id,
      studentName: '${json['studentName'] ?? 'Student'}',
      rating: rating,
      comment: comment == null || comment.isEmpty ? null : comment,
      createdAt: DateTime.tryParse('${json['createdAt']}'),
    );
  }
}
