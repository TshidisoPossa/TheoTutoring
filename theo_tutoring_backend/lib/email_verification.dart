import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/env.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';
import 'package:theo_tutoring_backend/request_utils.dart';

// Email verification with a 6-digit code (like banking and delivery apps).
//
//   POST /auth/verification/send    emails a new code (through Brevo)
//   POST /auth/verification/verify  {"code": "123456"}
//
// A right code marks the email verified in Firebase itself, so the user's
// next ID token says email_verified: true and GET /auth/me reports it.
// Codes are stored only as SHA-256 hashes (migration 009).

/// How long a code works.
const codeLifetime = Duration(minutes: 10);

/// Wrong tries allowed per code before a new one must be requested.
const maxCodeAttempts = 5;

/// Wait between two codes for the same account.
const resendCooldown = Duration(seconds: 60);

/// Codes one account may request per hour (Brevo's free plan allows 300
/// emails a day for the whole app).
const maxCodesPerHour = 5;

// ---------------------------------------------------------------------------
// Storage

/// The MySQL user a code belongs to.
typedef CodeOwner = ({int userId, String name});

/// Recent codes for one account, for the resend limits.
typedef CodeSendStats = ({
  int? secondsSinceLast, // null: no code sent yet
  int sentLastHour,
  int secondsUntilHourFrees, // when the oldest code of the last hour drops out
});

/// The newest code sent to an account.
typedef StoredCode = ({
  int codeId,
  String codeHash,
  int attempts,
  bool used,
  bool expired,
});

/// Where the codes live (MySQL in the app, a fake in the route tests).
abstract interface class VerificationCodeStore {
  /// The MySQL user with this Firebase UID, or null.
  Future<CodeOwner?> findUser(String firebaseUid);

  /// How many codes went out recently, for the resend limits.
  Future<CodeSendStats> sendStats(int userId);

  /// Saves a new code (it replaces the older ones) and returns its id.
  Future<int> saveCode(int userId, String codeHash);

  /// Removes a code whose email could not be sent, so it does not count.
  Future<void> deleteCode(int codeId);

  /// The newest code, the only one that can still be used.
  Future<StoredCode?> latestCode(int userId);

  /// Uses up one try; false once the code has no tries left.
  Future<bool> claimAttempt(int codeId);

  /// The code was right; it cannot be used again.
  Future<void> markUsed(int codeId);
}

/// Codes in the EmailVerificationCode table (migration 009).
class MySqlVerificationCodeStore implements VerificationCodeStore {
  /// Uses the shared connection unless a test passes its own.
  MySqlVerificationCodeStore({
    Future<MySQLConnection> Function() connectionFactory = getConnection,
  }) : _connect = connectionFactory;

  final Future<MySQLConnection> Function() _connect;

  @override
  Future<CodeOwner?> findUser(String firebaseUid) async {
    final result = await (await _connect()).execute(
      'SELECT UserId, Name FROM `user` WHERE FirebaseUid = :uid LIMIT 1',
      {'uid': firebaseUid},
    );
    if (result.rows.isEmpty) return null;
    final row = result.rows.first;
    return (
      userId: int.parse(row.reqStr('UserId')),
      name: row.str('Name') ?? '',
    );
  }

  @override
  Future<CodeSendStats> sendStats(int userId) async {
    final result = await (await _connect()).execute(
      '''
      SELECT
        TIMESTAMPDIFF(SECOND, MAX(CreatedAtUtc), UTC_TIMESTAMP(6)) AS SinceLast,
        COUNT(CASE WHEN CreatedAtUtc > UTC_TIMESTAMP(6) - INTERVAL 1 HOUR
                   THEN 1 END) AS LastHour,
        TIMESTAMPDIFF(
          SECOND,
          UTC_TIMESTAMP(6),
          MIN(CASE WHEN CreatedAtUtc > UTC_TIMESTAMP(6) - INTERVAL 1 HOUR
                   THEN CreatedAtUtc END) + INTERVAL 1 HOUR
        ) AS HourFreesIn
      FROM emailverificationcode
      WHERE UserId = :userId
      ''',
      {'userId': userId},
    );
    final row = result.rows.first;
    return (
      secondsSinceLast: int.tryParse(row.str('SinceLast') ?? ''),
      sentLastHour: int.tryParse(row.str('LastHour') ?? '') ?? 0,
      secondsUntilHourFrees: int.tryParse(row.str('HourFreesIn') ?? '') ?? 0,
    );
  }

