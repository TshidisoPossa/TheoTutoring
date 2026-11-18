import 'package:theo_tutoring_backend/account_suspensions.dart';
import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:theo_tutoring_backend/notifications.dart';

/// One student or tutor in [FakeSuspensionStore].
class FakeAccount {
  FakeAccount({
    required this.userId,
    required this.role,
    required this.profileId,
    required this.uid,
    this.status = 'Active',
  });

  final int userId;
  final String role;
  final int profileId;
  final String uid;
  String status;
}

class FakeSuspension {
  FakeSuspension(
    this.id,
    this.userId,
    this.adminId,
    this.reason,
    this.previous,
  );
  final int id;
  final int userId;
  final int adminId;
  final String reason;
  final String previous;
  String status = 'Active';
  String? liftReason;
  int? liftedBy;
  int? notificationId;
}

class FakeAppeal {
  FakeAppeal(this.id, this.suspensionId, this.userId, this.explanation);
  final int id;
  final int suspensionId;
  final int userId;
  final String explanation;
  String status = 'Pending';
  int? reviewedBy;
  String? note;
  int? notificationId;
}

class FakeNotification {
  FakeNotification(this.id, this.userId, this.type, this.message);
  final int id;
  final int userId;
  final String type;
  final String message;
  String? firestoreId;
}

/// In-memory AccountSuspensionRepository following the same rules as the
/// MySQL one (see lib/account_suspensions.dart), for route tests.
class FakeSuspensionStore implements AccountSuspensionRepository {
  final accounts = <FakeAccount>[];
  final suspensions = <FakeSuspension>[];
  final appeals = <FakeAppeal>[];
  final notifications = <FakeNotification>[];

  /// Set to make every call fail, like a lost database connection.
  Exception? failWith;

  FakeAccount add({
    required String role,
    required int profileId,
    String status = 'Active',
  }) {
    final account = FakeAccount(
      userId: 100 + accounts.length,
      role: role,
      profileId: profileId,
      uid: 'uid-$role-$profileId',
      status: status,
    );
    accounts.add(account);
    return account;
  }

  FakeAccount account(String role, int profileId) =>
      accounts.firstWhere((a) => a.role == role && a.profileId == profileId);

  FakeSuspension? activeFor(int userId) => suspensions
      .where((s) => s.userId == userId && s.status == 'Active')
      .firstOrNull;

  int _notify(int userId, String type, String message) {
    final n = FakeNotification(notifications.length + 1, userId, type, message);
    notifications.add(n);
    return n.id;
  }

