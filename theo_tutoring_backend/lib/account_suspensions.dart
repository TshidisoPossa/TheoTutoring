import 'dart:io';

import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';
import 'package:theo_tutoring_backend/notifications.dart';

// Account suspensions and appeals (migration 012_account_suspension_appeal).
//
// Suspending: an administrator with admin.students.manage / admin.tutors.manage
// suspends a student or tutor with a reason (PATCH .../{id}/status). One
// transaction sets User.AccountStatus, adds the AccountSuspension row and the
// Notification row (the SQL record of what the user is told). After it
// commits, the in-app notification is written to Firestore; if that fails the
// suspension stands, the admin is told, and delivery is retried the next time
// the user opens their suspension screen.
//
// Appealing: the suspended user may send one appeal per suspension
// (GET/POST /account/suspension...). Their identity comes only from the
// Firebase token; no ID, role or status is taken from the app. Appealing never
// changes the account.
//
// Deciding: an administrator who may manage that kind of account approves
// (the suspension is lifted and the previous status restored) or rejects (the
// suspension stays; the rejection is final for that suspension). The appeal,
// suspension, User row and Notification row change in one transaction.
//
// Every writer locks the User row first (SELECT ... FOR UPDATE), then the
// suspension, then the appeal, so concurrent decisions, reinstatements and
// appeals run one after another and the second sees the first's result.

// ignore_for_file: public_member_api_docs

const suspensionReasonMinLength = 10;
const suspensionReasonMaxLength = 1000;
const appealExplanationMinLength = 20;
const appealExplanationMaxLength = 2000;
const appealDecisionNoteMinLength = 10;
const appealDecisionNoteMaxLength = 1000;

/// Account kinds that can be suspended, by User.Role.
const suspendableRoles = {'student', 'tutor'};

/// The permission an administrator needs to suspend, reinstate or decide
/// appeals for each kind of account (the same as for changing its status).
const suspensionManagePermission = {
  'student': 'admin.students.manage',
  'tutor': 'admin.tutors.manage',
};

/// Roles whose appeals [admin] may see and decide.
Set<String> appealRolesFor(AdminIdentity admin) {
  final granted = permissionsForAdminRole(admin.roleKey);
  return {
    for (final MapEntry(key: role, value: permission)
        in suspensionManagePermission.entries)
      if (granted.contains(permission)) role,
  };
}

class SuspensionValidation implements Exception {
  const SuspensionValidation(this.message);
  final String message;
}

/// The student, tutor or appeal does not exist (or is not the caller's).
class SuspensionNotFound implements Exception {
  const SuspensionNotFound([this.message = 'Not found.']);
  final String message;
}

/// The account's current status may not be changed here (a tutor still in
/// review is decided on the Applications page).
class AccountStatusLocked implements Exception {
  const AccountStatusLocked(this.status);
  final String status;
}

/// The request conflicts with the account's current state.
class SuspensionConflict implements Exception {
  const SuspensionConflict(this.code, this.message);
  final String code;
  final String message;
}

/// Trims [value] and checks its length, for reasons, explanations and notes.
String requireText(
  Object? value, {
  required String field,
  required int min,
  required int max,
}) {
  final text = value is String ? value.trim() : '';
  if (text.length < min) {
    throw SuspensionValidation(
      '$field must be at least $min characters.',
    );
  }
  if (text.length > max) {
    throw SuspensionValidation('$field must be $max characters or fewer.');
  }
  return text;
}

/// A notification to write to Firestore once the transaction has committed.
/// [notificationId] is its row in the SQL Notification table.
class AccountNotice {
  const AccountNotice({
    required this.notificationId,
    required this.firebaseUid,
    required this.firestoreId,
    required this.type,
    required this.body,
  });

  final int notificationId;
  final String firebaseUid;

  /// Fixed document id, so a retried delivery never duplicates the card.
  final String firestoreId;
  final String type;
  final String body;

  String get title => accountNoticeTitle(type);
}

String accountNoticeTitle(String type) => switch (type) {
  NotificationType.accountSuspended => 'Account suspended',
  NotificationType.appealApproved => 'Appeal approved',
  NotificationType.appealRejected => 'Appeal rejected',
  _ => 'Account update',
};

