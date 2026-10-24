import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:theo_tutoring_backend/firebase_admin.dart';
import 'package:theo_tutoring_backend/firestore_endpoint.dart';

// A small Firestore REST client (Dart has no official Admin SDK): value
// conversion, document reads, queries, deletes, and read-write
// transactions with bounded retries. Requests go where FirestoreEndpoint
// says; in emulator mode nothing is sent anywhere but the emulator.
//
// Paths are relative to the database's documents root, e.g.
// "conversations/s1_t2" or "conversations/s1_t2/messages/9-abc". Every
// segment must match [A-Za-z0-9_-], so paths can never be used to reach
// another part of the database and never need encoding.

// ─── Errors ─────────────────────────────────────────────────────────────────

/// A Firestore request failed. The message never includes access tokens or
/// response bodies, so it is safe to log.
class FirestoreException implements Exception {
  /// Creates the exception.
  const FirestoreException(this.message, {this.statusCode, this.status});

  /// What went wrong.
  final String message;

  /// HTTP status code, if Firestore answered.
  final int? statusCode;

  /// Firestore's error status, e.g. "ABORTED" or "FAILED_PRECONDITION".
  final String? status;

  @override
  String toString() => 'FirestoreException: $message';
}

/// The document (or the database) does not exist.
class FirestoreNotFound extends FirestoreException {
  /// Creates the exception.
  const FirestoreNotFound(super.message, {super.statusCode, super.status});
}

/// A transaction was aborted, or a write's precondition failed (the
/// document changed, already exists, or no longer exists). Retrying after
/// reading again may succeed.
class FirestoreConflict extends FirestoreException {
  /// Creates the exception.
  const FirestoreConflict(super.message, {super.statusCode, super.status});

  /// Firestore aborted the transaction (contention), as opposed to a failed
  /// precondition.
  bool get isAborted => status == 'ABORTED';
}

/// Firestore refused the credentials or the request (401/403).
class FirestorePermissionDenied extends FirestoreException {
  /// Creates the exception.
  const FirestorePermissionDenied(
    super.message, {
    super.statusCode,
    super.status,
  });
}

/// Firestore rejected the request as invalid (a bug in the caller).
class FirestoreBadRequest extends FirestoreException {
  /// Creates the exception.
  const FirestoreBadRequest(super.message, {super.statusCode, super.status});
}

/// Firestore could not be reached, timed out, or is overloaded.
class FirestoreUnavailable extends FirestoreException {
  /// Creates the exception.
  const FirestoreUnavailable(super.message, {super.statusCode, super.status});
}

/// A transaction kept conflicting and was given up.
class FirestoreRetryExhausted extends FirestoreUnavailable {
  /// Creates the exception.
  const FirestoreRetryExhausted(this.attempts)
    : super('Transaction did not commit after $attempts attempts.');

  /// How many times the transaction was tried.
  final int attempts;
}

/// Firestore answered with something that is not the expected shape.
class FirestoreFormatException extends FirestoreException {
  /// Creates the exception.
  const FirestoreFormatException(super.message);
}

// ─── Value conversion ───────────────────────────────────────────────────────

/// Converts a Dart value to a Firestore REST `Value`. Supports null, bool,
/// int, double, String, DateTime (stored as UTC), `Map<String, Object?>`
/// and `List` (arrays cannot directly contain arrays). Anything else throws
/// an [ArgumentError].
Map<String, Object?> encodeFirestoreValue(Object? value) => switch (value) {
  null => {'nullValue': null},
  final bool b => {'booleanValue': b},
  final int i => {'integerValue': '$i'},
  final double d => {
    'doubleValue': d.isNaN
        ? 'NaN'
        : d.isInfinite
        ? (d > 0 ? 'Infinity' : '-Infinity')
        : d,
  },
  final String s => {'stringValue': s},
  final DateTime t => {'timestampValue': t.toUtc().toIso8601String()},
  final Map<String, Object?> m => {
    'mapValue': {'fields': encodeFirestoreFields(m)},
  },
  final List<Object?> l => {
    'arrayValue': {
      'values': [
        for (final v in l)
          if (v is List)
            throw ArgumentError('Firestore arrays cannot contain arrays.')
          else
            encodeFirestoreValue(v),
      ],
    },
  },
  _ => throw ArgumentError(
    'Unsupported Firestore value type: ${value.runtimeType}',
  ),
};

