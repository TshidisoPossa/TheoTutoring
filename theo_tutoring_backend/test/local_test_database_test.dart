import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:theo_tutoring_backend/firestore_endpoint.dart';
import 'package:theo_tutoring_backend/local_test_database.dart';

// No real settings and no database: the unit tests pass their own process
// environment, .env values and Firestore endpoint. The child-process tests
// run the real factories against loopback listeners that only count
// connection attempts (they never speak MySQL).

SettingLookup _lookup(Map<String, String> values) =>
    (key) => values[key];

FirestoreEndpoint _emulator() => FirestoreEndpoint.resolve(
  processEnvironment: _lookup({
    firestoreEmulatorHostVariable: '127.0.0.1:8085',
    firestoreEmulatorProjectVariable: 'demo-theotutoring',
  }),
  dotEnvFile: _lookup(const {}),
);

FirestoreEndpoint _production() => FirestoreEndpoint.production;

const _secret = 's3cret-Pa55';

const _valid = {
  localTestDatabaseOptInVariable: '1',
  'APP_ENV': 'development',
  'THEO_TEST_DB_PASSWORD': _secret,
};

LocalTestDatabase? _resolve(
  Map<String, String> process, {
  Map<String, String> file = const {},
  FirestoreEndpoint Function() endpoint = _emulator,
}) => LocalTestDatabase.resolve(
  processEnvironment: _lookup(process),
  dotEnvFile: _lookup(file),
  firestoreEndpoint: endpoint,
);

Matcher _refused(String fragment) => throwsA(
  isA<LocalTestDatabaseException>()
      .having((e) => e.message, 'message', contains(fragment))
      .having((e) => e.message, 'message', isNot(contains(_secret))),
);

