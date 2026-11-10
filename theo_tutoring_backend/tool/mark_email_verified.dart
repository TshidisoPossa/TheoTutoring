// Marks test accounts' emails as verified in Firebase, so the app does not
// ask them for an email code (useful for made-up test emails with no inbox).
//
// Run from theo_tutoring_backend (it uses the service account in .env):
//   dart run tool/mark_email_verified.dart joe23@gmail.com [more emails...]
//
// Undo with --undo before the emails.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:theo_tutoring_backend/firebase_admin.dart';

Future<void> main(List<String> args) async {
  final undo = args.contains('--undo');
  final emails = args.where((a) => !a.startsWith('--')).toList();
  if (emails.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/mark_email_verified.dart [--undo] <email>...',
    );
    exit(64);
  }

  final admin = FirebaseAdmin.instance;
  final base =
      'https://identitytoolkit.googleapis.com/v1/projects/${admin.projectId}';
  final headers = {
    'Authorization': 'Bearer ${await admin.accessToken()}',
    'Content-Type': 'application/json',
  };

  var failed = false;
  for (final email in emails) {
    final lookup = await http.post(
      Uri.parse('$base/accounts:lookup'),
      headers: headers,
      body: jsonEncode({
        'email': [email.trim().toLowerCase()],
      }),
    );
    final users = lookup.statusCode == 200
        ? (jsonDecode(lookup.body) as Map<String, dynamic>)['users']
        : null;
    if (users is! List || users.isEmpty) {
      stderr.writeln('$email: no Firebase account found');
      failed = true;
      continue;
    }
    final uid = (users.first as Map<String, dynamic>)['localId'] as String;

    final update = await http.post(
      Uri.parse('$base/accounts:update'),
      headers: headers,
      body: jsonEncode({'localId': uid, 'emailVerified': !undo}),
    );
    if (update.statusCode == 200) {
      stdout.writeln(
        '$email ($uid): email ${undo ? 'no longer verified' : 'verified'}',
      );
    } else {
      stderr.writeln('$email: Firebase refused (${update.statusCode})');
      failed = true;
    }
  }
  exit(failed ? 1 : 0);
}