/// Converts a map of Dart values to Firestore REST `fields`.
Map<String, Object?> encodeFirestoreFields(Map<String, Object?> fields) => {
  for (final MapEntry(:key, :value) in fields.entries)
    key: encodeFirestoreValue(value),
};

/// Converts a Firestore REST `Value` back to Dart (see
/// [encodeFirestoreValue]); timestamps come back as UTC DateTimes.
/// Throws a [FirestoreFormatException] for anything malformed or
/// unsupported (bytes, geo points, references).
Object? decodeFirestoreValue(Object? json) {
  if (json is! Map<String, dynamic> || json.length != 1) {
    throw const FirestoreFormatException('Firestore value is malformed.');
  }
  final MapEntry(:key, :value) = json.entries.single;
  switch (key) {
    case 'nullValue':
      return null;
    case 'booleanValue':
      if (value is bool) return value;
    case 'integerValue':
      final parsed = value is String
          ? int.tryParse(value)
          : value is int
          ? value
          : null;
      if (parsed != null) return parsed;
    case 'doubleValue':
      if (value is num) return value.toDouble();
      if (value == 'NaN') return double.nan;
      if (value == 'Infinity') return double.infinity;
      if (value == '-Infinity') return double.negativeInfinity;
    case 'stringValue':
      if (value is String) return value;
    case 'timestampValue':
      final parsed = value is String ? DateTime.tryParse(value) : null;
      if (parsed != null && parsed.isUtc) return parsed;
    case 'mapValue':
      if (value is Map<String, dynamic>) {
        return decodeFirestoreFields(value['fields'] ?? const {});
      }
    case 'arrayValue':
      if (value is Map<String, dynamic>) {
        final values = value['values'] ?? const <Object?>[];
        if (values is List) {
          return [for (final v in values) decodeFirestoreValue(v)];
        }
      }
  }
  throw FirestoreFormatException('Firestore $key value is malformed.');
}

/// Converts Firestore REST `fields` back to a map of Dart values.
Map<String, Object?> decodeFirestoreFields(Object? json) {
  if (json is! Map<String, dynamic>) {
    throw const FirestoreFormatException('Firestore fields are malformed.');
  }
  return {
    for (final MapEntry(:key, :value) in json.entries)
      key: decodeFirestoreValue(value),
  };
}

// ─── Documents and writes ───────────────────────────────────────────────────

/// A document read from Firestore.
class FirestoreDocument {
  /// Creates a document.
  const FirestoreDocument({
    required this.path,
    required this.fields,
    required this.updateTime,
  });

  /// Path relative to the documents root, e.g. "conversations/s1_t2".
  final String path;

  /// Field values (see [decodeFirestoreValue]).
  final Map<String, Object?> fields;

  /// Firestore's exact update time (nanoseconds), for
  /// [FirestorePrecondition.updateTime].
  final String updateTime;
}

/// A condition a write or delete only proceeds under.
class FirestorePrecondition {
  /// The document must (or must not) exist.
  const FirestorePrecondition.exists({required bool this.exists})
    : updateTime = null;

  /// The document must still have this exact update time.
  const FirestorePrecondition.updateTime(String this.updateTime)
    : exists = null;

  /// Only create a new document.
  static const mustNotExist = FirestorePrecondition.exists(exists: false);

  /// Only change an existing document.
  static const mustExist = FirestorePrecondition.exists(exists: true);

  /// Required existence, if this is an existence condition.
  final bool? exists;

  /// Required update time, if this is an update-time condition.
  final String? updateTime;

