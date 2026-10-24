import 'dart:io';

import 'package:dotenv/dotenv.dart';

// Decides whether Firestore requests go to production or to the local
// Firebase Emulator Suite. Emulator mode is switched on by
// FIRESTORE_EMULATOR_HOST, read from both the process environment and the
// .env file (env.dart lets .env win, which would hide a conflict, so the
// two are checked separately here). Anything unclear fails closed: a
// FirestoreEndpointException, never a silent fall back to production.

/// Variable that switches on emulator mode (set by
/// `firebase emulators:exec`).
const firestoreEmulatorHostVariable = 'FIRESTORE_EMULATOR_HOST';

/// Variable naming the emulator's project (set by `firebase emulators:exec`).
const firestoreEmulatorProjectVariable = 'GCLOUD_PROJECT';

/// Looks up one setting; null when it is not set at all.
typedef SettingLookup = String? Function(String key);

/// Thrown when the Firestore settings are contradictory or unsafe, for
/// example an emulator host that is not on this machine.
class FirestoreEndpointException implements Exception {
  /// Creates the exception.
  const FirestoreEndpointException(this.message);

  /// What is wrong (for the server log).
  final String message;

  @override
  String toString() => 'FirestoreEndpointException: $message';
}

/// Where Firestore requests are sent.
class FirestoreEndpoint {
  const FirestoreEndpoint._({
    required this.isEmulator,
    required this.baseUri,
    this.projectId,
    this.accessToken,
  });

  /// Reads the settings and returns the endpoint to use.
  ///
  /// Emulator mode needs FIRESTORE_EMULATOR_HOST to be a loopback address
  /// on port [emulatorPort], and GCLOUD_PROJECT to be a `demo-` project
  /// (Firebase never connects those to real resources). Throws a
  /// [FirestoreEndpointException] if a value is invalid, or if the process
  /// environment and .env disagree. With no emulator host anywhere, returns
  /// [production].
  ///
  /// Tests pass their own [processEnvironment] and [dotEnvFile].
  factory FirestoreEndpoint.resolve({
    SettingLookup? processEnvironment,
    SettingLookup? dotEnvFile,
  }) {
    final fromProcess = processEnvironment ?? _platformEnvironment;
    final fromFile = dotEnvFile ?? _dotEnvFileOnly;

    final host = _agreed(firestoreEmulatorHostVariable, fromProcess, fromFile);
    if (host == null) return production;

    final project = _agreed(
      firestoreEmulatorProjectVariable,
      fromProcess,
      fromFile,
    );
    if (project == null) {
      throw const FirestoreEndpointException(
        '$firestoreEmulatorHostVariable is set but '
        '$firestoreEmulatorProjectVariable is not; set it to a demo- project.',
      );
    }
    if (!_demoProject.hasMatch(project)) {
      throw const FirestoreEndpointException(
        '$firestoreEmulatorProjectVariable must be a demo- project '
        '(for example demo-theotutoring) in emulator mode.',
      );
    }

    _checkLoopback(host);
    return FirestoreEndpoint._(
      isEmulator: true,
      baseUri: Uri.http('127.0.0.1:$emulatorPort'),
      projectId: project,
      accessToken: emulatorAccessToken,
    );
  }

  /// Google's Firestore. The project and access token come from the
  /// service account (`FirebaseAdmin`).
  static final production = FirestoreEndpoint._(
    isEmulator: false,
    baseUri: Uri.https('firestore.googleapis.com'),
  );

  /// Port the Firestore emulator listens on (8080 is the backend's own port).
  static const emulatorPort = 8085;

  /// Token the Firestore emulator accepts as an administrator, bypassing
  /// security rules. Production rejects it.
  static const emulatorAccessToken = 'owner';

  static final _demoProject = RegExp(r'^demo-[a-z0-9-]{1,25}$');
  static const _loopbackHosts = {'127.0.0.1', 'localhost', '::1'};

  /// Whether requests go to the local emulator.
  final bool isEmulator;

  /// Scheme, host and port of the Firestore REST API.
  final Uri baseUri;

  /// The emulator's demo project; null in production, where the service
  /// account names the project.
  final String? projectId;

  /// Fixed emulator token; null in production, where `FirebaseAdmin`
  /// supplies one.
  final String? accessToken;

  /// The value of [key] when the process environment and .env agree.
  /// Null when neither sets it; throws when they disagree or it is blank.
  static String? _agreed(
    String key,
    SettingLookup fromProcess,
    SettingLookup fromFile,
  ) {
    final process = fromProcess(key);
    final file = fromFile(key);
    for (final value in [process, file]) {
      if (value != null && value.trim().isEmpty) {
        throw FirestoreEndpointException('$key is set but empty.');
      }
    }
    if (process != null && file != null && process.trim() != file.trim()) {
      throw FirestoreEndpointException(
        '$key differs between the process environment and .env.',
      );
    }
    return (process ?? file)?.trim();
  }

  /// Accepts "127.0.0.1:8085", "localhost:8085" or "[::1]:8085" only.
  static void _checkLoopback(String host) {
    final uri = Uri.tryParse('http://$host');
    final valid =
        uri != null &&
        uri.hasPort &&
        uri.userInfo.isEmpty &&
        (uri.path.isEmpty || uri.path == '/') &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        _loopbackHosts.contains(uri.host);
    if (!valid) {
      throw const FirestoreEndpointException(
        '$firestoreEmulatorHostVariable must be a loopback host and port, '
        'for example 127.0.0.1:$emulatorPort.',
      );
    }
    if (uri.port != emulatorPort) {
      throw const FirestoreEndpointException(
        '$firestoreEmulatorHostVariable must use port $emulatorPort.',
      );
    }
  }
}

String? _platformEnvironment(String key) => Platform.environment[key];

// The .env file on its own (env.dart mixes in the process environment).
final _dotEnvFile = DotEnv(quiet: true)..load();

String? _dotEnvFileOnly(String key) => _dotEnvFile[key];
