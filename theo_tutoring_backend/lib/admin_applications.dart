import 'package:theo_tutoring_backend/admin_refunds.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/db_row.dart';

// ignore_for_file: public_member_api_docs

abstract interface class AdminApplicationsRepository {
  Future<List<Map<String, Object?>>> fetchApplications();
  Future<void> reviewApplication({
    required int applicationId,
    required String decision,
    required String? feedback,
    required AdminIdentity admin,
  });
}

class AdminApplicationValidation implements Exception {
  const AdminApplicationValidation(this.message);
  final String message;
}

class AdminApplicationNotFound implements Exception {
  const AdminApplicationNotFound();
}

class AdminApplicationConflict implements Exception {
  const AdminApplicationConflict(this.message);
  final String message;
}

typedef AdminApplicationsRepositoryFactory =
    AdminApplicationsRepository Function();

class MySqlAdminApplicationsRepository implements AdminApplicationsRepository {
  MySqlAdminApplicationsRepository({
    Future<MySQLConnection> Function()? connectionFactory,
  }) : _connectionFactory = connectionFactory ?? createIndependentConnection;

  final Future<MySQLConnection> Function() _connectionFactory;

  @override
  Future<List<Map<String, Object?>>> fetchApplications() async {
    final connection = await _connectionFactory();
    try {
      final applications = await connection.execute('''
        SELECT ta.TutApplication, ta.TutorID, ta.Status, ta.SubmittedAt,
          ta.AdminFeedback, ta.Review_at, reviewer.Name AS ReviewerName,
          tp.VerificationStat, tp.Bio, tp.Experience,
          tp.Certificate, tp.IdDocument, u.Name, u.Email, u.PhoneNum,
          u.ProfilePhoto, u.AccountStatus
        FROM tutorapplication ta
        INNER JOIN tutorprofile tp ON tp.TutorID = ta.TutorID
        INNER JOIN `user` u ON u.UserId = tp.UserId
        LEFT JOIN admin review_admin ON review_admin.AdminID = ta.AdminID
        LEFT JOIN `user` reviewer ON reviewer.UserId = review_admin.UserId
        ORDER BY ta.SubmittedAt DESC, ta.TutApplication DESC
        ''');

      final rows = applications.rows.toList();
      if (rows.isEmpty) return [];

      final tutorIds = <int>{};
      for (final row in rows) {
        final tutorId = int.parse(row.reqStr('TutorID'));
        tutorIds.add(tutorId);
      }
      final parameters = <String, dynamic>{
        for (final (index, tutorId) in tutorIds.indexed) 'tutor$index': tutorId,
      };
      final placeholders = [
        for (final key in parameters.keys) ':$key',
      ].join(', ');

      final qualificationResult = await connection.execute(
        '''
        SELECT TutorID, Degree, Institution
        FROM qualification
        WHERE TutorID IN ($placeholders)
        ORDER BY TutorID ASC, QualificationID ASC
        ''',
        parameters,
      );
      final qualificationsByTutor = <int, List<String>>{};
      for (final row in qualificationResult.rows) {
        final tutorId = int.parse(row.reqStr('TutorID'));
        final degree = row.reqStr('Degree');
        final institution = row.reqStr('Institution');
        qualificationsByTutor
            .putIfAbsent(tutorId, () => [])
            .add('$degree — $institution');
      }

      final subjectsResult = await connection.execute(
        '''
        SELECT ts.TutorID, s.subjectName
        FROM tutorsubjects ts
        INNER JOIN subjects s ON s.subjectId = ts.SubjectID
        WHERE ts.TutorID IN ($placeholders)
        ORDER BY ts.TutorID ASC, s.subjectName ASC
        ''',
        parameters,
      );
      final subjectsByTutor = <int, List<String>>{};
      for (final row in subjectsResult.rows) {
        final tutorId = int.parse(row.reqStr('TutorID'));
        subjectsByTutor
            .putIfAbsent(tutorId, () => [])
            .add(row.reqStr('subjectName'));
      }

      return [
        for (final row in rows)
          _applicationJson(
            row.str,
            qualificationsByTutor,
            subjectsByTutor,
          ),
      ];
    } finally {
      await connection.close();
    }
  }

  @override
  Future<void> reviewApplication({
    required int applicationId,
    required String decision,
    required String? feedback,
    required AdminIdentity admin,
  }) async {
    final status = switch (decision) {
      'approve' => 'Approved',
      'reject' => 'Rejected',
      _ => throw const AdminApplicationValidation('Invalid decision.'),
    };
    final connection = await _connectionFactory();
    try {
      await connection.transactional((transaction) async {
        final current = await transaction.execute(
          '''
          SELECT ta.TutorID, ta.Status
          FROM tutorapplication ta
          WHERE ta.TutApplication = :applicationId
          FOR UPDATE
          ''',
          {'applicationId': applicationId},
        );
        if (current.rows.isEmpty) throw const AdminApplicationNotFound();
        if (current.rows.first.str('Status') != 'Pending') {
          throw const AdminApplicationConflict(
            'This application has already been reviewed.',
          );
        }
        final tutorId = int.parse(current.rows.first.reqStr('TutorID'));

        final update = await transaction.execute(
          '''
          UPDATE tutorapplication
          SET Status = :status,
              AdminFeedback = :feedback,
              AdminID = :adminId,
              Review_at = NOW()
          WHERE TutApplication = :applicationId AND Status = 'Pending'
          ''',
          {
            'status': status,
            'feedback': feedback,
            'adminId': admin.id,
            'applicationId': applicationId,
          },
        );
        if (update.affectedRows != BigInt.one) {
          throw const AdminApplicationConflict(
            'This application has already been reviewed.',
          );
        }

        await transaction.execute(
          '''
          UPDATE tutorprofile
          SET VerificationStat = :status
          WHERE TutorID = :tutorId
          ''',
          {'status': status, 'tutorId': tutorId},
        );
        await transaction.execute(
          '''
          UPDATE `user` u
          INNER JOIN tutorprofile tp ON tp.UserID = u.UserId
          SET u.AccountStatus = :accountStatus
          WHERE tp.TutorID = :tutorId AND u.Role = 'tutor'
          ''',
          {
            'accountStatus': status == 'Approved' ? 'Active' : 'Rejected',
            'tutorId': tutorId,
          },
        );
      });
    } finally {
      if (connection.connected) await connection.close();
    }
  }

  Map<String, Object?> _applicationJson(
    String? Function(String) value,
    Map<int, List<String>> qualificationsByTutor,
    Map<int, List<String>> subjectsByTutor,
  ) {
    final tutorId = int.parse(value('TutorID')!);
    return {
      'id': int.parse(value('TutApplication')!),
      'fullName': value('Name'),
      'email': value('Email'),
      'phone': value('PhoneNum'),
      'photoUrl': value('ProfilePhoto'),
      'status': value('Status'),
      'accountStatus': value('AccountStatus'),
      'verificationStatus': value('VerificationStat'),
      'appliedAt': value('SubmittedAt'),
      'adminFeedback': value('AdminFeedback'),
      'reviewedAt': value('Review_at'),
      'reviewerName': value('ReviewerName'),
      'bio': value('Bio'),
      'experience': value('Experience'),
      'qualifications': qualificationsByTutor[tutorId] ?? <String>[],
      'subjects': subjectsByTutor[tutorId] ?? <String>[],
      'certificateUrl': value('Certificate'),
      'idDocumentUrl': value('IdDocument'),
    };
  }
}