String suspensionNoticeBody(String reason) =>
    'Your TheoTutoring account has been suspended. Reason: $reason '
    'If you think this is a mistake, you can appeal from the suspension '
    'screen.';

String appealDecisionNoticeBody({required bool approved, String? note}) {
  final why = note?.trim() ?? '';
  return approved
      ? 'Your appeal was approved and your account has been reinstated.'
            '${why.isEmpty ? '' : ' Note from the team: $why'}'
      : 'Your appeal was reviewed and your account remains suspended. '
            'Reason: $why';
}

/// What a status change did; [notice] is set when the user must be told.
class AccountStatusChange {
  const AccountStatusChange({
    required this.userId,
    required this.previousStatus,
    required this.status,
    this.notice,
  });

  final int userId;
  final String previousStatus;
  final String status;
  final AccountNotice? notice;
}

/// The decided appeal (as the admin list shows it) and the user's notice.
class AppealDecision {
  const AppealDecision({required this.appeal, required this.notice});
  final Map<String, Object?> appeal;
  final AccountNotice notice;
}

abstract interface class AccountSuspensionRepository {
  /// Changes the status of the [role] account with profile id [profileId]
  /// (StudentID or TutorID). Suspending needs [reason]; leaving Suspended
  /// ends the active suspension and closes a pending appeal. With
  /// [allowedFrom], an account in any other status throws
  /// [AccountStatusLocked] and nothing changes.
  Future<AccountStatusChange> changeStatus({
    required AdminIdentity admin,
    required String role,
    required int profileId,
    required String status,
    String? reason,
    Set<String>? allowedFrom,
  });

  /// The signed-in student's or tutor's latest suspension and appeal, or
  /// null if [firebaseUid] is not a student or tutor.
  Future<Map<String, Object?>?> suspensionFor(String firebaseUid);

  /// Records the signed-in user's appeal against their active suspension.
  Future<Map<String, Object?>> submitAppeal(
    String firebaseUid,
    String explanation,
  );

  /// Appeals for accounts of [roles], filtered by [status] (pending,
  /// approved, rejected, closed or all).
  Future<Map<String, Object?>> listAppeals({
    required String status,
    required Set<String> roles,
  });

  Future<AppealDecision> decideAppeal({
    required AdminIdentity admin,
    required int appealId,
    required bool approve,
    required String? note,
    required Set<String> roles,
  });

  /// Notices the user was not sent yet (Firestore was unavailable).
  Future<List<AccountNotice>> undeliveredNotices(String firebaseUid);

  /// Records that the notice was written to Firestore.
  Future<void> markDelivered(int notificationId, String firestoreId);
}

/// Writes one notice to Firestore. Tests pass their own.
typedef AccountNoticeSender = Future<void> Function(AccountNotice notice);

NotificationStore? _store; // shared, so the Google access token is reused

Future<void> _sendToFirestore(AccountNotice notice) async {
  final store = _store ??= NotificationStore.fromFirebaseAdmin();
  // false means it was already there: delivered by an earlier attempt
  await store.createOnce(
    id: notice.firestoreId,
    uid: notice.firebaseUid,
    type: notice.type,
    title: notice.title,
    body: notice.body,
  );
}

/// Delivers [notice] and records it. Never throws: the suspension or
/// decision is already saved, so a failure is logged and reported (false),
/// and the notice stays undelivered for a later retry.
Future<bool> deliverAccountNotice(
  AccountNotice notice,
  AccountSuspensionRepository repository, {
  AccountNoticeSender? sender,
}) async {
  try {
    await (sender ?? _sendToFirestore)(notice);
  } catch (error) {
    stderr.writeln(
      'Account notice ${notice.firestoreId} was not delivered '
      '(${error.runtimeType}); it will be retried.',
    );
    return false;
  }
  try {
    await repository.markDelivered(notice.notificationId, notice.firestoreId);
  } catch (error) {
    // Delivered; the fixed id makes a later retry harmless.
    stderr.writeln(
      'Account notice ${notice.firestoreId} delivery was not recorded '
      '(${error.runtimeType}).',
    );
  }
  return true;
}

/// Retries the user's undelivered notices. Never throws.
Future<void> retryUndeliveredNotices(
  String firebaseUid,
  AccountSuspensionRepository repository, {
  AccountNoticeSender? sender,
}) async {
  try {
    for (final notice in await repository.undeliveredNotices(firebaseUid)) {
      await deliverAccountNotice(notice, repository, sender: sender);
    }
  } catch (error) {
    stderr.writeln('Undelivered account notices not retried ($error).');
  }
}

