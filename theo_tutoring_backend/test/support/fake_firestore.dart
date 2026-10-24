import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:theo_tutoring_backend/chat_store.dart';
import 'package:theo_tutoring_backend/firestore_rest.dart';

// A fake Firestore behind a fake HTTP client, shared by the chat tests (no
// network). It enforces what the chat store relies on the server for: a
// transaction's commit aborts if anything it read has changed, and every
// write precondition is checked. It rejects server-side transforms and
// answers with a deliberately unrelated commitTime.

/// Project the fake serves.
const fakeFirestoreProject = 'theo-test';

/// Documents root of [fakeFirestoreProject].
const fakeFirestoreRoot =
    'projects/$fakeFirestoreProject/databases/(default)/documents';

const _root = fakeFirestoreRoot;

/// A stored document.
typedef FakeDoc = ({Map<String, Object?> fields, String updateTime});

/// The fake. Tests read and seed [docs] directly.
class FakeFirestore {
  /// Creates an empty fake.
  FakeFirestore({this.checkReadSet = true});

  /// Abort commits whose transaction read something that has changed.
  final bool checkReadSet;

  final docs = <String, FakeDoc>{};
  final requests = <http.Request>[];
  final commitBodies = <Map<String, dynamic>>[];
  final commitFailures = <String>[];
  final _reads = <String, Map<String, String?>>{};
  var _time = 0;
  var _transactions = 0;
  int commits = 0;

  /// Runs at the start of every commit: another client acting between a
  /// transaction's reads and its commit.
  void Function(int commit)? beforeCommit;

  /// Applies a commit, then answers 503 (the reply is lost).
  bool loseNextCommitReply = false;

  late final client = MockClient(_handle);

  FirestoreRest rest({int maxAttempts = 5}) => FirestoreRest(
    projectId: fakeFirestoreProject,
    accessToken: () async => 'token',
    client: client,
    maxAttempts: maxAttempts,
    sleep: (_) async {},
  );

  String _nextTime() =>
      '2026-10-24T10:00:00.${(++_time).toString().padLeft(9, '0')}Z';

  void put(String path, Map<String, Object?> fields) =>
      docs[path] = (fields: fields, updateTime: _nextTime());

  void enableChat({bool enabled = true}) =>
      put(chatConfigPath, {'enabled': enabled});

  Map<String, Object?>? fields(String path) => docs[path]?.fields;

  List<String> paths(String prefix) =>
      docs.keys.where((p) => p.startsWith(prefix)).toList()..sort();

  /// Commits [writes] as another client would (no transaction).
  void apply(List<FirestoreWrite> writes) {
    final rest = this.rest();
    final json = [
      for (final w in writes)
        jsonDecode(
              jsonEncode(
                w.isDelete
                    ? {'delete': rest.documentName(w.path)}
                    : {
                        'update': {
                          'name': rest.documentName(w.path),
                          'fields': encodeFirestoreFields(w.fields!),
                        },
                        if (w.updateMask != null)
                          'updateMask': {'fieldPaths': w.updateMask},
                      },
              ),
            )
            as Map<String, dynamic>,
    ];
    _applyWrites(json, _nextTime());
  }

  Map<String, Object?> _docJson(String path) => {
    'name': '$_root/$path',
    'fields': encodeFirestoreFields(docs[path]!.fields),
    'updateTime': docs[path]!.updateTime,
  };

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final full = request.url.path.substring('/v1/'.length);
    final rest = full.substring(_root.length);
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;