  @override
  Future<int> saveCode(int userId, String codeHash) async {
    final result = await (await _connect()).execute(
      '''
      INSERT INTO emailverificationcode
        (UserId, CodeHash, CreatedAtUtc, ExpiresAtUtc)
      VALUES (:userId, :hash, UTC_TIMESTAMP(6),
              UTC_TIMESTAMP(6) + INTERVAL ${codeLifetime.inSeconds} SECOND)
      ''',
      {'userId': userId, 'hash': codeHash},
    );
    return result.lastInsertID.toInt();
  }

  @override
  Future<void> deleteCode(int codeId) async {
    await (await _connect()).execute(
      'DELETE FROM emailverificationcode WHERE CodeID = :id',
      {'id': codeId},
    );
  }

  @override
  Future<StoredCode?> latestCode(int userId) async {
    final result = await (await _connect()).execute(
      '''
      SELECT CodeID, CodeHash, Attempts,
             UsedAtUtc IS NOT NULL AS Used,
             ExpiresAtUtc <= UTC_TIMESTAMP(6) AS Expired
      FROM emailverificationcode
      WHERE UserId = :userId
      ORDER BY CodeID DESC
      LIMIT 1
      ''',
      {'userId': userId},
    );
    if (result.rows.isEmpty) return null;
    final row = result.rows.first;
    return (
      codeId: int.parse(row.reqStr('CodeID')),
      codeHash: row.reqStr('CodeHash'),
      attempts: int.parse(row.reqStr('Attempts')),
      used: row.str('Used') == '1',
      expired: row.str('Expired') == '1',
    );
  }

  @override
  Future<bool> claimAttempt(int codeId) async {
    // One statement, so two quick taps cannot both use the last try.
    final result = await (await _connect()).execute(
      '''
      UPDATE emailverificationcode
      SET Attempts = Attempts + 1
      WHERE CodeID = :id AND UsedAtUtc IS NULL AND Attempts < :max
      ''',
      {'id': codeId, 'max': maxCodeAttempts},
    );
    return result.affectedRows == BigInt.one;
  }

  @override
  Future<void> markUsed(int codeId) async {
    await (await _connect()).execute(
      '''
      UPDATE emailverificationcode
      SET UsedAtUtc = UTC_TIMESTAMP(6)
      WHERE CodeID = :id
      ''',
      {'id': codeId},
    );
  }
}

// ---------------------------------------------------------------------------
// Codes

final _random = Random.secure();

/// A random 6-digit code, e.g. "048213".
String newVerificationCode() =>
    _random.nextInt(1000000).toString().padLeft(6, '0');

/// What is stored instead of the code itself.
String hashVerificationCode(int userId, String code) =>
    sha256.convert(utf8.encode('$userId:$code')).toString();

