import 'package:intl/intl.dart';

// Backend contract (Dart Frog, lib/admin_reviews.dart). Read-only.
//
// GET /admin/reviews?search=&rating=1-5&range=all|7d|30d|90d
//     &withComment=true&sort=newest|oldest|lowest|highest&page=&pageSize=
//   { adminName, total, page, pageSize,
//     summary: { totalReviews, averageRating, lowRatingsLast30Days,
//                reviewsThisMonth },
//     distribution: { "5": n, ... "1": n },
//     needsAttention: [ { tutorId, name, photoUrl, status, averageRating,
//                         reviewCount } ],
//     reviews: [ { reviewId, rating, comment, bookingId, createdAt, subject,
//                  tutor: {tutorId, name, photoUrl},
//                  student: {studentId, name, photoUrl}, reportCount } ] }
//
// GET /admin/reviews/{id}
//   the review plus tutor {email, status, averageRating, reviewCount},
//   student {email, institution}, booking {bookingId, date, startTime,
//   endTime, status} and reports [ {reportId, category, reason, status,
//   createdAt, reporterName, reporterRole} ].

String? _text(dynamic v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

double _num(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

Map<String, dynamic> _map(dynamic v) =>
    v is Map<String, dynamic> ? v : const <String, dynamic>{};

final _dateFormat = DateFormat('d MMM yyyy');

/// "Lerato Dube" -> "LD"
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
  return letters.isEmpty ? '?' : letters;
}

/// A tutor or student shown with a review.
class ReviewPerson {
  const ReviewPerson({
    required this.id,
    required this.name,
    this.photoUrl,
    this.email,
    this.status,
    this.institution,
    this.averageRating,
    this.reviewCount,
  });

  factory ReviewPerson.fromJson(Map<String, dynamic> j, String idKey) =>
      ReviewPerson(
        id: _int(j[idKey]),
        name: _text(j['name']) ?? 'Unknown',
        photoUrl: _text(j['photoUrl']),
        email: _text(j['email']),
        status: _text(j['status']),
        institution: _text(j['institution']),
        averageRating: j['averageRating'] == null
            ? null
            : _num(j['averageRating']),
        reviewCount: j['reviewCount'] == null ? null : _int(j['reviewCount']),
      );

  final int id;
  final String name;
  final String? photoUrl;

  // Only in the details response
  final String? email;
  final String? status;
  final String? institution;
  final double? averageRating;
  final int? reviewCount;

  String get initials => initialsOf(name);
}

/// A report filed on the same booking as a review.
class ReviewReport {
  const ReviewReport({
    required this.reportId,
    required this.reason,
    required this.status,
    this.category,
    this.createdAt,
    this.reporterName,
    this.reporterRole,
  });

  factory ReviewReport.fromJson(Map<String, dynamic> j) => ReviewReport(
    reportId: _int(j['reportId']),
    reason: _text(j['reason']) ?? '',
    status: _text(j['status']) ?? 'Open',
    category: _text(j['category']),
    createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}'),
    reporterName: _text(j['reporterName']),
    reporterRole: _text(j['reporterRole']),
  );

  final int reportId;
  final String reason;

  /// Open, Under review or Resolved.
  final String status;
  final String? category;
  final DateTime? createdAt;
  final String? reporterName;

  /// student or tutor.
  final String? reporterRole;
}

/// The lesson a review is about.
class ReviewBooking {
  const ReviewBooking({
    required this.bookingId,
    this.date,
    this.startTime,
    this.endTime,
    this.status,
  });

  factory ReviewBooking.fromJson(Map<String, dynamic> j) => ReviewBooking(
    bookingId: _int(j['bookingId']),
    date: DateTime.tryParse('${j['date'] ?? ''}'),
    startTime: _text(j['startTime']),
    endTime: _text(j['endTime']),
    status: _text(j['status']),
  );

  final int bookingId;
  final DateTime? date;
  final String? startTime;
  final String? endTime;
  final String? status;

  /// "19 Oct 2026, 09:00–10:00"
  String get label {
    final day = date == null ? 'Unknown date' : _dateFormat.format(date!);
    if (startTime == null) return day;
    return endTime == null ? '$day, $startTime' : '$day, $startTime–$endTime';
  }
}

class AdminReview {
  const AdminReview({
    required this.reviewId,
    required this.rating,
    required this.tutor,
    required this.student,
    this.comment,
    this.bookingId,
    this.createdAt,
    this.subject,
    this.reportCount = 0,
    this.booking,
    this.reports = const [],
    this.highlights = const [],
    this.privateNote,
  });