/// "2026-11-17 09:30:00.000000" (UTC) -> "2026-11-17T09:30:00.000000Z".
String? _iso(String? value) =>
    value == null ? null : '${value.trim().replaceFirst(' ', 'T')}Z';

int? _int(String? value) => value == null ? null : int.tryParse(value);

class MySqlAccountSuspensionRepository implements AccountSuspensionRepository {
  MySqlAccountSuspensionRepository({
    Future<MySQLConnection> Function()? connectionFactory,
  }) : _connectionFactory = connectionFactory ?? createIndependentConnection;

  final Future<MySQLConnection> Function() _connectionFactory;

  Future<T> _transaction<T>(
    Future<T> Function(MySQLConnection connection) work,
  ) async {
    final connection = await _connectionFactory();
    try {
      await connection.execute(
        'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ',
      );
      return await connection.transactional(work);
    } finally {
      if (connection.connected) await connection.close();
    }
  }

  Future<T> _read<T>(
    Future<T> Function(MySQLConnection connection) work,
  ) async {
    final connection = await _connectionFactory();
    try {
      return await work(connection);
    } finally {
      if (connection.connected) await connection.close();
    }
  }

  static Future<int> _insertNotification(
    MySQLConnection connection, {
    required int userId,
    required String type,
    required String message,
  }) async {
    final result = await connection.execute(
      'INSERT INTO notification (UserID, Type, Message, IsRead) '
      'VALUES (:userId, :type, :message, FALSE)',
      {'userId': userId, 'type': type, 'message': message},
    );
    return result.lastInsertID.toInt();
  }

  static Future<String> _now(MySQLConnection connection) async {
    final result = await connection.execute(
      'SELECT UTC_TIMESTAMP(6) AS NowUtc',
    );
    return result.rows.first.reqStr('NowUtc');
  }