  void _check() {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<AccountStatusChange> changeStatus({
    required AdminIdentity admin,
    required String role,
    required int profileId,
    required String status,
    String? reason,
    Set<String>? allowedFrom,
  }) async {
    _check();
    final a = accounts
        .where((a) => a.role == role && a.profileId == profileId)
        .firstOrNull;
    if (a == null) throw const SuspensionNotFound();
    final previous = a.status;
    if (allowedFrom != null && !allowedFrom.contains(previous)) {
      throw AccountStatusLocked(previous);
    }
    if (previous == status) {
      if (status == 'Suspended') {
        throw const SuspensionConflict('already_suspended', 'Already.');
      }
      return AccountStatusChange(
        userId: a.userId,
        previousStatus: previous,
        status: status,
      );
    }
    AccountNotice? notice;
    if (status == 'Suspended') {
      final s = FakeSuspension(
        suspensions.length + 1,
        a.userId,
        admin.id,
        reason!,
        previous,
      );
      suspensions.add(s);
      final body = suspensionNoticeBody(reason);
      s.notificationId = _notify(
        a.userId,
        NotificationType.accountSuspended,
        body,
      );
      notice = AccountNotice(
        notificationId: s.notificationId!,
        firebaseUid: a.uid,
        firestoreId: 'suspension-${s.id}',
        type: NotificationType.accountSuspended,
        body: body,
      );
    } else if (previous == 'Suspended') {
      final s = activeFor(a.userId);
      if (s != null) {
        s
          ..status = 'Lifted'
          ..liftedBy = admin.id
          ..liftReason = status == 'Active' ? 'Reinstated' : 'Deactivated';
        for (final appeal in appeals.where(
          (x) => x.suspensionId == s.id && x.status == 'Pending',
        )) {
          appeal
            ..status = 'Closed'
            ..reviewedBy = admin.id;
        }
      }
    }
    a.status = status;
    return AccountStatusChange(
      userId: a.userId,
      previousStatus: previous,
      status: status,
      notice: notice,
    );
  }

  FakeAccount? _byUid(String uid) =>
      accounts.where((a) => a.uid == uid).firstOrNull;

  @override
  Future<Map<String, Object?>?> suspensionFor(String firebaseUid) async {
    _check();
    final a = _byUid(firebaseUid);
    if (a == null) return null;
    final latest = suspensions.where((s) => s.userId == a.userId).lastOrNull;
    final appeal = latest == null
        ? null
        : appeals.where((x) => x.suspensionId == latest.id).firstOrNull;
    return {
      'role': a.role,
      'accountStatus': a.status,
      'suspension': latest == null
          ? null
          : {
              'suspensionId': latest.id,
              'reason': latest.reason,
              'status': latest.status,
              'liftReason': latest.liftReason,
            },
      'appeal': appeal == null
          ? null
          : {
              'appealId': appeal.id,
              'explanation': appeal.explanation,
              'status': appeal.status,
              'decisionNote': appeal.note,
            },
      'canAppeal':
          a.status == 'Suspended' &&
          latest?.status == 'Active' &&
          appeal == null,
    };
  }

  @override
  Future<Map<String, Object?>> submitAppeal(
    String firebaseUid,
    String explanation,
  ) async {
    _check();
    final a = _byUid(firebaseUid);
    if (a == null) throw const SuspensionNotFound();
    if (a.status != 'Suspended') {
      throw const SuspensionConflict('not_suspended', 'Not suspended.');
    }
    final s = activeFor(a.userId);
    if (s == null) {
      throw const SuspensionConflict('no_suspension_record', 'No record.');
    }
    if (appeals.any((x) => x.suspensionId == s.id)) {
      throw const SuspensionConflict('appeal_exists', 'Already appealed.');
    }
    final appeal = FakeAppeal(appeals.length + 1, s.id, a.userId, explanation);
    appeals.add(appeal);
    return {
      'appealId': appeal.id,
      'explanation': explanation,
      'status': 'Pending',
    };
  }

  @override
  Future<Map<String, Object?>> listAppeals({
    required String status,
    required Set<String> roles,
  }) async {
    _check();
    lastListed = (status: status, roles: roles);
    final rows = [
      for (final appeal in appeals)
        if (roles.contains(_owner(appeal).role) &&
            (status == 'all' || appeal.status.toLowerCase() == status))
          _json(appeal),
    ];
    return {
      'summary': {
        'pending': appeals
            .where(
              (x) => x.status == 'Pending' && roles.contains(_owner(x).role),
            )
            .length,
      },
      'appeals': rows,
    };
  }

  ({String status, Set<String> roles})? lastListed;

  FakeAccount _owner(FakeAppeal appeal) =>
      accounts.firstWhere((a) => a.userId == appeal.userId);

  Map<String, Object?> _json(FakeAppeal appeal) {
    final s = suspensions.firstWhere((x) => x.id == appeal.suspensionId);
    final u = _owner(appeal);
    return {
      'appealId': appeal.id,
      'status': appeal.status,
      'explanation': appeal.explanation,
      'decisionNote': appeal.note,
      'suspension': {
        'suspensionId': s.id,
        'reason': s.reason,
        'status': s.status,
      },
      'user': {
        'userId': u.userId,
        'role': u.role,
        'profileId': u.profileId,
        'accountStatus': u.status,
      },
    };
  }

  @override
  Future<AppealDecision> decideAppeal({
    required AdminIdentity admin,
    required int appealId,
    required bool approve,
    required String? note,
    required Set<String> roles,
  }) async {
    _check();
    final appeal = appeals.where((x) => x.id == appealId).firstOrNull;
    if (appeal == null) throw const SuspensionNotFound('Appeal not found.');
    final u = _owner(appeal);
    if (!roles.contains(u.role)) {
      throw AdminPermissionDenied(suspensionManagePermission[u.role]!);
    }
    if (appeal.status != 'Pending') {
      throw const SuspensionConflict('appeal_already_decided', 'Decided.');
    }
    final s = suspensions.firstWhere((x) => x.id == appeal.suspensionId);
    if (approve && (s.status != 'Active' || u.status != 'Suspended')) {
      throw const SuspensionConflict('suspension_not_active', 'Not active.');
    }
    final type = approve
        ? NotificationType.appealApproved
        : NotificationType.appealRejected;
    final body = appealDecisionNoticeBody(approved: approve, note: note);
    appeal
      ..status = approve ? 'Approved' : 'Rejected'
      ..reviewedBy = admin.id
      ..note = note
      ..notificationId = _notify(u.userId, type, body);
    if (approve) {
      s
        ..status = 'Lifted'
        ..liftReason = 'AppealApproved'
        ..liftedBy = admin.id;
      u.status = s.previous == 'Suspended' ? 'Active' : s.previous;
    }
    return AppealDecision(
      appeal: _json(appeal),
      notice: AccountNotice(
        notificationId: appeal.notificationId!,
        firebaseUid: u.uid,
        firestoreId: 'appeal-$appealId-decision',
        type: type,
        body: body,
      ),
    );
  }

  @override
  Future<List<AccountNotice>> undeliveredNotices(String firebaseUid) async {
    _check();
    final a = _byUid(firebaseUid);
    if (a == null) return const [];
    return [
      for (final s in suspensions)
        if (s.userId == a.userId)
          for (final n in notifications)
            if (n.id == s.notificationId && n.firestoreId == null)
              AccountNotice(
                notificationId: n.id,
                firebaseUid: firebaseUid,
                firestoreId: 'suspension-${s.id}',
                type: n.type,
                body: n.message,
              ),
    ];
  }

  @override
  Future<void> markDelivered(int notificationId, String firestoreId) async {
    _check();
    notifications.firstWhere((n) => n.id == notificationId).firestoreId ??=
        firestoreId;
  }
}

/// Records every notice "sent"; set [fail] to simulate Firestore being down.
class RecordingSender {
  final sent = <AccountNotice>[];
  bool fail = false;

  Future<void> call(AccountNotice notice) async {
    if (fail) throw Exception('Firestore unavailable');
    sent.add(notice);
  }
}