  Map<String, Object?> _toJson() =>
      exists != null ? {'exists': exists} : {'updateTime': updateTime};

  Map<String, String> _toQuery() => exists != null
      ? {'currentDocument.exists': '$exists'}
      : {'currentDocument.updateTime': updateTime!};
}

/// A value Firestore computes when the write is applied.
class FirestoreTransform {
  /// Sets [fieldPath] to the commit time.
  const FirestoreTransform.serverTime(this.fieldPath) : increment = null;

  /// Adds [increment] to [fieldPath] (missing counts as 0).
  const FirestoreTransform.increment(this.fieldPath, int this.increment);

  /// Field the transform applies to, e.g. "sent.student".
  final String fieldPath;

  /// Amount to add, for an increment.
  final int? increment;

  Map<String, Object?> _toJson() => {
    'fieldPath': _checkFieldPath(fieldPath),
    if (increment == null)
      'setToServerValue': 'REQUEST_TIME'
    else
      'increment': encodeFirestoreValue(increment),
  };
}

/// One write in a commit.
class FirestoreWrite {
  /// Writes [fields] to [path]. With an [updateMask] only those fields
  /// change (others are kept); without one the document is replaced.
  const FirestoreWrite.update(
    this.path,
    Map<String, Object?> this.fields, {
    this.updateMask,
    this.transforms = const [],
    this.precondition,
  }) : isDelete = false;

  /// Deletes the document at [path].
  const FirestoreWrite.delete(this.path, {this.precondition})
    : fields = null,
      updateMask = null,
      transforms = const [],
      isDelete = true;

  /// Document path relative to the documents root.
  final String path;

  /// Values to write (null for a delete).
  final Map<String, Object?>? fields;

  /// Field paths to change, if not replacing the whole document.
  final List<String>? updateMask;

  /// Server-side values applied after [fields].
  final List<FirestoreTransform> transforms;

  /// Condition the write needs.
  final FirestorePrecondition? precondition;

  /// Whether this deletes the document.
  final bool isDelete;
}

/// The result of a commit.
class FirestoreCommitResult {
  /// Creates the result.
  const FirestoreCommitResult({
    required this.commitTime,
    required this.updateTimes,
  });

  /// When the commit was applied (also the value of server-time
  /// transforms), exactly as Firestore sent it.
  final String commitTime;

  /// Each write's new update time, in write order (null for deletes).
  final List<String?> updateTimes;

  /// [commitTime] as a UTC DateTime (microsecond precision).
  DateTime get committedAt => DateTime.parse(commitTime);
}

// ─── Client ─────────────────────────────────────────────────────────────────

/// Firestore REST client for one project's default database.
class FirestoreRest {
  /// Creates a client. [baseUri] is the REST API's scheme, host and port
  /// (production Firestore when omitted).
  ///
  /// Tests pass their own [client], [sleep] (instead of real waiting),
  /// [random] (for the retry jitter, values in [0, 1)) and may pass an
  /// [extraEndpointCheck], applied after the real settings: it can only add
  /// refusals, never lift one.
  FirestoreRest({
    required this.projectId,
    required Future<String> Function() accessToken,
    Uri? baseUri,
    http.Client? client,
    this.maxAttempts = defaultMaxAttempts,
    this.requestTimeout = const Duration(seconds: 15),
    Future<void> Function(Duration delay)? sleep,
    double Function()? random,
    FirestoreEndpoint Function()? extraEndpointCheck,
  }) : assert(maxAttempts >= 1, 'maxAttempts must be at least 1'),
       baseUri = baseUri ?? FirestoreEndpoint.production.baseUri,
       _accessToken = accessToken,
       _client = client ?? http.Client(),
       _sleep = sleep ?? Future<void>.delayed,
       _random = random ?? Random().nextDouble,
       _extraEndpointCheck = extraEndpointCheck;

