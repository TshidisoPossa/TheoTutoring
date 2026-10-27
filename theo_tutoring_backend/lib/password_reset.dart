import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/request_utils.dart';

/// Thrown when Firebase could not be asked whether an account exists.
class AccountLookupUnavailable implements Exception {
  const AccountLookupUnavailable();
}

/// Answers whether a Firebase Authentication account uses an email.
// ignore: one_member_abstracts
abstract interface class FirebaseAccountLookup {
  Future<bool> emailExists(String email);
}

typedef FirebaseAccountLookupFactory = FirebaseAccountLookup Function();

/// Looks the email up with the Identity Toolkit admin API. The client SDK
/// cannot do this: with email enumeration protection on, Firebase reports
/// success for every reset request, whether or not the account exists.
class IdentityToolkitAccountLookup implements FirebaseAccountLookup {
  IdentityToolkitAccountLookup({
    FirebaseAdmin Function()? firebaseAdmin,
    http.Client? client,
  }) : _firebaseAdmin = firebaseAdmin ?? (() => FirebaseAdmin.instance),
       _client = client ?? http.Client();

  final FirebaseAdmin Function() _firebaseAdmin;
  final http.Client _client;

  static const _base = 'https://identitytoolkit.googleapis.com/v1/projects';

  @override
  Future<bool> emailExists(String email) async {
    final FirebaseAdmin admin;
    final String token;
    try {
      admin = _firebaseAdmin();
      token = await admin.accessToken();
    } on FirebaseAdminException {
      throw const AccountLookupUnavailable();
    }

    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$_base/${admin.projectId}/accounts:lookup'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': [email],
        }),
      );
    } on Exception {
      throw const AccountLookupUnavailable();
    }
    if (response.statusCode != 200) throw const AccountLookupUnavailable();

    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw const AccountLookupUnavailable();
    }
    // Firebase leaves "users" out entirely when nothing matches.
    final users = body is Map<String, dynamic> ? body['users'] : null;
    return users is List && users.isNotEmpty;
  }
}

/// POST {"email": "..."} → {"exists": true|false}. Called by the forgot
/// password screen before it asks Firebase to send the reset email.
Future<Response> handlePasswordResetCheck(
  RequestContext context, {
  FirebaseAccountLookupFactory? lookupFactory,
}) async {
  if (context.request.method != HttpMethod.post) {
    return jsonError(
      HttpStatus.methodNotAllowed,
      'Only POST requests are supported.',
    );
  }

  final String? email;
  try {
    email = optionalString(
      await readJsonObject(context),
      'email',
      maxLength: 254,
    );
  } on FormatException catch (error) {
    return jsonError(HttpStatus.badRequest, error.message);
  }
  if (email == null || !email.contains('@')) {
    return jsonError(
      HttpStatus.badRequest,
      'A valid email address is required.',
    );
  }

  try {
    final lookup = (lookupFactory ?? IdentityToolkitAccountLookup.new)();
    return Response.json(body: {'exists': await lookup.emailExists(email)});
  } on AccountLookupUnavailable {
    return jsonError(
      HttpStatus.serviceUnavailable,
      'Could not check that email right now. Please try again.',
    );
  }
}
