// Expected backend (Dart Frog). Errors: non-2xx with { "message": "..." }

// POST   /admin/subjects          body { name, code, department, category }
// PUT    /admin/subjects/{id}     body { name, code, department, category }
// PATCH  /admin/subjects/{id}     body { isActive }
// DELETE /admin/subjects/{id}     (409 + message if tutors are linked)
// POST   /admin/subjects/bulk     body { ids, action: activate|deactivate|delete }

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int _int(dynamic v) => (_num(v) ?? 0).toInt();

bool _bool(dynamic v) {
  if (v is bool) return v;
  final s = v?.toString().toLowerCase();
  return s == '1' || s == 'true';
}

List<double> _trend(dynamic v) =>
    ((v ?? []) as List<dynamic>).map((e) => _num(e) ?? 0).toList();

class Subject {
  final String id;
  final String name;
  final String code;
  final String department;
  final String category;
  final int activeTutors;
  final double? avgRating;
  final bool isActive;

  const Subject({
    required this.id,
    required this.name,
    required this.code,
    required this.department,
    required this.category,
    required this.activeTutors,
    required this.avgRating,
    required this.isActive,
  });

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
    id: j['id'].toString(),
    name: (j['name'] ?? '').toString(),
    code: (j['code'] ?? '').toString(),
    department: (j['department'] ?? '').toString(),
    category: (j['category'] ?? '').toString(),
    activeTutors: _int(j['activeTutors']),
    avgRating: _num(j['avgRating']),
    isActive: _bool(j['isActive']),
  );
}

class SubjectInput {
  final String name;
  final String code;
  final String department;
  final String category;

  const SubjectInput({
    required this.name,
    required this.code,
    required this.department,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'code': code,
    'department': department,
    'category': category,
  };
}

class SubjectPage {
  final List<Subject> subjects;
  final int total;
  final List<String> categories;

  const SubjectPage({
    required this.subjects,
    required this.total,
    required this.categories,
  });

  factory SubjectPage.fromJson(Map<String, dynamic> j) => SubjectPage(
    subjects: ((j['subjects'] ?? []) as List<dynamic>)
        .map((e) => Subject.fromJson(e as Map<String, dynamic>))
        .toList(),
    total: _int(j['total']),
    categories: ((j['categories'] ?? []) as List<dynamic>)
        .map((e) => e.toString())
        .toList(),
  );
}

class SubjectSummary {
  final String adminName;
  final int totalSubjects;
  final double? totalSubjectsChange;
  final List<double> totalSubjectsTrend;
  final int activeTutors;
  final double? activeTutorsChange;
  final List<double> activeTutorsTrend;
  final double avgRating;
  final double? ratingTarget;
  final double? satisfaction;

  const SubjectSummary({
    required this.adminName,
    required this.totalSubjects,
    required this.totalSubjectsChange,
    required this.totalSubjectsTrend,
    required this.activeTutors,
    required this.activeTutorsChange,
    required this.activeTutorsTrend,
    required this.avgRating,
    required this.ratingTarget,
    required this.satisfaction,
  });

  factory SubjectSummary.fromJson(Map<String, dynamic> j) => SubjectSummary(
    adminName: (j['adminName'] ?? '').toString(),
    totalSubjects: _int(j['totalSubjects']),
    totalSubjectsChange: _num(j['totalSubjectsChange']),
    totalSubjectsTrend: _trend(j['totalSubjectsTrend']),
    activeTutors: _int(j['activeTutors']),
    activeTutorsChange: _num(j['activeTutorsChange']),
    activeTutorsTrend: _trend(j['activeTutorsTrend']),
    avgRating: _num(j['avgRating']) ?? 0,
    ratingTarget: _num(j['ratingTarget']),
    satisfaction: _num(j['satisfaction']),
  );
}