  @override
  Future<AccountStatusChange> changeStatus({
    required AdminIdentity admin,
    required String role,
    required int profileId,
    required String status,
    String? reason,
    Set<String>? allowedFrom,
  }) {
    if (!suspendableRoles.contains(role)) {
      throw ArgumentError.value(role, 'role');
    }
    return _transaction((connection) async {
      final profile = role == 'student'
          ? 'INNER JOIN studentprofile p ON p.UserID = u.UserId '
                'WHERE p.StudentID = :id'
          : 'INNER JOIN tutorprofile p ON p.UserID = u.UserId '
                'WHERE p.TutorID = :id';
      final found = await connection.execute(
        'SELECT u.UserId, u.AccountStatus, u.FirebaseUid FROM `user` u '
        "$profile AND u.Role = '$role' FOR UPDATE",
        {'id': profileId},
      );
      if (found.rows.isEmpty) throw const SuspensionNotFound();
      final row = found.rows.first;
      final userId = int.parse(row.reqStr('UserId'));
      final previous = row.reqStr('AccountStatus');
      final firebaseUid = row.reqStr('FirebaseUid');
      if (allowedFrom != null && !allowedFrom.contains(previous)) {
        throw AccountStatusLocked(previous);
      }

      if (previous == status) {
        if (status == 'Suspended') {
          throw const SuspensionConflict(
            'already_suspended',
            'This account is already suspended.',
          );
        }
        return AccountStatusChange(
          userId: userId,
          previousStatus: previous,
          status: status,
        );
      }
      final now = await _now(connection);

      AccountNotice? notice;
      if (status == 'Suspended') {
        if (reason == null ||
            reason.trim().length < suspensionReasonMinLength) {
          throw const SuspensionValidation('A suspension reason is required.');
        }
        final suspension = await connection.execute(
          '''
          INSERT INTO accountsuspension
            (UserID, SuspendedByAdminID, Reason, PreviousAccountStatus,
             SuspendedAtUtc, Status)
          VALUES (:userId, :adminId, :reason, :previous, :now, 'Active')
          ''',
          {
            'userId': userId,
            'adminId': admin.id,
            'reason': reason.trim(),
            'previous': previous,
            'now': now,
          },
        );
        final suspensionId = suspension.lastInsertID.toInt();
        final body = suspensionNoticeBody(reason.trim());
        final notificationId = await _insertNotification(
          connection,
          userId: userId,
          type: NotificationType.accountSuspended,
          message: body,
        );
        await connection.execute(
          'UPDATE accountsuspension SET NotificationID = :notificationId '
          'WHERE SuspensionID = :id',
          {'notificationId': notificationId, 'id': suspensionId},
        );
        notice = AccountNotice(
          notificationId: notificationId,
          firebaseUid: firebaseUid,
          firestoreId: 'suspension-$suspensionId',
          type: NotificationType.accountSuspended,
          body: body,
        );
      } else if (previous == 'Suspended') {
        // Reinstated or deactivated by an administrator: the suspension ends
        // and an undecided appeal is closed (not approved or rejected).
        final active = await connection.execute(
          'SELECT SuspensionID FROM accountsuspension WHERE UserID = :userId '
          "AND Status = 'Active' FOR UPDATE",
          {'userId': userId},
        );
        for (final s in active.rows) {
          final suspensionId = s.reqStr('SuspensionID');
          await connection.execute(
            '''
            UPDATE accountsuspension
            SET Status = 'Lifted', LiftedAtUtc = :now,
                LiftedByAdminID = :adminId, LiftReason = :liftReason
            WHERE SuspensionID = :id
            ''',
            {
              'now': now,
              'adminId': admin.id,
              'liftReason': status == 'Active' ? 'Reinstated' : 'Deactivated',
              'id': suspensionId,
            },
          );
          await connection.execute(
            '''
            UPDATE suspensionappeal
            SET Status = 'Closed', ReviewedByAdminID = :adminId,
                DecidedAtUtc = :now,
                DecisionNote = :note
            WHERE SuspensionID = :id AND Status = 'Pending'
            ''',
            {
              'adminId': admin.id,
              'now': now,
              'note': status == 'Active'
                  ? 'Closed: an administrator reinstated the account.'
                  : 'Closed: an administrator deactivated the account.',
              'id': suspensionId,
            },
          );
        }
      }

      await connection.execute(
        'UPDATE `user` SET AccountStatus = :status WHERE UserId = :userId',
        {'status': status, 'userId': userId},
      );
      return AccountStatusChange(
        userId: userId,
        previousStatus: previous,
        status: status,
        notice: notice,
      );
    });
  }

  @override
  Future<Map<String, Object?>?> suspensionFor(String firebaseUid) {
    return _read((connection) async {
      final user = await connection.execute(
        'SELECT UserId, Role, AccountStatus FROM `user` '
        "WHERE FirebaseUid = :uid AND Role IN ('student', 'tutor') LIMIT 1",
        {'uid': firebaseUid},
      );
      if (user.rows.isEmpty) return null;
      final u = user.rows.first;
      final latest = await connection.execute(
        '''
        SELECT s.SuspensionID, s.Reason, s.SuspendedAtUtc, s.Status,
               s.LiftedAtUtc, s.LiftReason,
               a.AppealID, a.Explanation, a.SubmittedAtUtc,
               a.Status AS AppealStatus, a.DecisionNote, a.DecidedAtUtc
        FROM accountsuspension s
        LEFT JOIN suspensionappeal a ON a.SuspensionID = s.SuspensionID
        WHERE s.UserID = :userId
        ORDER BY s.SuspendedAtUtc DESC, s.SuspensionID DESC
        LIMIT 1
        ''',
        {'userId': u.reqStr('UserId')},
      );
      final accountStatus = u.reqStr('AccountStatus');
      final row = latest.rows.isEmpty ? null : latest.rows.first;
      final suspension = row == null
          ? null
          : {
              'suspensionId': int.parse(row.reqStr('SuspensionID')),
              'reason': row.str('Reason'),
              'suspendedAt': _iso(row.str('SuspendedAtUtc')),
              'status': row.str('Status'),
              'liftedAt': _iso(row.str('LiftedAtUtc')),
              'liftReason': row.str('LiftReason'),
            };
      final appeal = row?.str('AppealID') == null
          ? null
          : {
              'appealId': int.parse(row!.reqStr('AppealID')),
              'explanation': row.str('Explanation'),
              'submittedAt': _iso(row.str('SubmittedAtUtc')),
              'status': row.str('AppealStatus'),
              'decisionNote': row.str('DecisionNote'),
              'decidedAt': _iso(row.str('DecidedAtUtc')),
            };
      return {
        'role': u.str('Role'),
        'accountStatus': accountStatus,
        'suspension': suspension,
        'appeal': appeal,
        'canAppeal':
            accountStatus == 'Suspended' &&
            suspension?['status'] == 'Active' &&
            appeal == null,
        'explanationMinLength': appealExplanationMinLength,
        'explanationMaxLength': appealExplanationMaxLength,
      };
    });
  }