  /// The client the backend uses, chosen by [FirestoreEndpoint.resolve]:
  /// the service account in production; the emulator's demo project and
  /// token in emulator mode (the service account is never loaded).
  ///
  /// Throws a [FirebaseAdminException] if the service account is not set
  /// up or the Firestore settings are invalid. Tests may pass a [client].
  factory FirestoreRest.fromEnvironment({http.Client? client}) {
    final endpoint = _resolveReal();
    if (endpoint.isEmulator) {
      final token = endpoint.accessToken!;
      return FirestoreRest(
        projectId: endpoint.projectId!,
        accessToken: () async => token,
        baseUri: endpoint.baseUri,
        client: client,
      );
    }
    final admin = FirebaseAdmin.instance;
    return FirestoreRest(
      projectId: admin.projectId,
      accessToken: admin.accessToken,
      client: client,
    );
  }

  /// Attempts a transaction gets before [FirestoreRetryExhausted].
  static const defaultMaxAttempts = 5;

  /// Firebase project the database belongs to.
  final String projectId;

  /// Scheme, host and port every request is sent to.
  final Uri baseUri;

  /// Attempts [runTransaction] makes before giving up.
  final int maxAttempts;

  /// Longest wait for one HTTP response.
  final Duration requestTimeout;

  final Future<String> Function() _accessToken;
  final http.Client _client;
  final Future<void> Function(Duration delay) _sleep;
  final double Function() _random;
  final FirestoreEndpoint Function()? _extraEndpointCheck;

  static final _segment = RegExp(r'^[A-Za-z0-9_-]{1,512}$');

  /// Base wait before retry number [retry] (1-based): 50 ms, doubling, at
  /// most one second.
  static Duration backoffFor(int retry) =>
      Duration(milliseconds: min(50 * (1 << (retry - 1).clamp(0, 10)), 1000));

  /// [backoffFor] plus up to the same again at random ([jitter] in [0, 1)),
  /// still at most one second, so contending transactions stop retrying in
  /// step.
  static Duration jitteredBackoffFor(int retry, double jitter) {
    final base = backoffFor(retry).inMilliseconds;
    return Duration(
      milliseconds: min((base * (1 + jitter.clamp(0, 1))).floor(), 1000),
    );
  }

  String get _root => 'projects/$projectId/databases/(default)/documents';

  /// Full resource name of the document at [path]. Throws an
  /// [ArgumentError] for anything that is not a safe document path.
  String documentName(String path) {
    final segments = path.split('/');
    if (segments.length.isOdd || !segments.every(_segment.hasMatch)) {
      throw ArgumentError.value(path, 'path', 'Not a valid document path');
    }
    return '$_root/$path';
  }

  /// Reads one document; null if it does not exist.
  Future<FirestoreDocument?> get(String path, {String? transaction}) async {
    final name = documentName(path);
    try {
      final json = await _send(
        'GET',
        name,
        query: transaction == null ? null : {'transaction': transaction},
      );
      return _document(json, expectedName: name);
    } on FirestoreNotFound {
      return null;
    }
  }

