import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../Pages/Tutor/tutor_presence.dart';
import '../Pages/Tutor/tutor_theme.dart';
import '../config/api.dart';
import 'chat_unread.dart';
import 'in_app_notifications.dart';

/// Who is signed in, from GET /auth/me.
class SignedInAccount {
  const SignedInAccount({
    required this.userId,
    required this.role,
    required this.accountStatus,
    required this.name,
    required this.email,
    required this.emailVerified,
  });

  factory SignedInAccount.fromJson(Map<String, dynamic> json) {
    final userId = json['userId'];
    final role = json['role'];
    final status = json['accountStatus'];
    if (userId is! int || role is! String || status is! String) {
      throw const FormatException('Incomplete account details');
    }
    return SignedInAccount(
      userId: userId,
      role: role,
      accountStatus: status,
      name: (json['name'] as String?)?.trim() ?? '',
      email: (json['email'] as String?)?.trim() ?? '',
      emailVerified: json['emailVerified'] == true,
    );
  }

  final int userId;
  final String role; // student | tutor | admin
  final String accountStatus; // Incomplete, Pending, Active, Suspended, ...
  final String name;
  final String email;
  final bool emailVerified;
}

/// Thrown when GET /auth/me could not say who is signed in.
class AuthAccountException implements Exception {
  const AuthAccountException(this.message, {this.statusCode});

  final String message;
  final int? statusCode; // null if the server was not reached

  /// The Firebase account exists, but registration never finished.
  bool get notRegistered => statusCode == 404;

  /// The sign-in is no longer valid (expired, disabled or deleted).
  bool get signedOut => statusCode == 401;

  @override
  String toString() => message;
}

/// A verification code was emailed (or was not needed).
class VerificationCodeSent {
  const VerificationCodeSent({
    required this.alreadyVerified,
    required this.resendIn,
  });

  final bool alreadyVerified;

  /// Seconds before another code can be requested.
  final int resendIn;
}

/// Sending or checking a verification code failed; [message] is for the user.
class VerificationCodeException implements Exception {
  const VerificationCodeException(
    this.message, {
    this.statusCode,
    this.retryAfter,
    this.attemptsLeft,
    this.needsNewCode = false,
  });

  final String message;
  final int? statusCode; // null if the server was not reached

  /// Seconds to wait before asking for another code.
  final int? retryAfter;

  /// Wrong code: tries left on this code.
  final int? attemptsLeft;

  /// The code expired, was used up, or none was sent: tap Resend.
  final bool needsNewCode;

  @override
  String toString() => message;
}

/// The one place the app signs users in and out (Firebase Authentication).
/// Firebase keeps the session on the device; the backend only ever sees the
/// ID token.
class AuthService {
  AuthService({FirebaseAuth? auth, http.Client? client})
    : _providedAuth = auth,
      _client = client ?? http.Client();

  /// Shared by the whole app.
  static final AuthService instance = AuthService();

  final FirebaseAuth? _providedAuth;
  final http.Client _client;
  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  /// The user Firebase restored from the device, or null. Waits for the
  /// restore to finish (on the web it is not ready straight away).
  Future<User?> restoredUser() => _auth.authStateChanges().first;

  /// Fires with null when the user signs out (anywhere in the app).
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  /// Asks the backend who is signed in (GET /auth/me).
  Future<SignedInAccount> fetchAccount() async {
    final token = await idToken();
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$apiBaseUrl/auth/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw const AuthAccountException(
        'Could not connect to the server. Please try again.',
      );
    }

    final dynamic body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw AuthAccountException(
        'The server returned an invalid response. Please try again.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode != 200) {
      final error = body is Map<String, dynamic> ? body['error'] : null;
      throw AuthAccountException(
        error is String && error.isNotEmpty
            ? error
            : 'We could not load your account. Please try again.',
        statusCode: response.statusCode,
      );
    }
    try {
      return SignedInAccount.fromJson(body as Map<String, dynamic>);
    } on Object {
      throw AuthAccountException(
        'The server returned an invalid response. Please try again.',
        statusCode: response.statusCode,
      );
    }
  }

  /// The signed-in user's Firebase ID token (renewed by Firebase when it is
  /// close to expiring). [refresh] forces a new one, e.g. after the email
  /// was verified, so the backend sees the change.
  Future<String> idToken({bool refresh = false}) async {
    final user = _auth.currentUser;
    final String? token;
    try {
      token = await user?.getIdToken(refresh);
    } on Exception {
      throw const AuthAccountException(
        'Could not verify your account. Please sign in again.',
        statusCode: 401,
      );
    }
    if (token == null || token.isEmpty) {
      throw const AuthAccountException(
        'You are signed out. Please log in again.',
        statusCode: 401,
      );
    }
    return token;
  }

  /// Emails the signed-in user a new 6-digit code (through Brevo, by the
  /// backend). Throws a [VerificationCodeException], e.g. when asked again
  /// too soon (its [VerificationCodeException.retryAfter] says how long).
  Future<VerificationCodeSent> sendVerificationCode() async {
    final body = await _postVerification('send', const {});
    if (body['alreadyVerified'] == true) {
      return const VerificationCodeSent(alreadyVerified: true, resendIn: 0);
    }
    final resendIn = body['resendIn'];
    return VerificationCodeSent(
      alreadyVerified: false,
      resendIn: resendIn is int ? resendIn : 60,
    );
  }

  /// Checks the code from the email. When it is right the backend marks the
  /// email verified in Firebase; this then refreshes the user and token so
  /// the app and backend both see it. Throws a [VerificationCodeException].
  Future<void> verifyCode(String code) async {
    await _postVerification('verify', {'code': code});
    await _auth.currentUser?.reload();
    await idToken(refresh: true);
  }

  Future<Map<String, dynamic>> _postVerification(
    String action,
    Map<String, Object?> payload,
  ) async {
    final token = await idToken();
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$apiBaseUrl/auth/verification/$action'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw const VerificationCodeException(
        'Could not connect to the server. Please try again.',
      );
    }

    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    final json = body is Map<String, dynamic> ? body : <String, dynamic>{};
    if (response.statusCode == 200) return json;

    final error = json['error'];
    final retryAfter = json['retryAfter'];
    final attemptsLeft = json['attemptsLeft'];
    throw VerificationCodeException(
      error is String && error.isNotEmpty
          ? error
          : 'Something went wrong. Please try again.',
      statusCode: response.statusCode,
      retryAfter: retryAfter is int ? retryAfter : null,
      attemptsLeft: attemptsLeft is int ? attemptsLeft : null,
      needsNewCode: json['needsNewCode'] == true,
    );
  }

  /// Re-reads the user from Firebase (their email may have been verified
  /// since) and gets a fresh ID token so the backend sees the change too.
  Future<bool> checkEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    final verified = _auth.currentUser?.emailVerified ?? false;
    if (verified) await idToken(refresh: true);
    return verified;
  }

  /// Signs out of everything the app started for this user.
  Future<void> signOut() async {
    // While the token still works, so students see the tutor offline now.
    if (TutorPresence.instance.isRunning) await TutorPresence.instance.stop();
    InAppNotifications.instance.stop(); // no pop-ups once signed out
    ChatUnread.instance.stop(); // no chat badge either
    await _auth.signOut();
    TutorTheme.signedOut(); // the sign-in screens are always light
  }
}
