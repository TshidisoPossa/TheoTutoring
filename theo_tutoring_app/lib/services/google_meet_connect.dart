import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/google_client_ids.dart';

// Connect Google Meet (registration Step 3 and the tutor's Profile page).
// Google's window gives the app a one-hour token that can only create Meet
// rooms, and the backend uses it once to create the tutor's room. Works in
// the web app, Android and iOS; each needs its client set up in Google Cloud
// (config/google_client_ids.dart). The desktop builds have no Google
// sign-in. On the web, Google only accepts the origins listed on the client
// (localhost:7357 from run_dev.ps1).

const _meetScope = 'https://www.googleapis.com/auth/meetings.space.created';

/// Shown when Google gave no token: the tutor closed the window or said no,
/// the window could not open, or this platform is not set up.
const meetNotConnectedMessage =
    "Google Meet wasn't connected. Please try again.";

/// Thrown by [requestMeetAccessToken] when Google gave no token.
class MeetNotConnected implements Exception {
  const MeetNotConnected();

  @override
  String toString() => meetNotConnectedMessage;
}

Future<void>? _signInReady;

/// Loads Google sign-in. main.dart does not wait for it: on the web the
/// script comes from Google, and the app must still open when it can't load.
void startGoogleSignIn() {
  if (kIsWeb) {
    _start(googleWebClientId);
  } else if (defaultTargetPlatform == TargetPlatform.iOS) {
    _start(googleIosClientId);
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    _start(null); // known by package name and signing SHA-1, not an ID
  }
}

void _start(String? clientId) {
  // Opening Google without a client ID fails, and on iOS it closes the app
  if (clientId != null && clientId.isEmpty) {
    debugPrint(
      'Connect Google Meet is off on this platform: add its client ID to '
      'lib/config/google_client_ids.dart.',
    );
    return;
  }
  _signInReady = GoogleSignIn.instance.initialize(clientId: clientId)
    ..ignore();
}

/// Opens Google's window and returns a token for creating one Meet room.
/// Call it straight from a button press, before any other await, or the
/// browser can block the window.
Future<String> requestMeetAccessToken() async {
  final ready = _signInReady;
  if (ready == null) throw const MeetNotConnected();
  final String token;
  try {
    await ready.timeout(const Duration(seconds: 10));
    final authorization = await GoogleSignIn.instance.authorizationClient
        .authorizeScopes(const [_meetScope]);
    token = authorization.accessToken;
  } catch (_) {
    throw const MeetNotConnected();
  }
  unawaited(_forgetGoogleSession(token));
  return token;
}

// Every connect must open Google's window again, so the tutor can choose
// another account and the next tutor on this device never gets this one:
// the web plugin caches the token for an hour, and iOS keeps the Google
// account signed in. Neither call revokes the token the backend is about
// to use.
Future<void> _forgetGoogleSession(String token) async {
  try {
    await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(
      accessToken: token,
    );
    await GoogleSignIn.instance.signOut();
  } catch (_) {
    // Nothing left to forget; the token still works for the backend.
  }
}