  /// Reads several documents at once. Every path is a key in the result;
  /// missing documents map to null.
  Future<Map<String, FirestoreDocument?>> batchGet(
    List<String> paths, {
    String? transaction,
  }) async {
    if (paths.isEmpty) return {};
    final pathByName = {for (final p in paths) documentName(p): p};
    final rows = await _send(
      'POST',
      '$_root:batchGet',
      body: {
        'documents': pathByName.keys.toList(),
        'transaction': ?transaction,
      },
    );
    if (rows is! List) {
      throw const FirestoreFormatException('batchGet response is not a list.');
    }
    final result = <String, FirestoreDocument?>{};
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        throw const FirestoreFormatException('batchGet row is malformed.');
      }
      final found = row['found'];
      final missing = row['missing'];
      if (found != null) {
        final name = found is Map ? found['name'] : null;
        final path = pathByName[name];
        if (path == null) {
          throw const FirestoreFormatException(
            'batchGet returned a document that was not asked for.',
          );
        }
        result[path] = _document(found, expectedName: name as String);
      } else if (missing != null) {
        final path = pathByName[missing];
        if (path == null) {
          throw const FirestoreFormatException(
            'batchGet reported a document that was not asked for.',
          );
        }
        result[path] = null;
      }
      // Rows with only a transaction or read time carry no document.
    }
    if (!pathByName.values.every(result.containsKey)) {
      throw const FirestoreFormatException(
        'batchGet response is missing documents.',
      );
    }
    return result;
  }

  /// Runs a structured query under [parent] (a document path, or the
  /// documents root when empty) and returns the matching documents.
  Future<List<FirestoreDocument>> runQuery(
    Map<String, Object?> structuredQuery, {
    String parent = '',
    String? transaction,
  }) async {
    final parentName = parent.isEmpty ? _root : documentName(parent);
    final rows = await _send(
      'POST',
      '$parentName:runQuery',
      body: {
        'structuredQuery': structuredQuery,
        'transaction': ?transaction,
      },
    );
    if (rows is! List) {
      throw const FirestoreFormatException('runQuery response is not a list.');
    }
    final documents = <FirestoreDocument>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        throw const FirestoreFormatException('runQuery row is malformed.');
      }
      final document = row['document'];
      if (document == null) continue; // e.g. the empty-result row
      documents.add(_document(document, under: '$parentName/'));
    }
    return documents;
  }

  /// Deletes one document, optionally only under [precondition].
  Future<void> delete(
    String path, {
    FirestorePrecondition? precondition,
  }) async {
    await _send('DELETE', documentName(path), query: precondition?._toQuery());
  }

  /// Starts a read-write transaction and returns its id. [retrying] is the
  /// id of an aborted attempt, which gives this one priority.
  Future<String> beginTransaction({String? retrying}) async {
    final json = await _send(
      'POST',
      '$_root:beginTransaction',
      body: {
        'options': {
          'readWrite': {'retryTransaction': ?retrying},
        },
      },
    );
    final id = json is Map<String, dynamic> ? json['transaction'] : null;
    if (id is! String || id.isEmpty) {
      throw const FirestoreFormatException(
        'beginTransaction returned no transaction.',
      );
    }
    return id;
  }

  /// Applies [writes] atomically (inside [transaction], if given).
  Future<FirestoreCommitResult> commit(
    List<FirestoreWrite> writes, {
    String? transaction,
  }) async {
    final json = await _send(
      'POST',
      '$_root:commit',
      body: {
        'writes': [for (final w in writes) _writeJson(w)],
        'transaction': ?transaction,
      },
    );
    final commitTime = json is Map<String, dynamic> ? json['commitTime'] : null;
    final results = json is Map<String, dynamic>
        ? json['writeResults'] ?? const <Object?>[]
        : null;
    if (commitTime is! String ||
        DateTime.tryParse(commitTime) == null ||
        results is! List ||
        results.length != writes.length) {
      throw const FirestoreFormatException('commit response is malformed.');
    }
    return FirestoreCommitResult(
      commitTime: commitTime,
      updateTimes: [for (final r in results) _updateTimeOf(r)],
    );
  }

  static String? _updateTimeOf(Object? writeResult) {
    final time = writeResult is Map<String, dynamic>
        ? writeResult['updateTime']
        : null;
    return time is String ? time : null;
  }

  /// Abandons [transaction] without writing anything.
  Future<void> rollback(String transaction) async {
    await _send('POST', '$_root:rollback', body: {'transaction': transaction});
  }

  /// Runs [body] in a read-write transaction, retrying the whole body when
  /// Firestore aborts or a precondition conflicts, at most [maxAttempts]
  /// times (then [FirestoreRetryExhausted]). Any attempt that does not
  /// commit is rolled back. Other errors are not retried.
  ///
  /// If a commit fails with a network error it may still have been
  /// applied; callers make their writes safe to repeat.
  Future<T> runTransaction<T>(
    Future<T> Function(FirestoreTransaction transaction) body,
  ) async {
    String? previous;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) {
        await _sleep(jitteredBackoffFor(attempt - 1, _random()));
      }
      FirestoreTransaction? transaction;
      try {
        transaction = FirestoreTransaction._(
          this,
          await beginTransaction(retrying: previous),
        );
        final value = await body(transaction);
        if (!transaction._committed) await _rollbackQuietly(transaction.id);
        return value;
      } on FirestoreConflict {
        if (transaction != null) {
          previous = transaction.id;
          if (!transaction._committed) await _rollbackQuietly(transaction.id);
        }
      } on Object {
        if (transaction != null && !transaction._committed) {
          await _rollbackQuietly(transaction.id);
        }
        rethrow;
      }
    }
    throw FirestoreRetryExhausted(maxAttempts);
  }

  /// Closes the HTTP client.
  void close() => _client.close();

  Future<void> _rollbackQuietly(String transaction) async {
    try {
      await rollback(transaction);
    } on Object {
      // The transaction expires on its own; the original outcome matters.
    }
  }

  Map<String, Object?> _writeJson(FirestoreWrite write) {
    final name = documentName(write.path);
    return {
      if (write.isDelete)
        'delete': name
      else
        'update': {
          'name': name,
          'fields': encodeFirestoreFields(write.fields!),
        },
      if (write.updateMask case final mask?)
        'updateMask': {
          'fieldPaths': [for (final p in mask) _checkFieldPath(p)],
        },
      if (write.transforms.isNotEmpty)
        'updateTransforms': [for (final t in write.transforms) t._toJson()],
      if (write.precondition case final condition?)
        'currentDocument': condition._toJson(),
    };
  }

  /// Decodes a document, checking it is the one asked for ([expectedName])
  /// or lies under the queried parent ([under]).
  FirestoreDocument _document(
    Object? json, {
    String? expectedName,
    String? under,
  }) {
    if (json is! Map<String, dynamic>) {
      throw const FirestoreFormatException('Document is malformed.');
    }
    final name = json['name'];
    final updateTime = json['updateTime'];
    final belongs =
        name is String &&
        name.startsWith('$_root/') &&
        (expectedName == null || name == expectedName) &&
        (under == null || name.startsWith(under));
    if (!belongs || updateTime is! String) {
      throw const FirestoreFormatException(
        'Document name or update time is malformed.',
      );
    }
    return FirestoreDocument(
      path: name.substring(_root.length + 1),
      fields: decodeFirestoreFields(json['fields'] ?? const {}),
      updateTime: updateTime,
    );
  }

  Uri _url(String path, [Map<String, String>? query]) =>
      baseUri.scheme == 'http'
      ? Uri.http(baseUri.authority, '/v1/$path', query)
      : Uri.https(baseUri.authority, '/v1/$path', query);

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final url = _url(path, query);
    _refuseOutsideEmulator(url, _resolveReal);
    if (_extraEndpointCheck case final check?) {
      _refuseOutsideEmulator(url, () => _resolveWith(check));
    }

    final String token;
    try {
      token = await _accessToken();
    } on FirebaseAdminException {
      rethrow;
    } on Exception {
      throw const FirestoreUnavailable('Could not get a Firestore token.');
    }

    final request = http.Request(method, url)
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(requestTimeout);
    } on Exception {
      throw FirestoreUnavailable('Firestore $method request did not complete.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _errorFor(method, response);
    }
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw FirestoreFormatException('Firestore $method response is not JSON.');
    }
  }

  /// Maps an HTTP error to an exception. Only the status code and
  /// Firestore's status name are kept; the body is never included.
  static FirestoreException _errorFor(String method, http.Response response) {
    String? status;
    try {
      final json = jsonDecode(response.body);
      final error = json is Map<String, dynamic> ? json['error'] : null;
      final value = error is Map<String, dynamic> ? error['status'] : null;
      if (value is String && RegExp(r'^[A-Z_]{1,40}$').hasMatch(value)) {
        status = value;
      }
    } on FormatException {
      // Not JSON: the HTTP status alone decides.
    }
    final code = response.statusCode;
    final message =
        'Firestore $method returned HTTP $code${_withSpace(status)}.';
    return switch (code) {
      404 => FirestoreNotFound(message, statusCode: code, status: status),
      409 => FirestoreConflict(message, statusCode: code, status: status),
      400 when status == 'FAILED_PRECONDITION' => FirestoreConflict(
        message,
        statusCode: code,
        status: status,
      ),
      400 => FirestoreBadRequest(message, statusCode: code, status: status),
      401 || 403 => FirestorePermissionDenied(
        message,
        statusCode: code,
        status: status,
      ),
      408 || 429 || >= 500 => FirestoreUnavailable(
        message,
        statusCode: code,
        status: status,
      ),
      _ => FirestoreException(message, statusCode: code, status: status),
    };
  }

  static String _withSpace(String? status) => status == null ? '' : ' $status';

  /// In emulator mode, refuses [url] unless it is the emulator.
  static void _refuseOutsideEmulator(
    Uri url,
    FirestoreEndpoint Function() resolve,
  ) {
    final endpoint = resolve();
    if (endpoint.isEmulator &&
        (url.scheme != endpoint.baseUri.scheme ||
            url.authority != endpoint.baseUri.authority)) {
      throw const FirebaseAdminException(
        'Firestore emulator mode is on, so requests outside the emulator '
        'are refused',
      );
    }
  }

  static FirestoreEndpoint _resolveReal() =>
      _resolveWith(FirestoreEndpoint.resolve);

  static FirestoreEndpoint _resolveWith(FirestoreEndpoint Function() resolve) {
    try {
      return resolve();
    } on FirestoreEndpointException catch (e) {
      throw FirebaseAdminException('Invalid Firestore settings: ${e.message}');
    }
  }
}