    if (request.method == 'DELETE') return _delete(rest.substring(1), request);
    if (request.method == 'POST' &&
        request.url.queryParameters.containsKey('documentId')) {
      final path =
          '${rest.substring(1)}/${request.url.queryParameters['documentId']}';
      if (docs.containsKey(path)) return _error(409, 'ALREADY_EXISTS');
      docs[path] = (
        fields: decodeFirestoreFields(body['fields']),
        updateTime: _nextTime(),
      );
      return _json(_docJson(path));
    }
    if (request.method == 'GET') {
      final path = rest.substring(1);
      return docs.containsKey(path)
          ? _json(_docJson(path))
          : _error(404, 'NOT_FOUND');
    }
    switch (rest) {
      case ':beginTransaction':
        final id = 'tx-${++_transactions}';
        _reads[id] = {};
        return _json({'transaction': id});
      case ':rollback':
        _reads.remove(body['transaction']);
        return _json(<String, Object?>{});
      case ':batchGet':
        final reads = _reads[body['transaction']];
        return _json([
          for (final name in (body['documents'] as List).cast<String>())
            () {
              final path = name.substring(_root.length + 1);
              reads?[path] = docs[path]?.updateTime;
              return docs.containsKey(path)
                  ? {'found': _docJson(path)}
                  : {'missing': name};
            }(),
        ]);
      case ':commit':
        return _commit(body);
    }
    if (rest.endsWith(':runQuery')) {
      final parent = rest.substring(0, rest.length - ':runQuery'.length);
      return _json(
        _query(
          parent.isEmpty ? '' : parent.substring(1),
          body['structuredQuery'] as Map<String, dynamic>,
        ),
      );
    }
    return _error(400, 'INVALID_ARGUMENT');
  }

  /// Runs before each DELETE: another client acting first.
  void Function(String path)? beforeDelete;

  /// Paths deleted, in order.
  final deleted = <String>[];

  http.Response _delete(String path, http.Request request) {
    beforeDelete?.call(path);
    final time = request.url.queryParameters['currentDocument.updateTime'];
    final exists = request.url.queryParameters['currentDocument.exists'];
    if (!docs.containsKey(path)) {
      return time != null || exists == 'true'
          ? _error(404, 'NOT_FOUND')
          : _json(<String, Object?>{});
    }
    // Like the Firestore emulator: an update-time condition sent as a
    // DELETE query parameter is read as version 0 and always fails.
    if (time != null) return _error(400, 'FAILED_PRECONDITION');
    docs.remove(path);
    deleted.add(path);
    return _json(<String, Object?>{});
  }

  http.Response _commit(Map<String, dynamic> body) {
    commitBodies.add(body);
    commits++;
    beforeCommit?.call(commits);
    final transaction = body['transaction'] as String?;
    if (transaction != null) {
      final reads = _reads.remove(transaction);
      if (reads == null) return _error(400, 'INVALID_ARGUMENT');
      if (checkReadSet &&
          reads.entries.any((e) => docs[e.key]?.updateTime != e.value)) {
        return _fail(409, 'ABORTED');
      }
    }
    final writes = (body['writes'] as List).cast<Map<String, dynamic>>();
    for (final w in writes) {
      if (w.containsKey('updateTransforms')) {
        return _fail(400, 'INVALID_ARGUMENT'); // the store must not use them
      }
      final path = _pathOf(w);
      final condition = w['currentDocument'] as Map<String, dynamic>?;
      if (condition == null) continue;
      if (condition['exists'] == false && docs.containsKey(path)) {
        return _fail(409, 'ALREADY_EXISTS');
      }
      if (condition['exists'] == true && !docs.containsKey(path)) {
        return _fail(404, 'NOT_FOUND');
      }
      if (condition['updateTime'] case final String time
          when docs[path]?.updateTime != time) {
        return _fail(400, 'FAILED_PRECONDITION');
      }
    }
    final time = _nextTime();
    _applyWrites(writes, time);
    if (loseNextCommitReply) {
      loseNextCommitReply = false;
      return _error(503, 'UNAVAILABLE');
    }
    return _json({
      // Deliberately unrelated to any stored time.
      'commitTime': '1999-01-01T00:00:00Z',
      'writeResults': [
        for (final _ in writes) {'updateTime': time},
      ],
    });
  }

  void _applyWrites(List<Map<String, dynamic>> writes, String time) {
    for (final w in writes) {
      final path = _pathOf(w);
      if (w.containsKey('delete')) {
        docs.remove(path);
        continue;
      }
      final fields = decodeFirestoreFields(
        (w['update'] as Map<String, dynamic>)['fields'],
      );
      final mask = (w['updateMask'] as Map<String, dynamic>?)?['fieldPaths'];
      if (mask == null) {
        docs[path] = (fields: fields, updateTime: time);
        continue;
      }
      final merged = _copy(docs[path]?.fields ?? const {});
      for (final fieldPath in (mask as List).cast<String>()) {
        final parts = fieldPath.split('.');
        Object? source = fields;
        var present = true;
        for (final part in parts) {
          if (source is Map<String, Object?> && source.containsKey(part)) {
            source = source[part];
          } else {
            present = false;
            break;
          }
        }
        var target = merged;
        for (final part in parts.take(parts.length - 1)) {
          target =
              (target[part] ??= <String, Object?>{}) as Map<String, Object?>;
        }
        if (present) {
          target[parts.last] = source;
        } else {
          target.remove(parts.last);
        }
      }
      docs[path] = (fields: merged, updateTime: time);
    }
  }

  List<Object?> _query(String parent, Map<String, dynamic> q) {
    final collection =
        ((q['from'] as List).single as Map<String, dynamic>)['collectionId'];
    final prefix = parent.isEmpty ? '$collection/' : '$parent/$collection/';
    Object? value(String path, String field) {
      if (field == '__name__') return '$_root/$path';
      Object? v = docs[path]!.fields;
      for (final part in field.split('.')) {
        v = v is Map<String, Object?> ? v[part] : null;
      }
      return v;
    }

    var matches = docs.keys
        .where(
          (p) =>
              p.startsWith(prefix) && !p.substring(prefix.length).contains('/'),
        )
        .toList();
    bool matchesFilter(String p, Map<String, dynamic> filter) {
      final field =
          (filter['field'] as Map<String, dynamic>)['fieldPath'] as String;
      final wanted = decodeFirestoreValue(filter['value']);
      final v = value(p, field);
      int cmp() => (v! as Comparable<Object>).compareTo(wanted!);
      return switch (filter['op']) {
        'EQUAL' => v == wanted,
        'LESS_THAN' => v is Comparable<Object> && cmp() < 0,
        'LESS_THAN_OR_EQUAL' => v is Comparable<Object> && cmp() <= 0,
        'GREATER_THAN' => v is Comparable<Object> && cmp() > 0,
        _ => throw UnsupportedError('op ${filter['op']}'),
      };
    }

    if (q['where'] case final Map<String, dynamic> where) {
      final filters = where.containsKey('compositeFilter')
          ? ((where['compositeFilter'] as Map<String, dynamic>)['filters']
                    as List)
                .cast<Map<String, dynamic>>()
                .map((f) => f['fieldFilter'] as Map<String, dynamic>)
                .toList()
          : [where['fieldFilter'] as Map<String, dynamic>];
      matches = matches
          .where((p) => filters.every((f) => matchesFilter(p, f)))
          .toList();
    }
    final orderBy = (q['orderBy'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    int compareValues(List<Object?> a, List<Object?> b) {
      for (var i = 0; i < orderBy.length; i++) {
        final c = (a[i]! as Comparable<Object>).compareTo(b[i]!);
        if (c != 0) return orderBy[i]['direction'] == 'DESCENDING' ? -c : c;
      }
      return 0;
    }

    List<Object?> key(String p) => [
      for (final o in orderBy)
        value(p, (o['field'] as Map<String, dynamic>)['fieldPath'] as String),
    ];
    matches.sort((a, b) => compareValues(key(a), key(b)));
    if (q['startAt'] case final Map<String, dynamic> start) {
      final cursor = [
        for (final v in (start['values'] as List).cast<Map<String, dynamic>>())
          if (v.containsKey('referenceValue'))
            v['referenceValue']
          else
            decodeFirestoreValue(v),
      ];
      expect(start['before'], isFalse);
      matches = matches
          .where((p) => compareValues(key(p), cursor) > 0)
          .toList();
    }
    final limit = q['limit'] as int?;
    if (limit != null && matches.length > limit) {
      matches = matches.sublist(0, limit);
    }
    return matches.isEmpty
        ? [
            {'readTime': _nextTime()},
          ]
        : [
            for (final p in matches) {'document': _docJson(p)},
          ];
  }

  String _pathOf(Map<String, dynamic> write) {
    final name =
        (write['update'] as Map<String, dynamic>?)?['name'] ?? write['delete'];
    return (name as String).substring(_root.length + 1);
  }

  http.Response _fail(int code, String status) {
    commitFailures.add(status);
    return _error(code, status);
  }

  static Map<String, Object?> _copy(Map<String, Object?> m) => {
    for (final MapEntry(:key, :value) in m.entries)
      key: value is Map<String, Object?> ? _copy(value) : value,
  };

  static http.Response _json(Object? body) =>
      http.Response(jsonEncode(body), 200);

  static http.Response _error(int code, String status) => http.Response(
    jsonEncode({
      'error': {'code': code, 'status': status},
    }),
    code,
  );

  List<String> get operations => [
    for (final r in requests)
      if (r.method == 'GET')
        'GET'
      else
        r.url.path.substring(r.url.path.lastIndexOf(':') + 1),
  ];
}