  @override
  Future<Map<String, Object?>> submitAppeal(
    String firebaseUid,
    String explanation,
  ) {
    return _transaction((connection) async {
      final user = await connection.execute(
        'SELECT UserId, AccountStatus FROM `user` WHERE FirebaseUid = :uid '
        "AND Role IN ('student', 'tutor') LIMIT 1 FOR UPDATE",
        {'uid': firebaseUid},
      );
      if (user.rows.isEmpty) throw const SuspensionNotFound();
      final userId = int.parse(user.rows.first.reqStr('UserId'));
      if (user.rows.first.str('AccountStatus') != 'Suspended') {
        throw const SuspensionConflict(
          'not_suspended',
          'Only a suspended account can send an appeal.',
        );
      }
      final suspension = await connection.execute(
        'SELECT SuspensionID FROM accountsuspension WHERE UserID = :userId '
        "AND Status = 'Active' FOR UPDATE",
        {'userId': userId},
      );
      if (suspension.rows.isEmpty) {
        // Suspended before suspensions were recorded: nothing to appeal
        throw const SuspensionConflict(
          'no_suspension_record',
          'This suspension cannot be appealed here. Please contact support.',
        );
      }
      final suspensionId = suspension.rows.first.reqStr('SuspensionID');
      final existing = await connection.execute(
        'SELECT AppealID FROM suspensionappeal '
        'WHERE SuspensionID = :id FOR UPDATE',
        {'id': suspensionId},
      );
      if (existing.rows.isNotEmpty) {
        throw const SuspensionConflict(
          'appeal_exists',
          'You have already appealed this suspension.',
        );
      }
      final now = await _now(connection);
      try {
        final inserted = await connection.execute(
          '''
          INSERT INTO suspensionappeal
            (SuspensionID, UserID, Explanation, SubmittedAtUtc, Status)
          VALUES (:suspensionId, :userId, :explanation, :now, 'Pending')
          ''',
          {
            'suspensionId': suspensionId,
            'userId': userId,
            'explanation': explanation,
            'now': now,
          },
        );
        return {
          'appealId': inserted.lastInsertID.toInt(),
          'explanation': explanation,
          'submittedAt': _iso(now),
          'status': 'Pending',
          'decisionNote': null,
          'decidedAt': null,
        };
      } on MySQLServerException catch (error) {
        // uq_appeal_one_per_suspension: a concurrent request won the race
        if (error.errorCode == 1062) {
          throw const SuspensionConflict(
            'appeal_exists',
            'You have already appealed this suspension.',
          );
        }
        rethrow;
      }
    });
  }

  static const _appealSelect = '''
    SELECT a.AppealID, a.Explanation, a.SubmittedAtUtc, a.Status,
           a.DecisionNote, a.DecidedAtUtc, reviewer.Name AS ReviewerName,
           s.SuspensionID, s.Reason, s.SuspendedAtUtc,
           s.Status AS SuspensionStatus, s.LiftedAtUtc, s.LiftReason,
           suspender.Name AS SuspendedByName,
           u.UserId, u.Name, u.Email, u.PhoneNum, u.ProfilePhoto, u.Role,
           u.AccountStatus, u.Created_at, sp.StudentID, tp.TutorID
    FROM suspensionappeal a
    INNER JOIN accountsuspension s ON s.SuspensionID = a.SuspensionID
    INNER JOIN `user` u ON u.UserId = a.UserID
    LEFT JOIN studentprofile sp ON sp.UserID = u.UserId
    LEFT JOIN tutorprofile tp ON tp.UserID = u.UserId
    INNER JOIN admin suspending ON suspending.AdminID = s.SuspendedByAdminID
    INNER JOIN `user` suspender ON suspender.UserId = suspending.UserId
    LEFT JOIN admin reviewing ON reviewing.AdminID = a.ReviewedByAdminID
    LEFT JOIN `user` reviewer ON reviewer.UserId = reviewing.UserId
  ''';

