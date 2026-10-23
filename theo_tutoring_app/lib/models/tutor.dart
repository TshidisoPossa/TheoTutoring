class TutorSubject {
  const TutorSubject({required this.subjectId, required this.subjectName});

  final int subjectId;
  final String subjectName;

  factory TutorSubject.fromJson(Map<String, dynamic> json) => TutorSubject(
    subjectId: _requiredInt(json['subjectId'], 'subjectId'),
    subjectName: _requiredString(json['subjectName'], 'subjectName'),
  );
}

class TutorSelection {
  const TutorSelection({required this.tutorId, required this.subjectId});

  final int tutorId;
  final int subjectId;
}

class Tutor {
  const Tutor({
    required this.tutorId,
    required this.name,
    required this.profilePhoto,
    required this.bio,
    required this.experience,
    required this.subjects,
    required this.hourlyRate,
    required this.averageRating,
    required this.reviewCount,
    this.qualification,
  });

  final int tutorId;
  final String name;
  final String? profilePhoto;
  final String? bio;
  final String? experience;
  final List<TutorSubject> subjects;
  final double? hourlyRate;
  final double? averageRating;
  final int reviewCount;

  /// The tutor's latest degree from registration (Qualification.Degree).
  final String? qualification;

  factory Tutor.fromJson(Map<String, dynamic> json) {
    final rawSubjects = json['subjects'];
    if (rawSubjects is! List) {
      throw const FormatException('Tutor subjects are invalid.');
    }
    return Tutor(
      tutorId: _requiredInt(json['tutorId'], 'tutorId'),
      name: _requiredString(json['name'], 'name'),
      profilePhoto: _nullableString(json['profilePhoto']),
      bio: _nullableString(json['bio']),
      experience: _nullableString(json['experience']),
      subjects: [
        for (final subject in rawSubjects)
          if (subject is Map<String, dynamic>)
            TutorSubject.fromJson(subject)
          else
            throw const FormatException('Tutor subject is invalid.'),
      ],
      hourlyRate: _nullableDouble(json['hourlyRate'], 'hourlyRate'),
      averageRating: _nullableDouble(json['averageRating'], 'averageRating'),
      reviewCount: _requiredInt(json['reviewCount'], 'reviewCount'),
      qualification: _nullableString(json['qualification']),
    );
  }
}

class TutorSearchPage {
  const TutorSearchPage({
    required this.tutors,
    required this.page,
    required this.limit,
    required this.total,
  });

  final List<Tutor> tutors;
  final int page;
  final int limit;
  final int total;

  factory TutorSearchPage.fromJson(Map<String, dynamic> json) {
    final rawTutors = json['tutors'];
    if (rawTutors is! List) {
      throw const FormatException('Tutor results are invalid.');
    }
    return TutorSearchPage(
      tutors: [
        for (final tutor in rawTutors)
          if (tutor is Map<String, dynamic>)
            Tutor.fromJson(tutor)
          else
            throw const FormatException('Tutor result is invalid.'),
      ],
      page: _requiredInt(json['page'], 'page'),
      limit: _requiredInt(json['limit'], 'limit'),
      total: _requiredInt(json['total'], 'total'),
    );
  }
}

int _requiredInt(Object? value, String field) {
  if (value is int) return value;
  if (value is num && value == value.toInt()) return value.toInt();
  throw FormatException('Tutor response field "$field" is invalid.');
}

String _requiredString(Object? value, String field) {
  if (value is String) return value;
  throw FormatException('Tutor response field "$field" is invalid.');
}

String? _nullableString(Object? value) {
  if (value == null || value is String) return value as String?;
  throw const FormatException('Tutor response contains invalid text.');
}

double? _nullableDouble(Object? value, String field) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw FormatException('Tutor response field "$field" is invalid.');
}
