import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/admin_reports.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/tutor_account_status.dart';
import 'package:theo_tutoring_backend/tutor_reports.dart';

import '../../../routes/admin/reports/index.dart' as admin_route;

// Report a Problem (tutor) and GET /admin/reports, with fake storage.

class _MockRequestContext extends Mock implements RequestContext {}

class _FakeTutorReports implements TutorReportRepository {
  final filed = <Map<String, Object?>>[];
  TutorReportException? refuse;

  @override
  Future<List<ReportableStudent>> studentsOf(int tutorId) async => [
    (userId: 15, name: 'Dumisani Khumalo', photo: null),
    (userId: 22, name: 'Lerato Dube', photo: 'https://example.com/l.png'),
  ];

  @override
  Future<int> file({
    required int tutorId,
    required String category,
    required String description,
    int? studentUserId,
  }) async {
    final error = refuse;
    if (error != null) throw error;
    filed.add({
      'tutorId': tutorId,
      'category': category,
      'description': description,
      'studentUserId': studentUserId,
    });
    return filed.length;
  }
}

class _FakeAdminReports implements AdminReportRepository {
  Map<String, Object?>? asked;

  @override
  Future<Map<String, Object?>> list({
    required int page,
    required int pageSize,
    String? status,
    String? category,
  }) async {
    asked = {
      'status': status,
      'category': category,
      'page': page,
      'pageSize': pageSize,
    };
    return {'total': 0, 'page': page, 'pageSize': pageSize, 'reports': []};
  }
}

RequestContext _request(
  String method, {
  String url = 'http://localhost/TutorLandingpage/reports',
  Object? body,
}) {
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(
    Request(
      method,
      Uri.parse(url),
      headers: {'Authorization': 'Bearer test'},
      body: body == null ? null : jsonEncode(body),
    ),
  );
  return context;
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.body()) as Map<String, dynamic>;

AdminResolver _as(String role) =>
    (_) async => AdminIdentity(id: 1, name: 'Ada', roleKey: role);

void main() {
  group('POST /TutorLandingpage/reports', () {
    late _FakeTutorReports repo;
    setUp(() => repo = _FakeTutorReports());

    Future<Response> send(Object? body) => handleFileTutorReport(
      _request('POST', body: body),
      tutorId: 7,
      repository: repo,
    );

    test('a Payments & Payouts report is saved without a student', () async {
      final response = await send({
        'category': 'Payments & Payouts',
        'description': '  My payout for October has not arrived.  ',
        'studentUserId': 15, // ignored: not a student report
      });

      expect(response.statusCode, 200);
      expect((await _json(response))['reportId'], 1);
      expect(repo.filed.single, {
        'tutorId': 7,
        'category': 'Payments & Payouts',
        'description': 'My payout for October has not arrived.',
        'studentUserId': null,
      });
    });

    test('a Student issues report names the student', () async {
      final response = await send({
        'category': 'Student issues',
        'description': 'The student was rude during our lesson.',
        'studentUserId': 15,
      });
      expect(response.statusCode, 200);
      expect(repo.filed.single['studentUserId'], 15);
    });

    test('Student issues without a student is refused', () async {
      final response = await send({
        'category': 'Student issues',
        'description': 'The student was rude during our lesson.',
      });
      expect(response.statusCode, 400);
      expect((await _json(response))['error'], contains('student'));
      expect(repo.filed, isEmpty);
    });

    test('an unknown category or short description is refused', () async {
      for (final body in [
        {'category': 'Spam', 'description': 'Something went wrong here.'},
        {'description': 'Something went wrong here.'},
        {'category': 'Other', 'description': 'Too short'},
        {'category': 'Other'},
        {'category': 'Other', 'description': 'x' * 1001},
      ]) {
        expect((await send(body)).statusCode, 400, reason: '$body');
      }
      expect(repo.filed, isEmpty);
    });

    test('the repository refusal is passed on to the tutor', () async {
      repo.refuse = const TutorReportException(
        409,
        'You have already reported this student.',
      );
      final response = await send({
        'category': 'Student issues',
        'description': 'The student was rude during our lesson.',
        'studentUserId': 15,
      });
      expect(response.statusCode, 409);
      expect(
        (await _json(response))['error'],
        'You have already reported this student.',
      );
    });

    test('only POST is allowed', () async {
      final response = await handleFileTutorReport(
        _request('GET'),
        tutorId: 7,
        repository: repo,
      );
      expect(response.statusCode, 405);
    });
  });

  group('GET /TutorLandingpage/reports/students', () {
    test('lists the students who booked the tutor', () async {
      final response = await handleReportableStudents(
        _request(
          'GET',
          url: 'http://localhost/TutorLandingpage/reports/students',
        ),
        tutorId: 7,
        repository: _FakeTutorReports(),
      );
      expect(response.statusCode, 200);
      expect(await _json(response), {
        'students': [
          {'userId': 15, 'name': 'Dumisani Khumalo', 'photo': null},
          {
            'userId': 22,
            'name': 'Lerato Dube',
            'photo': 'https://example.com/l.png',
          },
        ],
      });
    });
  });

  test('Pending tutors may send reports from their Profile', () {
    final uri = Uri.parse('http://localhost/TutorLandingpage/reports');
    expect(canAccessTutorRoute('Pending', uri), isTrue);
    expect(canAccessTutorRoute('Active', uri), isTrue);
    expect(canAccessTutorRoute('Suspended', uri), isFalse);
  });

  group('GET /admin/reports', () {
    test('support admins read the reports with filters', () async {
      final repo = _FakeAdminReports();
      final response = await admin_route.handleAdminReports(
        _request(
          'GET',
          url:
              'http://localhost/admin/reports?status=open'
              '&category=Student%20issues&page=2&pageSize=10',
        ),
        adminResolver: _as('support_admin'),
        repository: repo,
      );
      expect(response.statusCode, 200);
      expect(repo.asked, {
        'status': 'Open',
        'category': 'Student issues',
        'page': 2,
        'pageSize': 10,
      });
      expect((await _json(response))['adminName'], 'Ada');
    });

    test('admins without admin.reports.read are refused', () async {
      final repo = _FakeAdminReports();
      final response = await admin_route.handleAdminReports(
        _request('GET', url: 'http://localhost/admin/reports'),
        adminResolver: _as('application_reviewer'),
        repository: repo,
      );
      expect(response.statusCode, HttpStatus.forbidden);
      expect(repo.asked, isNull);
    });

    test('a bad token is 401', () async {
      final response = await admin_route.handleAdminReports(
        _request('GET', url: 'http://localhost/admin/reports'),
        adminResolver: (_) async =>
            throw const AuthTokenException('Invalid sign-in token.'),
        repository: _FakeAdminReports(),
      );
      expect(response.statusCode, 401);
    });

    test('unknown filters are refused', () async {
      for (final query in ['status=lost', 'category=Spam', 'pageSize=500']) {
        final response = await admin_route.handleAdminReports(
          _request('GET', url: 'http://localhost/admin/reports?$query'),
          adminResolver: _as('super_admin'),
          repository: _FakeAdminReports(),
        );
        expect(response.statusCode, 400, reason: query);
      }
    });
  });
}