  factory AdminReview.fromJson(Map<String, dynamic> j) => AdminReview(
    reviewId: _int(j['reviewId']),
    rating: _int(j['rating']).clamp(0, 5),
    comment: _text(j['comment']),
    bookingId: j['bookingId'] == null ? null : _int(j['bookingId']),
    createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}'),
    subject: _text(j['subject']),
    tutor: ReviewPerson.fromJson(_map(j['tutor']), 'tutorId'),
    student: ReviewPerson.fromJson(_map(j['student']), 'studentId'),
    reportCount: _int(j['reportCount']),
    booking: j['booking'] is Map<String, dynamic>
        ? ReviewBooking.fromJson(j['booking'] as Map<String, dynamic>)
        : null,
    reports: [
      for (final r in (j['reports'] as List?) ?? const [])
        if (r is Map<String, dynamic>) ReviewReport.fromJson(r),
    ],
    highlights: [
      for (final h in (j['highlights'] as List?) ?? const [])
        if (h is String && h.trim().isNotEmpty) h.trim(),
    ],
    privateNote: _text(j['privateNote']),
  );

  final int reviewId;

  /// 1-5 stars.
  final int rating;
  final String? comment;
  final int? bookingId;
  final DateTime? createdAt;
  final String? subject;
  final ReviewPerson tutor;
  final ReviewPerson student;

  /// Reports filed on the same booking.
  final int reportCount;

  // Only in the details response
  final ReviewBooking? booking;
  final List<ReviewReport> reports;

  /// Badges the student tapped ("Clear explanations", ...); admin only.
  final List<String> highlights;

  /// The student's private note for platform support; admin only.
  final String? privateNote;

  String get dateLabel =>
      createdAt == null ? '—' : _dateFormat.format(createdAt!);
}

class ReviewSummary {
  const ReviewSummary({
    this.totalReviews = 0,
    this.averageRating = 0,
    this.lowRatingsLast30Days = 0,
    this.reviewsThisMonth = 0,
  });

  factory ReviewSummary.fromJson(Map<String, dynamic> j) => ReviewSummary(
    totalReviews: _int(j['totalReviews']),
    averageRating: _num(j['averageRating']),
    lowRatingsLast30Days: _int(j['lowRatingsLast30Days']),
    reviewsThisMonth: _int(j['reviewsThisMonth']),
  );

  final int totalReviews;
  final double averageRating;

  /// 1-2 star reviews in the last 30 days.
  final int lowRatingsLast30Days;
  final int reviewsThisMonth;
}

/// A tutor averaging below 3 stars over at least 3 reviews.
class TutorNeedingAttention {
  const TutorNeedingAttention({
    required this.tutorId,
    required this.name,
    required this.averageRating,
    required this.reviewCount,
    this.photoUrl,
    this.status,
  });

  factory TutorNeedingAttention.fromJson(Map<String, dynamic> j) =>
      TutorNeedingAttention(
        tutorId: _int(j['tutorId']),
        name: _text(j['name']) ?? 'Unknown tutor',
        averageRating: _num(j['averageRating']),
        reviewCount: _int(j['reviewCount']),
        photoUrl: _text(j['photoUrl']),
        status: _text(j['status']),
      );

  final int tutorId;
  final String name;
  final double averageRating;
  final int reviewCount;
  final String? photoUrl;

  /// User.AccountStatus, e.g. Active or Suspended.
  final String? status;

  String get initials => initialsOf(name);
}

class AdminReviewsPage {
  const AdminReviewsPage({
    required this.reviews,
    required this.summary,
    required this.distribution,
    required this.needsAttention,
    required this.total,
    required this.page,
    required this.pageSize,
    this.adminName,
  });

  factory AdminReviewsPage.fromJson(Map<String, dynamic> j) {
    final distribution = _map(j['distribution']);
    return AdminReviewsPage(
      adminName: _text(j['adminName']),
      reviews: [
        for (final r in (j['reviews'] as List?) ?? const [])
          if (r is Map<String, dynamic>) AdminReview.fromJson(r),
      ],
      summary: ReviewSummary.fromJson(_map(j['summary'])),
      distribution: {
        for (var stars = 5; stars >= 1; stars--)
          stars: _int(distribution['$stars']),
      },
      needsAttention: [
        for (final t in (j['needsAttention'] as List?) ?? const [])
          if (t is Map<String, dynamic>) TutorNeedingAttention.fromJson(t),
      ],
      total: _int(j['total']),
      page: _int(j['page']) < 1 ? 1 : _int(j['page']),
      pageSize: _int(j['pageSize']) < 1 ? 10 : _int(j['pageSize']),
    );
  }

  final String? adminName;
  final List<AdminReview> reviews;
  final ReviewSummary summary;

  /// Stars (5..1) -> number of reviews.
  final Map<int, int> distribution;
  final List<TutorNeedingAttention> needsAttention;
  final int total;
  final int page;
  final int pageSize;

  int get pageCount => total == 0 ? 1 : (total / pageSize).ceil();
}
