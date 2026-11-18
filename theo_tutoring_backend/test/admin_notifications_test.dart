import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/admin_notifications.dart';
import 'package:theo_tutoring_backend/notifications.dart';

// Admin notifications: one card per active admin, each event only once.
// MySQL and Firestore are fakes; nothing real is written.

class _MockConnection extends Mock implements MySQLConnection {}

class _MockResult extends Mock implements IResultSet {}

class _MockRow extends Mock implements ResultSetRow {}

MySQLConnection _admins(List<String?> uids) {
  final rows = [
    for (final uid in uids)
      _MockRow()..stub(uid),
  ];
  final result = _MockResult();
  when(() => result.rows).thenReturn(rows);
  final connection = _MockConnection();
  when(() => connection.execute(any())).thenAnswer((_) async => result);
  return connection;
}

extension on _MockRow {
  void stub(String? uid) =>
      when(() => colByName('FirebaseUid')).thenReturn(uid);
}

const _notice = Notice(
  id: 'admin-report-7',
  type: NotificationType.reportSubmitted,
  title: 'New report',
  body: 'Lerato filed a report. Review it on the Reports page.',
);

void main() {
  late List<http.Request> requests;

  NotificationStore store(int Function(http.Request) status) {
    requests = [];
    return NotificationStore(
      projectId: 'demo',
      accessToken: () async => 'token',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', status(request));
      }),
    );
  }

  test('the admin types are valid notification types', () {
    expect(
      NotificationType.all,
      containsAll([
        NotificationType.applicationSubmitted,
        NotificationType.reportSubmitted,
        NotificationType.refundRequested,
      ]),
    );
  });

  test('every active admin gets the notification once', () async {
    final told = await notifyAdmins(
      _notice,
      connection: _admins(['admin-a', 'admin-b', null, '']),
      store: store((_) => 200),
    );
    expect(told, 2); // admins without a Firebase account are skipped
    expect(requests.map((r) => r.url.path), [
      contains('/notifications/admin-a/items'),
      contains('/notifications/admin-b/items'),
    ]);
    // Fixed id: the same event is never written twice
    expect(requests.first.url.queryParameters['documentId'], 'admin-report-7');
    final fields =
        (jsonDecode(requests.first.body) as Map<String, dynamic>)['fields']
            as Map<String, dynamic>;
    expect(fields['type'], {'stringValue': 'ReportSubmitted'});
    expect(fields['title'], {'stringValue': 'New report'});
    expect(fields['read'], {'booleanValue': false});
  });

  test('an admin who already has it is not counted again', () async {
    final told = await notifyAdmins(
      _notice,
      connection: _admins(['admin-a', 'admin-b']),
      // ALREADY_EXISTS for admin-a
      store: store((r) => r.url.path.contains('admin-a') ? 409 : 200),
    );
    expect(told, 1);
  });

  test('one failing admin does not stop the others', () async {
    final told = await notifyAdmins(
      _notice,
      connection: _admins(['admin-a', 'admin-b']),
      store: store((r) => r.url.path.contains('admin-a') ? 500 : 200),
    );
    expect(told, 1);
    expect(requests, hasLength(2));
  });

  test('no admins means nothing is written', () async {
    final told = await notifyAdmins(
      _notice,
      connection: _admins([]),
      store: store((_) => 200),
    );
    expect(told, 0);
    expect(requests, isEmpty);
  });

  test('readResponseJson gives the body and an identical response', () async {
    final (response, body) = await readResponseJson(
      Response.json(statusCode: 201, body: {'reportId': 7}),
    );
    expect(body, {'reportId': 7});
    expect(response.statusCode, 201);
    expect(jsonDecode(await response.body()), {'reportId': 7});
  });

  test('readResponseJson copes with a body that is not JSON', () async {
    final (response, body) = await readResponseJson(
      Response(statusCode: 405, body: 'Method not allowed'),
    );
    expect(body, isNull);
    expect(await response.body(), 'Method not allowed');
  });
}
