import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:theo_tutoring_backend/firestore_endpoint.dart';

// An explicit, local-only development mode: every MySQL connection goes to
// the `theotutoring_test` database on this machine instead of the database
// named by DB_* in .env, so chat can run against the Firestore emulator
// without touching the shared database.
//
// It is switched on only by THEO_LOCAL_TEST_DB=1 in the process
// environment (never .env), and needs APP_ENV=development or test and
// Firestore emulator mode. The connection settings are the THEO_TEST_DB_*
// variables the integration tests already use, also read from the process
// environment only, so the password never has to be written to a file.
// Anything invalid or contradictory fails closed with a
// LocalTestDatabaseException; nothing falls back to DB_*.

/// Process variable that switches the local test database on (value `1`).
const localTestDatabaseOptInVariable = 'THEO_LOCAL_TEST_DB';

/// The only database this mode connects to.
const localTestDatabaseName = 'theotutoring_test';

const _hostVariable = 'THEO_TEST_DB_HOST';
const _portVariable = 'THEO_TEST_DB_PORT';
const _userVariable = 'THEO_TEST_DB_USER';
const _passwordVariable = 'THEO_TEST_DB_PASSWORD';
const _caVariable = 'THEO_TEST_DB_SSL_CA';
const _connectionVariables = [
  _hostVariable,
  _portVariable,
  _userVariable,
  _passwordVariable,
  _caVariable,
];
const _loopbackHosts = {'127.0.0.1', 'localhost', '::1'};

/// Thrown when the local test database settings are invalid or unsafe.
class LocalTestDatabaseException implements Exception {
  /// Creates the exception.
  const LocalTestDatabaseException(this.message);

  /// What is wrong (for the server log; never includes the password).
  final String message;

  @override
  String toString() => 'LocalTestDatabaseException: $message';
}

/// Connection settings for the local `theotutoring_test` database.
class LocalTestDatabase {
  const LocalTestDatabase._({
    required this.host,
    required this.port,
    required this.userName,
    required String password,
    this.caFile,
  }) : _password = password;

  /// The local test database, or null when the mode is not switched on
  /// (the normal DB_* settings apply, unchanged).
  ///
  /// Throws a [LocalTestDatabaseException] when the mode is requested from
  /// .env, or switched on with an invalid or unsafe setting. Tests pass
  /// their own [processEnvironment], [dotEnvFile] and [firestoreEndpoint].
  static LocalTestDatabase? resolve({
    SettingLookup? processEnvironment,
    SettingLookup? dotEnvFile,
    FirestoreEndpoint Function()? firestoreEndpoint,
  }) {
    final fromProcess = processEnvironment ?? _platformEnvironment;
    final fromFile = dotEnvFile ?? _dotEnvFileOnly;

    if (fromFile(localTestDatabaseOptInVariable) != null) {
      throw const LocalTestDatabaseException(
        '$localTestDatabaseOptInVariable must be set in the process '
        'environment, not .env.',
      );
    }
    final optIn = fromProcess(localTestDatabaseOptInVariable);
    if (optIn == null) return null;
    if (optIn.trim() != '1') {
      throw const LocalTestDatabaseException(
        '$localTestDatabaseOptInVariable must be 1 to use the local test '
        'database.',
      );
    }

    for (final key in _connectionVariables) {
      if (fromFile(key) != null) {
        throw LocalTestDatabaseException(
          '$key must be set in the process environment, not .env.',
        );
      }
    }

    final appEnv = fromProcess('APP_ENV')?.trim();
    if (appEnv != 'development' && appEnv != 'test') {
      throw const LocalTestDatabaseException(
        'The local test database needs APP_ENV=development or test.',
      );
    }

    final FirestoreEndpoint endpoint;
    try {
      endpoint = (firestoreEndpoint ?? FirestoreEndpoint.resolve)();
    } on FirestoreEndpointException catch (e) {
      throw LocalTestDatabaseException(
        'Invalid Firestore settings: ${e.message}',
      );
    }
    if (!endpoint.isEmulator) {
      throw const LocalTestDatabaseException(
        'The local test database needs Firestore emulator mode, so local '
        'user IDs are never written to production Firestore.',
      );
    }

    String? setting(String key) {
      final value = fromProcess(key);
      if (value != null && value.trim().isEmpty) {
        throw LocalTestDatabaseException('$key is set but empty.');
      }
      return value?.trim();
    }

    final host = setting(_hostVariable) ?? '127.0.0.1';
    if (!_loopbackHosts.contains(host)) {
      throw const LocalTestDatabaseException(
        '$_hostVariable must be 127.0.0.1, localhost or ::1.',
      );
    }
    final rawPort = setting(_portVariable) ?? '3306';
    final port = int.tryParse(rawPort);
    if (port == null || port < 1 || port > 65535) {
      throw const LocalTestDatabaseException(
        '$_portVariable must be a port number.',
      );
    }
    // The password is used as given (not trimmed); it is only checked for
    // presence and never reported.
    final password = fromProcess(_passwordVariable);
    if (password == null || password.isEmpty) {
      throw const LocalTestDatabaseException(
        '$_passwordVariable must be set in the process environment.',
      );
    }
    final caFile = setting(_caVariable);
    if (caFile != null && !File(caFile).existsSync()) {
      throw const LocalTestDatabaseException(
        '$_caVariable does not name a readable file.',
      );
    }

    return LocalTestDatabase._(
      host: host,
      port: port,
      userName: setting(_userVariable) ?? 'theo_app',
      password: password,
      caFile: caFile,
    );
  }

  /// Loopback host.
  final String host;

  /// MySQL port.
  final int port;

  /// MySQL account.
  final String userName;

  /// CA that signed the local server's certificate, if given.
  final String? caFile;

  final String _password;

  /// Always [localTestDatabaseName].
  String get databaseName => localTestDatabaseName;

  /// For logs: account, host, port and database, never the password.
  String get description => '$userName@$host:$port/$databaseName';

  /// A new, unopened connection to the local test database.
  ///
  /// TLS is always on. With [caFile] the server certificate is verified
  /// against that CA only; without it the certificate is not verified
  /// (MySQL's self-generated certificate cannot be), which is accepted
  /// only because the host is restricted to this machine.
  Future<MySQLConnection> newConnection() => MySQLConnection.createConnection(
    host: host,
    port: port,
    userName: userName,
    password: _password,
    databaseName: localTestDatabaseName,
    securityContext: caFile == null
        ? null
        : (SecurityContext(withTrustedRoots: false)
            ..setTrustedCertificates(caFile!)),
    verifyServerCertificate: caFile != null,
  );

  @override
  String toString() => 'LocalTestDatabase($description)';
}

String? _platformEnvironment(String key) => Platform.environment[key];

// The .env file on its own (env.dart mixes in the process environment).
final _dotEnvFile = DotEnv(quiet: true)..load();

String? _dotEnvFileOnly(String key) => _dotEnvFile[key];
