// ignore_for_file: public_member_api_docs

enum TutorApplicationSubmissionPlan {
  createInitial,
  createResubmission,
  alreadyPending,
  blocked,
}

TutorApplicationSubmissionPlan planTutorApplicationSubmission({
  required String? accountStatus,
  required String? latestApplicationStatus,
  String? requestAccountStatus,
  bool hasPendingApplication = false,
}) {
  final account = accountStatus?.trim().toLowerCase();
  final application = latestApplicationStatus?.trim().toLowerCase();
  final requestedFrom = (requestAccountStatus ?? accountStatus)
      ?.trim()
      .toLowerCase();

  if (hasPendingApplication) {
    return account == 'pending' && application == 'pending'
        ? TutorApplicationSubmissionPlan.alreadyPending
        : TutorApplicationSubmissionPlan.blocked;
  }
  if (account == 'rejected' &&
      requestedFrom == 'rejected' &&
      application == 'rejected') {
    return TutorApplicationSubmissionPlan.createResubmission;
  }
  if ((account == 'incomplete' || account == 'pending') &&
      application == null) {
    return TutorApplicationSubmissionPlan.createInitial;
  }
  if (account == 'pending' && application == 'pending') {
    return TutorApplicationSubmissionPlan.alreadyPending;
  }
  return TutorApplicationSubmissionPlan.blocked;
}

class TutorApplicationSubmissionBlocked implements Exception {
  const TutorApplicationSubmissionBlocked();
}

Map<String, Object?> tutorApplicationStatusPayload({
  required Object? tutor,
  required String accountStatus,
  required String? applicationStatus,
  required String? adminFeedback,
  required String? submittedAt,
  required String? reviewedAt,
}) => {
  'tutor': tutor,
  'accountStatus': accountStatus,
  'application': applicationStatus == null
      ? null
      : {
          'status': applicationStatus,
          'adminFeedback': adminFeedback,
          'submittedAt': submittedAt,
          'reviewedAt': reviewedAt,
        },
};

/// Keeps the last rejection feedback visible while its replacement is pending.
/// A completed review always takes precedence, including a decision with no
/// feedback, so older feedback does not leak into a newly reviewed result.
String? tutorApplicationStatusFeedback({
  required String? applicationStatus,
  required String? currentFeedback,
  required String? latestRejectedFeedback,
}) {
  if (applicationStatus?.trim().toLowerCase() == 'pending') {
    return currentFeedback ?? latestRejectedFeedback;
  }
  return currentFeedback;
}
