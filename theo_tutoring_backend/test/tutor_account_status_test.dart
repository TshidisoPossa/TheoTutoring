import 'package:test/test.dart';
import 'package:theo_tutoring_backend/tutor_account_status.dart';
import 'package:theo_tutoring_backend/tutorlanding_session.dart';

void main() {
  const allowedOnDashboard = [
    'Active',
    'Pending',
    'active',
    'PENDING',
    ' pEnDiNg ',
  ];
  const deniedOnDashboard = <String?>[
    'Incomplete',
    'incomplete',
    'Rejected',
    'REJECTED',
    '',
    '   ',
    null,
  ];

  group('canViewTutorDashboard', () {
    for (final status in allowedOnDashboard) {
      test('allows "$status"', () {
        expect(canViewTutorDashboard(status), isTrue);
      });
    }
    for (final status in deniedOnDashboard) {
      test('denies ${status == null ? 'null' : '"$status"'}', () {
        expect(canViewTutorDashboard(status), isFalse);
      });
    }
  });

  group('canAccessTutorLandingPage (all other restricted routes)', () {
    test('allows only Active, case-insensitively', () {
      expect(canAccessTutorLandingPage('Active'), isTrue);
      expect(canAccessTutorLandingPage('ACTIVE'), isTrue);
      expect(canAccessTutorLandingPage(' active '), isTrue);
    });

    test('blocks Pending tutors', () {
      expect(canAccessTutorLandingPage('Pending'), isFalse);
      expect(canAccessTutorLandingPage('pending'), isFalse);
      expect(canAccessTutorLandingPage('PENDING'), isFalse);
    });

    for (final status in deniedOnDashboard) {
      test('blocks ${status == null ? 'null' : '"$status"'}', () {
        expect(canAccessTutorLandingPage(status), isFalse);
      });
    }
  });

  group('canViewTutorApplicationStatus', () {
    final dashboard = Uri.parse(
      'https://example.test/TutorLandingpage/LandingPageScreen',
    );

    test('allows rejected accounts on the application status page only', () {
      expect(canViewTutorApplicationStatus('Rejected', dashboard), isTrue);
      expect(
        canViewTutorApplicationStatus(
          'Rejected',
          Uri.parse('https://example.test/TutorLandingpage/bookings'),
        ),
        isFalse,
      );
      expect(
        canViewTutorApplicationStatus(
          'Rejected',
          Uri.parse('https://example.test/TutorLandingpage/Profile'),
        ),
        isFalse,
      );
      expect(canViewTutorApplicationStatus('Pending', dashboard), isTrue);
      expect(canViewTutorApplicationStatus('Active', dashboard), isFalse);
    });
  });

  group('canAccessTutorRoute', () {
    test('rejected tutors may open only the status dashboard', () {
      expect(
        canAccessTutorRoute(
          'Rejected',
          Uri.parse('https://example.test/TutorLandingpage/LandingPageScreen'),
        ),
        isTrue,
      );
      for (final path in [
        '/TutorLandingpage/Profile',
        '/TutorLandingpage/notifications',
        '/TutorLandingpage/bookings',
        '/TutorLandingpage/LandingPageScreen/extra',
      ]) {
        expect(
          canAccessTutorRoute(
            'Rejected',
            Uri.parse('https://example.test$path'),
          ),
          isFalse,
          reason: path,
        );
      }
    });

    test('pending exceptions and active tutor access stay unchanged', () {
      expect(
        canAccessTutorRoute(
          'Pending',
          Uri.parse('https://example.test/TutorLandingpage/Profile'),
        ),
        isTrue,
      );
      expect(
        canAccessTutorRoute(
          'Pending',
          Uri.parse('https://example.test/TutorLandingpage/bookings'),
        ),
        isFalse,
      );
      expect(
        canAccessTutorRoute(
          'Active',
          Uri.parse('https://example.test/TutorLandingpage/bookings'),
        ),
        isTrue,
      );
    });
  });

  test(
    'rejected tutors may correct registration but are not active tutors',
    () {
      expect(canUpdateTutorRegistrationProfile('Rejected'), isTrue);
      expect(canSubmitTutorAvailability('Rejected'), isTrue);
      expect(canAccessTutorLandingPage('Rejected'), isFalse);
      expect(canViewTutorDashboard('Rejected'), isFalse);
    },
  );

  test('Pending is the only status the dashboard allows beyond Active', () {
    const statuses = <String?>[
      'Active',
      'Pending',
      'Incomplete',
      'Rejected',
      'Suspended',
      '',
      null,
    ];
    for (final status in statuses) {
      final dashboardOnly =
          canViewTutorDashboard(status) && !canAccessTutorLandingPage(status);
      expect(
        dashboardOnly,
        status?.toLowerCase() == 'pending',
        reason: 'status: $status',
      );
    }
  });

  group('TutorSession.isActive', () {
    test('is true only for an active status, ignoring case and spaces', () {
      for (final status in ['Active', 'active', 'ACTIVE', ' Active ']) {
        expect(TutorSession('uid', 1, accountStatus: status).isActive, isTrue);
      }
    });

    test('is false for pending, incomplete, rejected, empty and null', () {
      for (final status in [
        'Pending',
        'pending',
        'Incomplete',
        'Rejected',
        '',
      ]) {
        expect(
          TutorSession('uid', 1, accountStatus: status).isActive,
          isFalse,
          reason: status,
        );
      }
      // The constructor's default status is 'Active'; null is not accepted.
      expect(const TutorSession('uid', 1).isActive, isTrue);
    });

    test('keeps the user and tutor ids', () {
      const session = TutorSession('firebase-uid', 7, accountStatus: 'Pending');
      expect(session.userId, 'firebase-uid');
      expect(session.tutorId, 7);
      expect(session.accountStatus, 'Pending');
    });
  });
}