  static Map<String, Object?> _appealJson(ResultSetRow r) => {
    'appealId': int.parse(r.reqStr('AppealID')),
    'status': r.str('Status'),
    'explanation': r.str('Explanation'),
    'submittedAt': _iso(r.str('SubmittedAtUtc')),
    'decisionNote': r.str('DecisionNote'),
    'decidedAt': _iso(r.str('DecidedAtUtc')),
    'reviewedBy': r.str('ReviewerName'),
    'suspension': {
      'suspensionId': int.parse(r.reqStr('SuspensionID')),
      'reason': r.str('Reason'),
      'suspendedAt': _iso(r.str('SuspendedAtUtc')),
      'suspendedBy': r.str('SuspendedByName'),
      'status': r.str('SuspensionStatus'),
      'liftedAt': _iso(r.str('LiftedAtUtc')),
      'liftReason': r.str('LiftReason'),
    },
    'user': {
      'userId': int.parse(r.reqStr('UserId')),
      'role': r.str('Role'),
      'profileId': _int(r.str('StudentID')) ?? _int(r.str('TutorID')),
      'name': r.str('Name'),
      'email': r.str('Email'),
      'phone': r.str('PhoneNum'),
      'photoUrl': r.str('ProfilePhoto'),
      'accountStatus': r.str('AccountStatus'),
      'joinedAt': r.str('Created_at'),
    },
  };

  @override
  Future<Map<String, Object?>> listAppeals({
    required String status,
    required Set<String> roles,
  }) {
    final allowed = roles.where(suspendableRoles.contains).toList()..sort();
    if (allowed.isEmpty) {
      return Future.value({
        'summary': {'pending': 0},
        'appeals': <Object?>[],
      });
    }
    // The role names come from suspendableRoles, never from the request
    final roleList = allowed.map((r) => "'$r'").join(', ');
    return _read((connection) async {
      final rows = await connection.execute(
        '''
        $_appealSelect
        WHERE u.Role IN ($roleList)
          AND (:status = 'all' OR a.Status = :status)
        ORDER BY (a.Status = 'Pending') DESC, a.SubmittedAtUtc DESC,
                 a.AppealID DESC
        LIMIT 200
        ''',
        {'status': status},
      );
      final pending = await connection.execute(
        'SELECT COUNT(*) AS n FROM suspensionappeal a '
        'INNER JOIN `user` u ON u.UserId = a.UserID '
        "WHERE a.Status = 'Pending' AND u.Role IN ($roleList)",
      );
      return {
        'summary': {'pending': int.parse(pending.rows.first.reqStr('n'))},
        'appeals': [for (final r in rows.rows) _appealJson(r)],
      };
    });
  }

