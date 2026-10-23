import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_applications.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

import '../../../routes/admin/applications/index.dart' as admin_route;
import '../../../routes/admin/applications/review.dart' as review_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

class _TestApplicationsRepository implements AdminApplicationsRepository {
  int? reviewedId;
  String? reviewedDecision;
  String? reviewedFeedback;
  AdminIdentity? reviewer;

  @override
  Future<List<Map<String, Object?>>> fetchApplications() async => [
    {
      'id': 12,
      'fullName': 'Tutor Example',
      'email': 'tutor@example.test',
      'phone': '0123456789',
      'photoUrl': null,
      'status': 'Pending',
      'accountStatus': 'Pending',
      'appliedAt': '2026-05-01 09:30:00',
      'adminFeedback': null,
      'bio': 'Mathematics tutor',
      'experience': '3 years',
      'qualifications': ['BSc Mathematics — Example University'],
      'subjects': ['Mathematics'],
      'certificateUrl': 'https://example.test/certificate.pdf',
      'idDocumentUrl': 'https://example.test/id.png',
    },
  ];

  @override
  Future<void> reviewApplication({
    required int applicationId,
    required String decision,
    required String? feedback,
    required AdminIdentity admin,
  }) async {
    reviewedId = applicationId;
    reviewedDecision = decision;
    reviewedFeedback = feedback;
    reviewer = admin;
  }
}

void main() {
  late RequestContext context;
  late Request request;

  setUp(() {
    context = _MockRequestContext();
    request = _MockRequest();
    when(() => context.request).thenReturn(request);
    when(() => request.method).thenReturn(HttpMethod.get);
    when(() => request.headers).thenReturn({'Authorization': 'Bearer test'});
  });

  test('returns the application payload for an authorized admin', () async {
    final response = await admin_route.handleAdminApplications(
      context,
      adminResolver: (authorization) async {
        expect(authorization, 'Bearer test');
        return const AdminIdentity(id: 7, name: 'Admin Example');
      },
      repositoryFactory: _TestApplicationsRepository.new,
    );

    expect(response.statusCode, HttpStatus.ok);
    final body = jsonDecode(await response.body()) as Map<String, dynamic>;
    expect(body['adminName'], 'Admin Example');
    final application = (body['applications'] as List).single;
    expect(application['status'], 'Pending');
    expect(application['qualifications'], [
      'BSc Mathematics — Example University',
    ]);
    expect(application['subjects'], ['Mathematics']);
    expect(
      application['certificateUrl'],
      'https://example.test/certificate.pdf',
    );
    expect(application['idDocumentUrl'], 'https://example.test/id.png');
    expect(application.containsKey('qualificationDocumentUrl'), isFalse);
  });

  test(
    'returns 401 for invalid authentication and 403 for non-admins',
    () async {
      final unauthorized = await admin_route.handleAdminApplications(
        context,
        adminResolver: (_) =>
            throw const AuthTokenException('Sign in required.'),
        repositoryFactory: _TestApplicationsRepository.new,
      );
      final forbidden = await admin_route.handleAdminApplications(
        context,
        adminResolver: (_) => throw const AdminAccessDenied(
          'Administrator access is required.',
        ),
        repositoryFactory: _TestApplicationsRepository.new,
      );

      expect(unauthorized.statusCode, HttpStatus.unauthorized);
      expect(forbidden.statusCode, HttpStatus.forbidden);
    },
  );

  test('rejects other methods without resolving admin identity', () async {
    when(() => request.method).thenReturn(HttpMethod.post);
    var resolved = false;
    final response = await admin_route.handleAdminApplications(
      context,
      adminResolver: (_) async {
        resolved = true;
        return const AdminIdentity(id: 7, name: 'Admin Example');
      },
      repositoryFactory: _TestApplicationsRepository.new,
    );

    expect(response.statusCode, HttpStatus.methodNotAllowed);
    expect(resolved, isFalse);
  });

  test('records an authorized approval with reviewer identity', () async {
    final repository = _TestApplicationsRepository();
    when(() => request.method).thenReturn(HttpMethod.post);
    when(() => request.json()).thenAnswer(
      (_) async => {'applicationId': '12', 'decision': 'approve'},
    );
    final response = await review_route.handleApplicationReview(
      context,
      adminResolver: (_) async =>
          const AdminIdentity(id: 7, name: 'Admin Example'),
      repositoryFactory: () => repository,
    );
    expect(response.statusCode, HttpStatus.ok);
    expect(repository.reviewedId, 12);
    expect(repository.reviewedDecision, 'approve');
    expect(repository.reviewedFeedback, isNull);
    expect(repository.reviewer?.id, 7);
  });

  test(
    'records rejection feedback through the protected review route',
    () async {
      final repository = _TestApplicationsRepository();
      when(() => request.method).thenReturn(HttpMethod.post);
      when(() => request.json()).thenAnswer(
        (_) async => {
          'applicationId': 12,
          'decision': 'reject',
          'feedback': 'Please provide clearer qualification details.',
        },
      );
      final response = await review_route.handleApplicationReview(
        context,
        adminResolver: (_) async =>
            const AdminIdentity(id: 7, name: 'Admin Example'),
        repositoryFactory: () => repository,
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(repository.reviewedDecision, 'reject');
      expect(
        repository.reviewedFeedback,
        'Please provide clearer qualification details.',
      );
    },
  );

  test('rejects invalid decisions and rejection without feedback', () async {
    when(() => request.method).thenReturn(HttpMethod.post);
    var calls = 0;
    final repository = _TestApplicationsRepository();
    final responses = <Response>[];
    for (final body in [
      {'applicationId': 12, 'decision': 'defer'},
      {'applicationId': 12, 'decision': 'reject'},
    ]) {
      when(() => request.json()).thenAnswer((_) async => body);
      responses.add(
        await review_route.handleApplicationReview(
          context,
          adminResolver: (_) async =>
              const AdminIdentity(id: 7, name: 'Admin Example'),
          repositoryFactory: () {
            calls++;
            return repository;
          },
        ),
      );
    }
    expect(responses.map((response) => response.statusCode), [
      HttpStatus.badRequest,
      HttpStatus.badRequest,
    ]);
    expect(calls, 0);
  });

  test(
    'returns 401 or 403 without calling the review repository',
    () async {
      when(() => request.method).thenReturn(HttpMethod.post);
      when(() => request.json()).thenAnswer(
        (_) async => {
          'applicationId': 12,
          'decision': 'reject',
          'feedback': 'Incomplete application',
        },
      );
      var repositoryCreated = false;
      final unauthorized = await review_route.handleApplicationReview(
        context,
        adminResolver: (_) =>
            throw const AuthTokenException('Sign in required.'),
        repositoryFactory: () {
          repositoryCreated = true;
          return _TestApplicationsRepository();
        },
      );
      final forbidden = await review_route.handleApplicationReview(
        context,
        adminResolver: (_) => throw const AdminAccessDenied(
          'Administrator access is required.',
        ),
        repositoryFactory: () {
          repositoryCreated = true;
          return _TestApplicationsRepository();
        },
      );
      expect(unauthorized.statusCode, HttpStatus.unauthorized);
      expect(forbidden.statusCode, HttpStatus.forbidden);
      expect(repositoryCreated, isFalse);
    },
  );
}
