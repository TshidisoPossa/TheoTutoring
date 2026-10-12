/// Whether an account may access tutor landing-page routes.
bool canAccessTutorLandingPage(String? status) =>
    status?.trim().toLowerCase() == 'active';

/// Whether an account may submit the teaching-profile registration step.
bool canUpdateTutorRegistrationProfile(String? status) =>
    status?.trim().toLowerCase() == 'incomplete';

/// Whether an account may submit or resubmit registration availability.
bool canSubmitTutorAvailability(String? status) {
  final normalized = status?.trim().toLowerCase();
  return normalized == 'incomplete' || normalized == 'pending';
}
