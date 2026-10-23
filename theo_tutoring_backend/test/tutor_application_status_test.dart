import 'package:test/test.dart';
import 'package:theo_tutoring_backend/tutor_application_status.dart';

void main() {
  group('planTutorApplicationSubmission', () {
    test('creates a first application for an incomplete tutor', () {
      expect(
        planTutorApplicationSubmission(
          accountStatus: 'Incomplete',
          latestApplicationStatus: null,
        ),
        TutorApplicationSubmissionPlan.createInitial,
      );
    });

    test('creates a new application after rejection', () {
      expect(
        planTutorApplicationSubmission(
          accountStatus: 'Rejected',
          latestApplicationStatus: 'Rejected',
          requestAccountStatus: 'Rejected',
        ),
        TutorApplicationSubmissionPlan.createResubmission,
      );
    });

    test('does not turn an in-flight pending submission into resubmission', () {
      expect(
        planTutorApplicationSubmission(
          accountStatus: 'Rejected',
          latestApplicationStatus: 'Rejected',
          requestAccountStatus: 'Pending',
        ),
        TutorApplicationSubmissionPlan.blocked,
      );
    });

    test('does not duplicate an application already pending', () {
      expect(
        planTutorApplicationSubmission(
          accountStatus: 'Pending',
          latestApplicationStatus: 'Pending',
        ),
        TutorApplicationSubmissionPlan.alreadyPending,
      );
    });

    test('does not create a second pending row when one already exists', () {
      expect(
        planTutorApplicationSubmission(
          accountStatus: 'Pending',
          latestApplicationStatus: 'Pending',
          hasPendingApplication: true,
        ),
        TutorApplicationSubmissionPlan.alreadyPending,
      );
    });

    test('blocks resubmission if any pending application already exists', () {
      expect(
        planTutorApplicationSubmission(
          accountStatus: 'Rejected',
          latestApplicationStatus: 'Rejected',
          hasPendingApplication: true,
        ),
        TutorApplicationSubmissionPlan.blocked,
      );
    });

    test('blocks inconsistent account/application states', () {
      expect(
        planTutorApplicationSubmission(
          accountStatus: 'Rejected',
          latestApplicationStatus: 'Pending',
        ),
        TutorApplicationSubmissionPlan.blocked,
      );
    });
  });

  test('keeps reviewer feedback in the application-status payload', () {
    final payload = tutorApplicationStatusPayload(
      tutor: {'name': 'Tutor Example'},
      accountStatus: 'Rejected',
      applicationStatus: 'Rejected',
      adminFeedback: 'Please upload a readable certificate.',
      submittedAt: '2026-05-01 09:00:00',
      reviewedAt: '2026-05-02 09:00:00',
    );

    expect(payload['accountStatus'], 'Rejected');
    expect(
      (payload['application'] as Map)['adminFeedback'],
      'Please upload a readable certificate.',
    );
  });

  group('tutorApplicationStatusFeedback', () {
    test(
      'shows the latest rejection feedback while resubmission is pending',
      () {
        expect(
          tutorApplicationStatusFeedback(
            applicationStatus: 'Pending',
            currentFeedback: null,
            latestRejectedFeedback: 'Please upload a clearer certificate.',
          ),
          'Please upload a clearer certificate.',
        );
      },
    );

    test('a new review decision replaces older rejection feedback', () {
      expect(
        tutorApplicationStatusFeedback(
          applicationStatus: 'Approved',
          currentFeedback: null,
          latestRejectedFeedback: 'Older rejection feedback.',
        ),
        isNull,
      );
      expect(
        tutorApplicationStatusFeedback(
          applicationStatus: 'Rejected',
          currentFeedback: 'New review feedback.',
          latestRejectedFeedback: 'Older rejection feedback.',
        ),
        'New review feedback.',
      );
    });
  });
}
