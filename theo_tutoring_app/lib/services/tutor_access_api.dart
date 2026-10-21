import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api.dart';

sealed class TutorAccessResult {
  const TutorAccessResult();
}

/// The backend confirmed this Firebase user is a tutor allowed on the
/// dashboard. [accountStatus] is the server's value, normalised to
/// 'Active' or 'Pending'.
class TutorAccessGranted extends TutorAccessResult {
  const TutorAccessGranted(this.accountStatus, {this.dashboard});
  final String accountStatus;

  /// The dashboard response body (counts, today's schedule, application).
  final Map<String, dynamic>? dashboard;
}

/// Not a tutor, or a tutor whose account may not open the dashboard
/// (Incomplete, Rejected, unknown or missing status).
class TutorAccessDenied extends TutorAccessResult {
  const TutorAccessDenied(this.message);
  final String message;
}

/// The status could not be determined (expired token, network, bad response).
class TutorAccessFailure extends TutorAccessResult {
  const TutorAccessFailure(this.message);
  final String message;
}

/// Asks the backend for the tutor's real account status. The existing
/// dashboard endpoint is used because its middleware verifies the Firebase
/// token and only admits Active and Pending tutors; the role and status are
/// never taken from the client.
class TutorAccessApi {
  TutorAccessApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<TutorAccessResult> check(String idToken) async {
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$apiBaseUrl/TutorLandingpage/LandingPageScreen'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));
    } on Exception {
      return const TutorAccessFailure(
        'Could not connect to the server. Please try again.',
      );
    }

    switch (response.statusCode) {
      case 200:
        break;
      case 401:
        return const TutorAccessFailure(
          'Your session could not be verified. Please sign in again.',
        );
      case 403:
        return const TutorAccessDenied(
          'No active or pending tutor account was found for this login. '
          'If you are still registering, finish the registration steps.',
        );
      default:
        return const TutorAccessFailure(
          'We could not verify your tutor account. Please try again.',
        );
    }

    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      return const TutorAccessFailure(
        'The server returned an invalid response. Please try again.',
      );
    }
    final status = body is Map<String, dynamic> ? body['accountStatus'] : null;
    if (status is! String) {
      return const TutorAccessDenied(
        'Your tutor account status could not be confirmed.',
      );
    }
    switch (status.trim().toLowerCase()) {
      case 'active':
        return TutorAccessGranted('Active', dashboard: body as Map<String, dynamic>);
      case 'pending':
        return TutorAccessGranted('Pending', dashboard: body as Map<String, dynamic>);
      default:
        return const TutorAccessDenied('Your tutor account is not active yet.');
    }
  }
}
