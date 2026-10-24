import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/firestore_endpoint.dart';
import 'package:theo_tutoring_backend/notifications.dart';

// Run by firestore_endpoint_test.dart in a child process whose environment
// it controls (Platform.environment cannot change inside a running test).
// Uses the real settings, with nothing injected except where named. Every
// HTTP request goes to a fake client, and no step asks FirebaseAdmin for a
// token, so nothing reaches the network even if a guard were broken.
Future<void> main() async {
  _report('instance', () => FirebaseAdmin.instance);
  _report(
    'injectedProduction',
    () => FirebaseAdmin.fromEnvironment(
      endpoint: () => FirestoreEndpoint.production,
    ),
  );
  await _storeRequest(
    'notificationStore',
    (client) => NotificationStore.fromFirebaseAdmin(client: client),
  );
  await _storeRequest(
    'directProductionStore',
    (client) => NotificationStore(
      projectId: 'demo-theotutoring',
      accessToken: () async => FirestoreEndpoint.emulatorAccessToken,
      client: client,
    ),
  );
}

void _report(String step, Object Function() create) {
  try {
    create();
    stdout.writeln('$step: CREATED');
  } on FirebaseAdminException catch (e) {
    stdout.writeln('$step: REFUSED ${e.message}');
  } on Object catch (e) {
    stdout.writeln('$step: ERROR ${e.runtimeType}');
  }
}

/// Builds a store with a recording fake client and lists one user's
/// notifications. Reports where the request went; never prints a token
/// other than the emulator's fixed one.
Future<void> _storeRequest(
  String step,
  NotificationStore Function(http.Client client) build,
) async {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    return http.Response('[]', 200);
  });
  try {
    await build(client).list('probe-user');
    final request = requests.single;
    final auth = request.headers['Authorization'] == 'Bearer owner'
        ? 'emulator-token'
        : 'other-token';
    stdout.writeln('$step: SENT ${request.url} $auth');
  } on FirebaseAdminException catch (e) {
    stdout.writeln('$step: REFUSED requests=${requests.length} ${e.message}');
  } on Object catch (e) {
    stdout.writeln('$step: ERROR ${e.runtimeType}');
  }
}
