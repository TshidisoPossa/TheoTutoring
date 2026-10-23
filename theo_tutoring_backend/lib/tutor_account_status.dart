/// Whether an account may access tutor landing-page routes.
bool canAccessTutorLandingPage(String? status) =>
    status?.trim().toLowerCase() == 'active';

/// Whether an account may open the tutor dashboard. Pending tutors see their
/// application status there instead of bookings.
bool canViewTutorDashboard(String? status) {
  final normalized = status?.trim().toLowerCase();
  return normalized == 'active' || normalized == 'pending';
}

/// Rejected tutors may read only the dashboard's application-status response.
bool canViewTutorApplicationStatus(String? status, Uri uri) {
  final normalizedStatus = status?.trim().toLowerCase();
  var path = uri.path;
  if (path.endsWith('/')) path = path.substring(0, path.length - 1);
  return (normalizedStatus == 'pending' || normalizedStatus == 'rejected') &&
      path == '/TutorLandingpage/LandingPageScreen';
}

/// Route-level authorization shared by tutor middleware and focused tests.
bool canAccessTutorRoute(String? status, Uri uri) {
  if (canAccessTutorLandingPage(status)) return true;

  var path = uri.path;
  if (path.endsWith('/')) path = path.substring(0, path.length - 1);
  final pendingOnlyPath =
      path == '/TutorLandingpage/LandingPageScreen' ||
      path == '/TutorLandingpage/notifications' ||
      path.startsWith('/TutorLandingpage/notifications/') ||
      path == '/TutorLandingpage/Profile' ||
      path.startsWith('/TutorLandingpage/Profile/');
  if (status?.trim().toLowerCase() == 'pending' && pendingOnlyPath) {
    return true;
  }
  return canViewTutorApplicationStatus(status, uri);
}

/// Whether an account may submit the teaching-profile registration step.
bool canUpdateTutorRegistrationProfile(String? status) =>
    status?.trim().toLowerCase() == 'incomplete' ||
    status?.trim().toLowerCase() == 'rejected';

/// Whether an account may submit or resubmit registration availability.
bool canSubmitTutorAvailability(String? status) {
  final normalized = status?.trim().toLowerCase();
  return normalized == 'incomplete' ||
      normalized == 'pending' ||
      normalized == 'rejected';
}