  @override
  Future<AppealDecision> decideAppeal({
    required AdminIdentity admin,
    required int appealId,
    required bool approve,
    required String? note,
    required Set<String> roles,
  }) {
    return _transaction((connection) async {
      // Find the user without locking, then lock in the usual order
      final owner = await connection.execute(
        'SELECT UserID FROM suspensionappeal WHERE AppealID = :id',
        {'id': appealId},
      );
      if (owner.rows.isEmpty) {
        throw const SuspensionNotFound('Appeal not found.');
      }
      final userId = int.parse(owner.rows.first.reqStr('UserID'));
      final user = await connection.execute(
        'SELECT Role, AccountStatus, FirebaseUid FROM `user` '
        'WHERE UserId = :userId FOR UPDATE',
        {'userId': userId},
      );
      final role = user.rows.first.reqStr('Role');
      if (!roles.contains(role)) {
        throw AdminPermissionDenied(
          suspensionManagePermission[role] ?? 'admin.users.manage',
        );
      }
      final appeal = await connection.execute(
        'SELECT a.Status, a.SuspensionID, s.Status AS SuspensionStatus, '
        's.PreviousAccountStatus FROM suspensionappeal a '
        'INNER JOIN accountsuspension s ON s.SuspensionID = a.SuspensionID '
        'WHERE a.AppealID = :id FOR UPDATE',
        {'id': appealId},
      );
      final a = appeal.rows.first;
      if (a.str('Status') != 'Pending') {
        throw const SuspensionConflict(
          'appeal_already_decided',
          'This appeal has already been decided.',
        );
      }
      final suspensionId = a.reqStr('SuspensionID');
      if (approve &&
          (a.str('SuspensionStatus') != 'Active' ||
              user.rows.first.str('AccountStatus') != 'Suspended')) {
        throw const SuspensionConflict(
          'suspension_not_active',
          'The account is no longer suspended.',
        );
      }
      final now = await _now(connection);
      final type = approve
          ? NotificationType.appealApproved
          : NotificationType.appealRejected;
      final body = appealDecisionNoticeBody(approved: approve, note: note);
      final notificationId = await _insertNotification(
        connection,
        userId: userId,
        type: type,
        message: body,
      );
      await connection.execute(
        '''
        UPDATE suspensionappeal
        SET Status = :status, ReviewedByAdminID = :adminId,
            DecisionNote = :note, DecidedAtUtc = :now,
            DecisionNotificationID = :notificationId
        WHERE AppealID = :id AND Status = 'Pending'
        ''',
        {
          'status': approve ? 'Approved' : 'Rejected',
          'adminId': admin.id,
          'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
          'now': now,
          'notificationId': notificationId,
          'id': appealId,
        },
      );
      if (approve) {
        await connection.execute(
          '''
          UPDATE accountsuspension
          SET Status = 'Lifted', LiftedAtUtc = :now,
              LiftedByAdminID = :adminId, LiftReason = 'AppealApproved'
          WHERE SuspensionID = :id AND Status = 'Active'
          ''',
          {'now': now, 'adminId': admin.id, 'id': suspensionId},
        );
        // Back to what it was before (Active, or Pending for a tutor still
        // awaiting approval); never to Suspended
        final previous = a.str('PreviousAccountStatus');
        await connection.execute(
          'UPDATE `user` SET AccountStatus = :status WHERE UserId = :userId',
          {
            'status': previous == null || previous == 'Suspended'
                ? 'Active'
                : previous,
            'userId': userId,
          },
        );
      }
      final decided = await connection.execute(
        '$_appealSelect WHERE a.AppealID = :id',
        {'id': appealId},
      );
      return AppealDecision(
        appeal: _appealJson(decided.rows.first),
        notice: AccountNotice(
          notificationId: notificationId,
          firebaseUid: user.rows.first.reqStr('FirebaseUid'),
          firestoreId: 'appeal-$appealId-decision',
          type: type,
          body: body,
        ),
      );
    });
  }

  @override
  Future<List<AccountNotice>> undeliveredNotices(String firebaseUid) {
    return _read((connection) async {
      final rows = await connection.execute(
        '''
        SELECT n.NotificationID, n.Type, n.Message,
               CONCAT('suspension-', s.SuspensionID) AS FirestoreId
        FROM accountsuspension s
        INNER JOIN notification n ON n.NotificationID = s.NotificationID
        INNER JOIN `user` u ON u.UserId = s.UserID
        WHERE u.FirebaseUid = :uid AND n.FirestoreNotificationID IS NULL
        UNION ALL
        SELECT n.NotificationID, n.Type, n.Message,
               CONCAT('appeal-', a.AppealID, '-decision') AS FirestoreId
        FROM suspensionappeal a
        INNER JOIN notification n ON n.NotificationID = a.DecisionNotificationID
        INNER JOIN `user` u ON u.UserId = a.UserID
        WHERE u.FirebaseUid = :uid AND n.FirestoreNotificationID IS NULL
        ORDER BY NotificationID
        LIMIT 20
        ''',
        {'uid': firebaseUid},
      );
      return [
        for (final r in rows.rows)
          AccountNotice(
            notificationId: int.parse(r.reqStr('NotificationID')),
            firebaseUid: firebaseUid,
            firestoreId: r.reqStr('FirestoreId'),
            type: r.reqStr('Type'),
            body: r.reqStr('Message'),
          ),
      ];
    });
  }

  @override
  Future<void> markDelivered(int notificationId, String firestoreId) {
    return _read((connection) async {
      await connection.execute(
        'UPDATE notification SET FirestoreNotificationID = :firestoreId '
        'WHERE NotificationID = :id AND FirestoreNotificationID IS NULL',
        {'firestoreId': firestoreId, 'id': notificationId},
      );
    });
  }
}