void main() {
  group('LocalTestDatabase.resolve', () {
    test('is off unless explicitly opted in, even in emulator mode', () {
      expect(
        _resolve({
          'APP_ENV': 'development',
          'THEO_TEST_DB_PASSWORD': _secret,
          'THEO_TEST_DB_HOST': '127.0.0.1',
        }),
        isNull,
      );
    });

    test('valid opt-in uses only theotutoring_test on loopback', () {
      final local = _resolve(_valid)!;
      expect(local.databaseName, 'theotutoring_test');
      expect(local.host, '127.0.0.1');
      expect(local.port, 3306);
      expect(local.userName, 'theo_app');
      expect(local.caFile, isNull);
      expect(local.description, 'theo_app@127.0.0.1:3306/theotutoring_test');
      expect('$local', isNot(contains(_secret)));
    });

    test('accepts explicit loopback settings and APP_ENV=test', () {
      final local = _resolve({
        ..._valid,
        'APP_ENV': 'test',
        'THEO_TEST_DB_HOST': 'localhost',
        'THEO_TEST_DB_PORT': '3307',
        'THEO_TEST_DB_USER': 'someone',
      })!;
      expect(local.host, 'localhost');
      expect(local.port, 3307);
      expect(local.userName, 'someone');
    });

    test('cannot be switched on from .env', () {
      expect(
        () => _resolve(
          const {},
          file: const {localTestDatabaseOptInVariable: '1'},
        ),
        _refused('not .env'),
      );
    });

    test('connection settings in .env conflict with the opt-in', () {
      for (final key in [
        'THEO_TEST_DB_PASSWORD',
        'THEO_TEST_DB_HOST',
        'THEO_TEST_DB_PORT',
        'THEO_TEST_DB_USER',
        'THEO_TEST_DB_SSL_CA',
      ]) {
        expect(
          () => _resolve(_valid, file: {key: 'x'}),
          _refused('$key must be set in the process environment'),
          reason: key,
        );
      }
    });

    test('the opt-in value must be exactly 1', () {
      for (final value in ['0', 'true', 'yes', '']) {
        expect(
          () => _resolve({..._valid, localTestDatabaseOptInVariable: value}),
          _refused('must be 1'),
          reason: value,
        );
      }
    });

    test('needs APP_ENV=development or test', () {
      expect(
        () => _resolve({..._valid}..remove('APP_ENV')),
        _refused('APP_ENV'),
      );
      expect(
        () => _resolve({..._valid, 'APP_ENV': 'production'}),
        _refused('APP_ENV'),
      );
    });

    test('needs Firestore emulator mode', () {
      expect(
        () => _resolve(_valid, endpoint: _production),
        _refused('needs Firestore emulator mode'),
      );
      expect(
        () => _resolve(
          _valid,
          endpoint: () =>
              throw const FirestoreEndpointException('bad emulator host'),
        ),
        _refused('Invalid Firestore settings: bad emulator host'),
      );
    });

    test('refuses any host that is not this machine', () {
      for (final host in [
        'mysql-87bce02-lelomaluleka11-602b.g.aivencloud.com',
        '10.0.0.5',
        '0.0.0.0',
        '127.0.0.1:3306',
      ]) {
        expect(
          () => _resolve({..._valid, 'THEO_TEST_DB_HOST': host}),
          _refused('THEO_TEST_DB_HOST must be'),
          reason: host,
        );
      }
    });

    test('refuses bad ports, blank values and a missing password', () {
      for (final port in ['0', '65536', 'abc', '28238x']) {
        expect(
          () => _resolve({..._valid, 'THEO_TEST_DB_PORT': port}),
          _refused('THEO_TEST_DB_PORT'),
          reason: port,
        );
      }
      expect(
        () => _resolve({..._valid, 'THEO_TEST_DB_USER': '  '}),
        _refused('THEO_TEST_DB_USER is set but empty'),
      );
      expect(
        () => _resolve({..._valid}..remove('THEO_TEST_DB_PASSWORD')),
        _refused('THEO_TEST_DB_PASSWORD must be set'),
      );
      expect(
        () => _resolve({..._valid, 'THEO_TEST_DB_PASSWORD': ''}),
        _refused('THEO_TEST_DB_PASSWORD must be set'),
      );
    });

    test('a CA file must exist', () {
      expect(
        () => _resolve({
          ..._valid,
          'THEO_TEST_DB_SSL_CA': 'C:/definitely/missing/ca.pem',
        }),
        _refused('THEO_TEST_DB_SSL_CA'),
      );
    });
  });

  group('real factories (child process)', () {
    late ServerSocket decoy;
    late ServerSocket local;
    var decoyConnections = 0;
    var localConnections = 0;

    setUp(() async {
      decoyConnections = 0;
      localConnections = 0;
      decoy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      local = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      decoy.listen((socket) {
        decoyConnections++;
        socket.destroy();
      });
      local.listen((socket) {
        localConnections++;
        socket.destroy();
      });
    });

    tearDown(() async {
      await decoy.close();
      await local.close();
    });

    /// DB_* points at [decoy] (standing in for the shared database), so any
    /// fallback to DB_* would be counted there.
    Map<String, String> environment(Map<String, String> extra) => {
      'DB_HOST': '127.0.0.1',
      'DB_PORT': '${decoy.port}',
      'DB_NAME': 'theotutoring',
      'DB_USER': 'shared_user',
      'DB_PASSWORD': 'shared-password',
      firestoreEmulatorHostVariable: '127.0.0.1:8085',
      firestoreEmulatorProjectVariable: 'demo-theotutoring',
      ...extra,
    };

    test('opted in: chat and every other route dial only the local test '
        'database, never DB_*', () async {
      final steps = await _runProbe(
        environment({
          localTestDatabaseOptInVariable: '1',
          'APP_ENV': 'development',
          'THEO_TEST_DB_HOST': '127.0.0.1',
          'THEO_TEST_DB_PORT': '${local.port}',
          'THEO_TEST_DB_PASSWORD': _secret,
        }),
      );
      // The listener hangs up, so each attempt fails after dialling.
      for (final step in ['permissions', 'audit', 'getConnection']) {
        expect(steps[step], startsWith('ERROR'), reason: step);
      }
      expect(localConnections, greaterThanOrEqualTo(3));
      expect(decoyConnections, 0);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('emulator mode without the opt-in still refuses chat before '
        'connecting', () async {
      final steps = await _runProbe(environment(const {}));
      for (final step in ['permissions', 'audit']) {
        expect(
          steps[step],
          startsWith('REFUSED Firestore emulator mode is on'),
          reason: step,
        );
      }
      expect(localConnections, 0);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('an invalid opt-in refuses every connection before dialling '
        'anything', () async {
      final steps = await _runProbe(
        environment({
          localTestDatabaseOptInVariable: '1',
          'APP_ENV': 'development',
          'THEO_TEST_DB_HOST':
              'mysql-87bce02-lelomaluleka11-602b.g.'
              'aivencloud.com',
          'THEO_TEST_DB_PASSWORD': _secret,
        }),
      );
      for (final step in ['permissions', 'audit']) {
        expect(
          steps[step],
          startsWith('REFUSED Invalid local test database settings'),
          reason: step,
        );
      }
      expect(steps['getConnection'], startsWith('REFUSED THEO_TEST_DB_HOST'));
      for (final line in steps.values) {
        expect(line, isNot(contains(_secret)));
      }
      expect(localConnections, 0);
      expect(decoyConnections, 0);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

const _probe = r'''
import 'dart:async';
import 'dart:io';

import 'package:theo_tutoring_backend/chat_handlers.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/local_test_database.dart';

Future<void> main() async {
  final deps = ChatDependencies.production();
  final steps = <(String, Future<Object> Function())>[
    ('permissions', deps.permissions),
    ('audit', deps.audit),
    ('getConnection', getConnection),
  ];
  for (final (name, open) in steps) {
    try {
      await open().timeout(const Duration(seconds: 20));
      stdout.writeln('$name: OPENED');
    } on ChatSetupException catch (e) {
      stdout.writeln('$name: REFUSED ${e.message}');
    } on LocalTestDatabaseException catch (e) {
      stdout.writeln('$name: REFUSED ${e.message}');
    } on Object catch (e) {
      stdout.writeln('$name: ERROR ${e.runtimeType}');
    }
  }
  exit(0);
}
''';

/// Runs [_probe] in a fresh process with only [environment] (plus what the
/// OS needs) and no .env file, and returns each step's result.
Future<Map<String, String>> _runProbe(Map<String, String> environment) async {
  final dir = Directory.systemTemp.createTempSync('local_test_db_probe');
  try {
    const inheritedOsKeys = [
      'PATH',
      'SystemRoot',
      'WINDIR',
      'TEMP',
      'TMP',
      'HOME',
    ];
    File(
      '${dir.path}${Platform.pathSeparator}probe.dart',
    ).writeAsStringSync(_probe);
    final packages = File(
      '${Directory.current.path}/.dart_tool/package_config.json',
    ).absolute.path;
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['--packages=$packages', 'probe.dart'],
      workingDirectory: dir.path,
      environment: {
        for (final key in inheritedOsKeys)
          if (Platform.environment.containsKey(key))
            key: Platform.environment[key]!,
        ...environment,
      },
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return {
      for (final line in LineSplitter.split(result.stdout as String))
        if (line.contains(': '))
          line.substring(0, line.indexOf(': ')): line.substring(
            line.indexOf(': ') + 2,
          ),
    };
  } finally {
    dir.deleteSync(recursive: true);
  }
}