/// Compares two hashes in constant time.
bool _sameHash(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

final _sixDigits = RegExp(r'^\d{6}$');

// ---------------------------------------------------------------------------
// Sending the email

/// Thrown when the email could not be sent.
class EmailSendException implements Exception {
  /// Creates the exception.
  const EmailSendException(this.message);

  /// What went wrong (for the server log).
  final String message;

  @override
  String toString() => 'EmailSendException: $message';
}

/// Thrown when no way of sending email is set up.
class EmailNotConfiguredException implements Exception {
  /// Creates the exception.
  const EmailNotConfiguredException();
}

/// Emails a verification code.
// ignore: one_member_abstracts
abstract interface class VerificationEmailSender {
  /// Throws an [EmailSendException] if the email could not be sent.
  Future<void> sendCode({
    required String to,
    required String name,
    required String code,
  });
}

/// Brevo, from the BREVO_API_KEY / BREVO_SENDER_EMAIL settings. Without
/// them, and only while APP_ENV is development or test, codes are printed
/// in the backend window instead (for made-up test emails).
VerificationEmailSender verificationEmailSenderFromEnvironment() {
  final apiKey = env['BREVO_API_KEY']?.trim() ?? '';
  final senderEmail = env['BREVO_SENDER_EMAIL']?.trim() ?? '';
  if (apiKey.isNotEmpty && senderEmail.isNotEmpty) {
    return BrevoEmailSender(
      apiKey: apiKey,
      senderEmail: senderEmail,
      senderName: env['BREVO_SENDER_NAME']?.trim() ?? 'TheoTutoring',
    );
  }
  // Like demo payments: APP_ENV only counts from the real environment.
  final appEnv = Platform.environment['APP_ENV'];
  if (appEnv == 'development' || appEnv == 'test') {
    return const ConsoleEmailSender();
  }
  throw const EmailNotConfiguredException();
}

/// Sends through Brevo's transactional email API.
class BrevoEmailSender implements VerificationEmailSender {
  /// [client] is replaced in tests.
  BrevoEmailSender({
    required this.apiKey,
    required this.senderEmail,
    this.senderName = 'TheoTutoring',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// BREVO_API_KEY.
  final String apiKey;

  /// A sender address verified in Brevo (BREVO_SENDER_EMAIL).
  final String senderEmail;

  /// Shown as who the email is from.
  final String senderName;
  final http.Client _client;

  static final _url = Uri.parse('https://api.brevo.com/v3/smtp/email');

  @override
  Future<void> sendCode({
    required String to,
    required String name,
    required String code,
  }) async {
    final firstName = name.trim().split(RegExp(r'\s+')).first;
    final http.Response response;
    try {
      response = await _client
          .post(
            _url,
            headers: {
              'api-key': apiKey,
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'sender': {'name': senderName, 'email': senderEmail},
              'to': [
                {'email': to, if (name.trim().isNotEmpty) 'name': name.trim()},
              ],
              'subject': '$code is your TheoTutoring verification code',
              'htmlContent': verificationEmailHtml(firstName, code),
              'textContent': verificationEmailText(firstName, code),
            }),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception catch (error) {
      throw EmailSendException('Brevo could not be reached: $error');
    }
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw EmailSendException(
        'Brevo refused the email (${response.statusCode}): ${response.body}',
      );
    }
  }
}

/// Development only: prints the code in the backend window.
class ConsoleEmailSender implements VerificationEmailSender {
  /// Creates the sender.
  const ConsoleEmailSender();

  @override
  Future<void> sendCode({
    required String to,
    required String name,
    required String code,
  }) async {
    stderr.writeln(
      '[dev] Brevo is not set up. Verification code for $to: $code',
    );
  }
}

/// The plain-text email, for inboxes that do not show HTML.
String verificationEmailText(String firstName, String code) =>
    '''
Hi${firstName.isEmpty ? '' : ' $firstName'},

Your TheoTutoring verification code is: $code

Enter it in the app to finish creating your account. It expires in ${codeLifetime.inMinutes} minutes.

If you didn't sign up for TheoTutoring, you can ignore this email.

The TheoTutoring team
''';

/// The email as most inboxes show it.
String verificationEmailHtml(String firstName, String code) {
  final greeting = firstName.isEmpty
      ? 'Hi there,'
      : 'Hi ${const HtmlEscape().convert(firstName)},';
  final spacedCode = code.split('').join('&nbsp;');
  return '''
<div style="background:#f3f6fb;padding:32px 16px;font-family:Arial,Helvetica,sans-serif;">
  <div style="max-width:460px;margin:0 auto;background:#ffffff;border-radius:16px;padding:32px;color:#1f2937;">
    <p style="margin:0;font-size:22px;font-weight:bold;color:#246BFE;">TheoTutoring</p>
    <p style="margin:4px 0 24px;font-size:14px;color:#6b7280;">Find the right tutor for your modules.</p>
    <p style="font-size:16px;margin:0 0 12px;">$greeting</p>
    <p style="font-size:16px;margin:0 0 24px;">Enter this code in the app to verify your email address:</p>
    <div style="background:#eef3ff;border-radius:12px;padding:18px;text-align:center;font-size:34px;font-weight:bold;letter-spacing:6px;color:#1f2937;">$spacedCode</div>
    <p style="font-size:14px;color:#6b7280;margin:24px 0 0;">The code expires in ${codeLifetime.inMinutes} minutes. Never share it with anyone. TheoTutoring will never ask you for it.</p>
    <p style="font-size:14px;color:#6b7280;margin:12px 0 0;">If you didn't sign up for TheoTutoring, you can ignore this email.</p>
    <p style="font-size:14px;margin:24px 0 0;">The TheoTutoring team</p>
  </div>
</div>
''';
}

// ---------------------------------------------------------------------------
// Marking the email verified in Firebase

/// Marks an account's email verified in Firebase.
// ignore: one_member_abstracts
abstract interface class FirebaseEmailVerifier {
  /// Throws a [FirebaseAdminException] if Firebase could not be updated.
  Future<void> markEmailVerified(String uid);
}

/// The Identity Toolkit admin API, signed in with the service account.
class IdentityToolkitEmailVerifier implements FirebaseEmailVerifier {
  /// Tests pass their own admin and client.
  IdentityToolkitEmailVerifier({
    FirebaseAdmin Function()? firebaseAdmin,
    http.Client? client,
  }) : _firebaseAdmin = firebaseAdmin ?? (() => FirebaseAdmin.instance),
       _client = client ?? http.Client();

  final FirebaseAdmin Function() _firebaseAdmin;
  final http.Client _client;

  static const _base = 'https://identitytoolkit.googleapis.com/v1/projects';

  @override
  Future<void> markEmailVerified(String uid) async {
    final admin = _firebaseAdmin();
    final token = await admin.accessToken();
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_base/${admin.projectId}/accounts:update'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'localId': uid, 'emailVerified': true}),
          )
          .timeout(const Duration(seconds: 15));
    } on Exception catch (error) {
      throw FirebaseAdminException('Firebase could not be reached: $error');
    }
    if (response.statusCode != 200) {
      throw FirebaseAdminException(
        'Firebase refused to mark the email verified '
        '(${response.statusCode}): ${response.body}',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Routes

/// The signed-in Firebase user, or the response refusing the request.
Future<(FirebaseUser?, Response?)> _signedIn(
  RequestContext context,
  Future<FirebaseUser> Function(String?) tokenVerifier,
) async {
  try {
    final user = await tokenVerifier(
      context.request.headers['Authorization'] ??
          context.request.headers['authorization'],
    );
    return (user, null);
  } on AuthTokenException catch (error) {
    return (null, jsonError(HttpStatus.unauthorized, error.message));
  } catch (error) {
    stderr.writeln('Firebase authentication error: $error');
    return (
      null,
      jsonError(
        HttpStatus.serviceUnavailable,
        'Authentication service is temporarily unavailable.',
      ),
    );
  }
}

Response _tooMany(String message, int retryAfter) => Response.json(
  statusCode: HttpStatus.tooManyRequests,
  body: {'error': message, 'retryAfter': retryAfter},
);

/// POST /auth/verification/send → {"sent": true, "expiresIn": 600,
/// "resendIn": 60}, or {"alreadyVerified": true}.
Future<Response> handleSendVerificationCode(
  RequestContext context, {
  Future<FirebaseUser> Function(String?) tokenVerifier = verifyFirebaseToken,
  VerificationCodeStore? store,
  VerificationEmailSender Function() emailSender =
      verificationEmailSenderFromEnvironment,
}) async {
  if (context.request.method != HttpMethod.post) {
    return jsonError(
      HttpStatus.methodNotAllowed,
      'Only POST requests are supported.',
    );
  }

  final (user, rejection) = await _signedIn(context, tokenVerifier);
  if (user == null) return rejection!;

  if (user.emailVerified) {
    return Response.json(body: {'alreadyVerified': true});
  }
  final email = user.email;
  if (email == null || email.isEmpty) {
    return jsonError(
      HttpStatus.badRequest,
      'This account has no email address.',
    );
  }

  final codes = store ?? MySqlVerificationCodeStore();
  try {
    final owner = await codes.findUser(user.uid);
    if (owner == null) {
      return jsonError(
        HttpStatus.notFound,
        'Your registration is not complete.',
      );
    }

    final stats = await codes.sendStats(owner.userId);
    final sinceLast = stats.secondsSinceLast;
    if (sinceLast != null && sinceLast < resendCooldown.inSeconds) {
      final wait = resendCooldown.inSeconds - sinceLast;
      return _tooMany(
        'Please wait $wait seconds before asking for a new code.',
        wait,
      );
    }
    if (stats.sentLastHour >= maxCodesPerHour) {
      final wait = max(stats.secondsUntilHourFrees, 1);
      return _tooMany(
        'Too many codes requested. Try again in ${(wait / 60).ceil()} '
        'minutes.',
        wait,
      );
    }

    final VerificationEmailSender sender;
    try {
      sender = emailSender();
    } on EmailNotConfiguredException {
      stderr.writeln(
        'Email verification: set BREVO_API_KEY and BREVO_SENDER_EMAIL in '
        r'.env (or $env:APP_ENV = "development" to print codes in this '
        'window).',
      );
      return jsonError(
        HttpStatus.serviceUnavailable,
        'Email sending is not set up on the server yet.',
      );
    }

    final code = newVerificationCode();
    final codeId = await codes.saveCode(
      owner.userId,
      hashVerificationCode(owner.userId, code),
    );
    try {
      await sender.sendCode(to: email, name: owner.name, code: code);
    } on EmailSendException catch (error) {
      stderr.writeln('Verification email failed: ${error.message}');
      await codes.deleteCode(codeId);
      return jsonError(
        HttpStatus.serviceUnavailable,
        'Could not send the email. Please try again in a moment.',
      );
    }

    return Response.json(
      body: {
        'sent': true,
        'expiresIn': codeLifetime.inSeconds,
        'resendIn': resendCooldown.inSeconds,
      },
    );
  } catch (error) {
    stderr.writeln('Sending a verification code failed: $error');
    return jsonError(
      HttpStatus.internalServerError,
      'An unexpected error occurred.',
    );
  }
}

/// POST /auth/verification/verify {"code": "123456"} → {"verified": true}.
/// Wrong codes: 400 with "attemptsLeft"; out of tries or no live code: 400
/// with "needsNewCode": true.
Future<Response> handleVerifyCode(
  RequestContext context, {
  Future<FirebaseUser> Function(String?) tokenVerifier = verifyFirebaseToken,
  VerificationCodeStore? store,
  FirebaseEmailVerifier? firebase,
}) async {
  if (context.request.method != HttpMethod.post) {
    return jsonError(
      HttpStatus.methodNotAllowed,
      'Only POST requests are supported.',
    );
  }

  final (user, rejection) = await _signedIn(context, tokenVerifier);
  if (user == null) return rejection!;

  if (user.emailVerified) return Response.json(body: {'verified': true});

  final Object? code;
  try {
    code = (await readJsonObject(context))['code'];
  } on FormatException catch (error) {
    return jsonError(HttpStatus.badRequest, error.message);
  }
  if (code is! String || !_sixDigits.hasMatch(code.trim())) {
    return jsonError(HttpStatus.badRequest, 'Enter the 6-digit code.');
  }

  Response needsNewCode(String message) => Response.json(
    statusCode: HttpStatus.badRequest,
    body: {'error': message, 'needsNewCode': true},
  );

  final codes = store ?? MySqlVerificationCodeStore();
  try {
    final owner = await codes.findUser(user.uid);
    if (owner == null) {
      return jsonError(
        HttpStatus.notFound,
        'Your registration is not complete.',
      );
    }

    final latest = await codes.latestCode(owner.userId);
    if (latest == null || latest.used) {
      return needsNewCode('There is no active code. Tap Resend for a new one.');
    }
    if (latest.expired) {
      return needsNewCode('This code has expired. Tap Resend for a new one.');
    }
    if (!await codes.claimAttempt(latest.codeId)) {
      return needsNewCode('Too many wrong tries. Tap Resend for a new code.');
    }

    final hash = hashVerificationCode(owner.userId, code.trim());
    if (!_sameHash(hash, latest.codeHash)) {
      final left = maxCodeAttempts - latest.attempts - 1;
      if (left <= 0) {
        return needsNewCode(
          'That code is incorrect, and that was the last try. '
          'Tap Resend for a new code.',
        );
      }
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {
          'error':
              'That code is incorrect. $left ${left == 1 ? 'try' : 'tries'} '
              'left.',
          'attemptsLeft': left,
        },
      );
    }

    try {
      await (firebase ?? IdentityToolkitEmailVerifier()).markEmailVerified(
        user.uid,
      );
    } on FirebaseAdminException catch (error) {
      stderr.writeln('Marking the email verified failed: $error');
      return jsonError(
        HttpStatus.serviceUnavailable,
        'Your code is right, but we could not finish. Please try again.',
      );
    }
    await codes.markUsed(latest.codeId);
    return Response.json(body: {'verified': true});
  } catch (error) {
    stderr.writeln('Checking a verification code failed: $error');
    return jsonError(
      HttpStatus.internalServerError,
      'An unexpected error occurred.',
    );
  }
}
