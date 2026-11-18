import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/api.dart';

// The suspended-account screen's two backend routes:
//   GET  /account/suspension         the user's suspension and appeal
//   POST /account/suspension/appeal  {"explanation": "..."}
// Both identify the user only by their Firebase ID token.

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

String? _text(Object? value) {
  final s = value is String ? value.trim() : null;
  return s == null || s.isEmpty ? null : s;
}

class AccountSuspension {
  const AccountSuspension({
    required this.id,
    required this.reason,
    required this.suspendedAt,
    required this.isActive,
    this.liftedAt,
    this.liftReason,
  });

  factory AccountSuspension.fromJson(Map<String, dynamic> j) =>
      AccountSuspension(
        id: j['suspensionId'] as int,
        reason: _text(j['reason']) ?? '',
        suspendedAt: _date(j['suspendedAt']),
        isActive: j['status'] == 'Active',
        liftedAt: _date(j['liftedAt']),
        liftReason: _text(j['liftReason']),
      );

  final int id;
  final String reason;
  final DateTime? suspendedAt;
  final bool isActive;
  final DateTime? liftedAt;

  /// AppealApproved, Reinstated or Deactivated.
  final String? liftReason;
}

enum AppealStatus {
  pending,
  approved,
  rejected,
  closed,
  unknown;

  static AppealStatus parse(Object? value) => switch (value) {
    'Pending' => pending,
    'Approved' => approved,
    'Rejected' => rejected,
    'Closed' => closed,
    _ => unknown,
  };
}

class SuspensionAppeal {
  const SuspensionAppeal({
    required this.id,
    required this.explanation,
    required this.status,
    this.submittedAt,
    this.decisionNote,
    this.decidedAt,
  });

  factory SuspensionAppeal.fromJson(Map<String, dynamic> j) =>
      SuspensionAppeal(
        id: j['appealId'] as int,
        explanation: _text(j['explanation']) ?? '',
        status: AppealStatus.parse(j['status']),
        submittedAt: _date(j['submittedAt']),
        decisionNote: _text(j['decisionNote']),
        decidedAt: _date(j['decidedAt']),
      );

  final int id;
  final String explanation;
  final AppealStatus status;
  final DateTime? submittedAt;
  final String? decisionNote;
  final DateTime? decidedAt;
}

/// GET /account/suspension.
class AccountSuspensionStatus {
  const AccountSuspensionStatus({
    required this.accountStatus,
    required this.canAppeal,
    this.suspension,
    this.appeal,
    this.explanationMinLength = 20,
    this.explanationMaxLength = 2000,
  });

  factory AccountSuspensionStatus.fromJson(Map<String, dynamic> j) {
    final suspension = j['suspension'];
    final appeal = j['appeal'];
    return AccountSuspensionStatus(
      accountStatus: (j['accountStatus'] as String?) ?? '',
      canAppeal: j['canAppeal'] == true,
      suspension: suspension is Map<String, dynamic>
          ? AccountSuspension.fromJson(suspension)
          : null,
      appeal: appeal is Map<String, dynamic>
          ? SuspensionAppeal.fromJson(appeal)
          : null,
      explanationMinLength: j['explanationMinLength'] as int? ?? 20,
      explanationMaxLength: j['explanationMaxLength'] as int? ?? 2000,
    );
  }

  final String accountStatus;
  final bool canAppeal;
  final AccountSuspension? suspension;
  final SuspensionAppeal? appeal;
  final int explanationMinLength;
  final int explanationMaxLength;

  bool get isSuspended => accountStatus == 'Suspended';
}

class AccountSuspensionException implements Exception {
  const AccountSuspensionException(this.message, {this.code});
  final String message;

  /// e.g. appeal_exists, not_suspended.
  final String? code;

  @override
  String toString() => message;
}

Future<String?> _firebaseToken() async =>
    FirebaseAuth.instance.currentUser?.getIdToken();

class AccountSuspensionApi {
  AccountSuspensionApi({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  }) : _client = client ?? http.Client(),
       _tokenProvider = tokenProvider ?? _firebaseToken;

  final http.Client _client;
  final Future<String?> Function() _tokenProvider;

  Future<Map<String, String>> _headers() async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const AccountSuspensionException(
        'You are signed out. Please sign in again.',
      );
    }
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  AccountSuspensionException _failure(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is String) {
        return AccountSuspensionException(
          body['error'] as String,
          code: body['code'] as String?,
        );
      }
    } on FormatException {
      // fall through
    }
    return AccountSuspensionException(
      'Something went wrong (${response.statusCode}). Please try again.',
    );
  }

  Future<AccountSuspensionStatus> fetch() async {
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$apiBaseUrl/account/suspension'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 15));
    } on AccountSuspensionException {
      rethrow;
    } on Exception {
      throw const AccountSuspensionException(
        'Could not connect to the server. Please try again.',
      );
    }
    if (response.statusCode != 200) throw _failure(response);
    return AccountSuspensionStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<SuspensionAppeal> submitAppeal(String explanation) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$apiBaseUrl/account/suspension/appeal'),
            headers: await _headers(),
            body: jsonEncode({'explanation': explanation}),
          )
          .timeout(const Duration(seconds: 20));
    } on AccountSuspensionException {
      rethrow;
    } on Exception {
      throw const AccountSuspensionException(
        'Could not connect to the server. Your appeal was not sent.',
      );
    }
    if (response.statusCode != 201) throw _failure(response);
    return SuspensionAppeal.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