/// A running read-write transaction (see [FirestoreRest.runTransaction]).
/// Reads lock what they read until the transaction ends.
class FirestoreTransaction {
  FirestoreTransaction._(this._rest, this.id);

  final FirestoreRest _rest;

  /// Firestore's transaction id.
  final String id;

  bool _committed = false;
  bool _commitAttempted = false;

  String get _active {
    if (_commitAttempted) {
      throw StateError('This transaction has already been committed.');
    }
    return id;
  }

  /// Reads one document inside the transaction.
  Future<FirestoreDocument?> get(String path) =>
      _rest.get(path, transaction: _active);

  /// Reads several documents inside the transaction.
  Future<Map<String, FirestoreDocument?>> batchGet(List<String> paths) =>
      _rest.batchGet(paths, transaction: _active);

  /// Runs a query inside the transaction.
  Future<List<FirestoreDocument>> runQuery(
    Map<String, Object?> structuredQuery, {
    String parent = '',
  }) => _rest.runQuery(structuredQuery, parent: parent, transaction: _active);

  /// Commits [writes]; at most once per transaction. A failed existence
  /// precondition (Firestore reports NOT_FOUND) counts as a conflict, so
  /// the transaction is retried.
  Future<FirestoreCommitResult> commit(List<FirestoreWrite> writes) async {
    final transaction = _active;
    _commitAttempted = true;
    try {
      final result = await _rest.commit(writes, transaction: transaction);
      _committed = true;
      return result;
    } on FirestoreNotFound catch (e) {
      throw FirestoreConflict(
        e.message,
        statusCode: e.statusCode,
        status: e.status ?? 'NOT_FOUND',
      );
    }
  }
}

final _fieldPath = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$',
);

String _checkFieldPath(String path) {
  if (!_fieldPath.hasMatch(path)) {
    throw ArgumentError.value(path, 'fieldPath', 'Not a simple field path');
  }
  return path;
}
