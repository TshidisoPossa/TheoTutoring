import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/firestore_endpoint.dart';

// No network and no real settings: every test passes its own process
// environment and .env values.

SettingLookup _lookup(Map<String, String> values) =>
    (key) => values[key];

const _host = firestoreEmulatorHostVariable;
const _project = firestoreEmulatorProjectVariable;

FirestoreEndpoint _resolve({
  Map<String, String> process = const {},
  Map<String, String> file = const {},
}) => FirestoreEndpoint.resolve(
  processEnvironment: _lookup(process),
  dotEnvFile: _lookup(file),
);

final _emulator = _resolve(
  process: {_host: '127.0.0.1:8085', _project: 'demo-theotutoring'},
);

Matcher _endpointError(String fragment) => throwsA(
  isA<FirestoreEndpointException>().having(
    (e) => e.message,
    'message',
    contains(fragment),
  ),
);

Matcher _adminError(String fragment) => throwsA(
  isA<FirebaseAdminException>().having(
    (e) => e.message,
    'message',
    contains(fragment),
  ),
);

void main() {
  group('FirestoreEndpoint.resolve', () {
    group('absent', () {
      test('no emulator host anywhere is production', () {
        final endpoint = _resolve();
        expect(endpoint.isEmulator, isFalse);
        expect(endpoint.baseUri, Uri.https('firestore.googleapis.com'));
        expect(endpoint.projectId, isNull);
        expect(endpoint.accessToken, isNull);
      });

      test('an unrelated or odd GCLOUD_PROJECT does not affect production', () {
        final endpoint = _resolve(
          process: {_project: 'theotutoring-2e83f'},
          file: {_project: 'something-else'},
        );
        expect(endpoint.isEmulator, isFalse);
      });
    });

    group('valid emulator settings', () {
      test('from the process environment', () {
        expect(_emulator.isEmulator, isTrue);
        expect(_emulator.baseUri, Uri.http('127.0.0.1:8085'));
        expect(_emulator.projectId, 'demo-theotutoring');
        expect(_emulator.accessToken, 'owner');
      });

      test('from .env only', () {
        final endpoint = _resolve(
          file: {_host: '127.0.0.1:8085', _project: 'demo-theotutoring'},
        );
        expect(endpoint.isEmulator, isTrue);
        expect(endpoint.projectId, 'demo-theotutoring');
      });

      test('the same values in both places (spaces ignored)', () {
        final endpoint = _resolve(
          process: {_host: '127.0.0.1:8085', _project: 'demo-theotutoring'},
          file: {_host: ' 127.0.0.1:8085 ', _project: 'demo-theotutoring '},
        );
        expect(endpoint.isEmulator, isTrue);
      });

      test('host and project may come from different places', () {
        final endpoint = _resolve(
          process: {_host: '127.0.0.1:8085'},
          file: {_project: 'demo-theotutoring'},
        );
        expect(endpoint.projectId, 'demo-theotutoring');
      });

      for (final host in ['localhost:8085', '[::1]:8085', '127.0.0.1:8085/']) {
        test('$host is accepted and still uses 127.0.0.1:8085', () {
          final endpoint = _resolve(
            process: {_host: host, _project: 'demo-theotutoring'},
          );
          expect(endpoint.baseUri, Uri.http('127.0.0.1:8085'));
        });
      }
    });

    group('conflicting settings', () {
      test('different hosts in the process environment and .env', () {
        expect(
          () => _resolve(
            process: {_host: '127.0.0.1:8085', _project: 'demo-theotutoring'},
            file: {_host: 'localhost:8085'},
          ),
          _endpointError('$_host differs'),
        );
      });

      test('different projects in the process environment and .env', () {
        expect(
          () => _resolve(
            process: {_host: '127.0.0.1:8085', _project: 'demo-theotutoring'},
            file: {_project: 'demo-other'},
          ),
          _endpointError('$_project differs'),
        );
      });

      test('a conflict message does not echo the values', () {
        try {
          _resolve(
            process: {_host: '127.0.0.1:8085', _project: 'demo-a'},
            file: {_host: '127.0.0.1:8085', _project: 'demo-secretish'},
          );
          fail('expected a FirestoreEndpointException');
        } on FirestoreEndpointException catch (e) {
          expect(e.message, isNot(contains('demo-secretish')));
        }
      });
    });

    group('invalid emulator host', () {
      final invalid = {
        'a production host': 'firestore.googleapis.com:443',
        'another machine': '10.0.0.5:8085',
        'a look-alike domain': '127.0.0.1.evil.example:8085',
        'no port': '127.0.0.1',
        'the wrong port': '127.0.0.1:8080',
        'a scheme': 'http://127.0.0.1:8085',
        'a path': '127.0.0.1:8085/v1',
        'user info': 'user@127.0.0.1:8085',
        'a query': '127.0.0.1:8085?x=1',
      };
      for (final MapEntry(key: name, value: host) in invalid.entries) {
        test('rejects $name', () {
          expect(
            () => _resolve(
              process: {_host: host, _project: 'demo-theotutoring'},
            ),
            throwsA(isA<FirestoreEndpointException>()),
          );
        });
      }

      test('an empty host is an error, not production', () {
        expect(
          () => _resolve(file: {_host: '  '}),
          _endpointError('$_host is set but empty'),
        );
      });
    });

    group('invalid emulator project', () {
      test('a missing project is an error', () {
        expect(
          () => _resolve(process: {_host: '127.0.0.1:8085'}),
          _endpointError('$_project is not'),
        );
      });

      final invalid = {
        'the real project': 'theotutoring-2e83f',
        'a bare demo- prefix': 'demo-',
        'upper case': 'DEMO-theotutoring',
        'a path': 'demo-x/../theotutoring-2e83f',
        'too long': 'demo-${'a' * 26}',
      };
      for (final MapEntry(key: name, value: project) in invalid.entries) {
        test('rejects $name', () {
          expect(
            () => _resolve(
              process: {_host: '127.0.0.1:8085', _project: project},
            ),
            _endpointError('must be a demo- project'),
          );
        });
      }

      test('an empty project is an error', () {
        expect(
          () => _resolve(
            process: {_host: '127.0.0.1:8085', _project: ''},
          ),
          _endpointError('$_project is set but empty'),
        );
      });
    });
  });

  group('FirebaseAdmin in emulator mode', () {
    late Directory dir;
    late String keyFile;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('firestore_endpoint_test');
      keyFile = '${dir.path}${Platform.pathSeparator}service-account.json';
      // A dummy account: signing with this key fails before any request.
      File(keyFile).writeAsStringSync(
        jsonEncode({
          'type': 'service_account',
          'project_id': 'demo-unit-test',
          'client_email': 'unit-test@demo-unit-test.iam.gserviceaccount.com',
          'private_key': 'not-a-real-key',
        }),
      );
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('refuses to load a service account, before reading the file', () {
      expect(
        () => FirebaseAdmin.fromEnvironment(
          endpoint: () => _emulator,
          serviceAccountFile: '${dir.path}/missing.json',
        ),
        _adminError('emulator mode is on'),
      );
    });

    test('invalid Firestore settings also fail closed', () {
      expect(
        () => FirebaseAdmin.fromEnvironment(
          endpoint: () => _resolve(process: {_host: '10.0.0.5:8085'}),
          serviceAccountFile: keyFile,
        ),
        _adminError('Invalid Firestore settings'),
      );
    });

    test('accessToken() refuses once emulator mode is switched on', () async {
      var endpoint = FirestoreEndpoint.production;
      final admin = FirebaseAdmin.fromEnvironment(
        endpoint: () => endpoint,
        serviceAccountFile: keyFile,
      );
      expect(admin.projectId, 'demo-unit-test');

      endpoint = _emulator;
      await expectLater(
        admin.accessToken(),
        _adminError('emulator mode is on'),
      );
    });

    test('production mode behaves as before', () async {
      final admin = FirebaseAdmin.fromEnvironment(
        endpoint: () => FirestoreEndpoint.production,
        serviceAccountFile: keyFile,
      );
      // The guard lets it through; the dummy key then fails to sign, which
      // happens before any request to Google.
      await expectLater(
        admin.accessToken(),
        _adminError('private key is invalid'),
      );
    });

    test('a cached real token is never returned in emulator mode', () async {
      var endpoint = FirestoreEndpoint.production;
      var fetches = 0;
      final admin = FirebaseAdmin.fromEnvironment(
        endpoint: () => endpoint,
        serviceAccountFile: keyFile,
        fetchToken: () async {
          fetches++;
          return (token: 'real-token', expiresIn: const Duration(hours: 1));
        },
      );

      // Production: fetched once, then served from the cache.
      expect(await admin.accessToken(), 'real-token');
      expect(await admin.accessToken(), 'real-token');
      expect(fetches, 1);

      // Emulator mode: refused even though a real token is cached.
      endpoint = _emulator;
      await expectLater(
        admin.accessToken(),
        _adminError('emulator mode is on'),
      );
      expect(fetches, 1);
    });
  }, skip: _realSettingsSkip);

  group('real FirebaseAdmin.instance -> NotificationStore.fromFirebaseAdmin '
      'chain', () {
    test('valid emulator settings: credentials are refused and the real '
        'store only talks to the emulator', () async {
      final steps = await _runProbe({
        _host: '127.0.0.1:8085',
        _project: 'demo-theotutoring',
      });
      expect(steps.keys, _probeSteps);
      expect(
        steps['instance'],
        startsWith('REFUSED Firestore emulator mode is on'),
      );
      expect(
        steps['injectedProduction'],
        startsWith('REFUSED Firestore emulator mode is on'),
      );
      // Built without FirebaseAdmin (which refuses): emulator URL and token.
      final emulatorUrl = Uri.http(
        '127.0.0.1:8085',
        '/v1/projects/demo-theotutoring/databases/(default)/documents/'
            'notifications/probe-user:runQuery',
      );
      expect(steps['notificationStore'], 'SENT $emulatorUrl emulator-token');
      // A store aimed at production is stopped before any request.
      expect(
        steps['directProductionStore'],
        startsWith(
          'REFUSED requests=0 Firestore emulator mode is on, so requests '
          'outside the emulator are refused',
        ),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('invalid emulator settings refuse every step, with no request '
        'sent', () async {
      final steps = await _runProbe({
        _host: '10.0.0.5:8085',
        _project: 'demo-theotutoring',
      });
      expect(steps.keys, _probeSteps);
      for (final step in ['instance', 'injectedProduction']) {
        expect(
          steps[step],
          startsWith('REFUSED Invalid Firestore settings'),
          reason: step,
        );
      }
      for (final step in ['notificationStore', 'directProductionStore']) {
        expect(
          steps[step],
          startsWith('REFUSED requests=0 Invalid Firestore settings'),
          reason: step,
        );
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

/// The in-process FirebaseAdmin tests need this machine's real settings to
/// be production, because the real guard always runs first.
final Object _realSettingsSkip = () {
  try {
    return FirestoreEndpoint.resolve().isEmulator
        ? 'Real settings are in Firestore emulator mode'
        : false;
  } on FirestoreEndpointException {
    return 'Real Firestore settings are invalid';
  }
}();

const _probeSteps = [
  'instance',
  'injectedProduction',
  'notificationStore',
  'directProductionStore',
];

/// Runs test/support/emulator_guard_probe.dart in a child process with
/// [environment] added, and returns each step's outcome. The probe never
/// requests a token, so a broken guard shows up as CREATED, not as a call
/// to Google.
Future<Map<String, String>> _runProbe(Map<String, String> environment) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    '--packages=.dart_tool/package_config.json',
    'test/support/emulator_guard_probe.dart',
  ], environment: environment);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return {
    for (final line in LineSplitter.split(result.stdout as String))
      if (line.contains(': '))
        line.substring(0, line.indexOf(': ')): line.substring(
          line.indexOf(': ') + 2,
        ),
  };
}
