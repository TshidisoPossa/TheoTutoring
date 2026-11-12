class AdminSubject {
  final int subjectId;
  final String subjectName;

  const AdminSubject({required this.subjectId, required this.subjectName});

  factory AdminSubject.fromJson(Map<String, dynamic> json) {
    return AdminSubject(
      subjectId: (json['subjectId'] as num).toInt(),
      subjectName: (json['subjectName'] ?? '').toString(),
    );
  }
}

class AdminSubjectsResult {
  final List<AdminSubject> subjects;

  const AdminSubjectsResult({required this.subjects});

  factory AdminSubjectsResult.fromJson(Map<String, dynamic> json) {
    return AdminSubjectsResult(
      subjects: ((json['subjects'] as List<dynamic>?) ?? const [])
          .map((item) => AdminSubject.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
