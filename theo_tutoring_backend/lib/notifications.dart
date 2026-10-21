import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:theo_tutoring_backend/firebase_admin.dart';

// In-app notifications live in Firestore, not MySQL (project documentation
// 11.2 / 11.4): notifications/{firebaseUid}/items, one document per
// notification, with the fields type, title, body, bookingId, read, createdAt.
// The app reads them through these backend routes; only the backend writes.

/// Notification types, one per event in project documentation 4.8.
abstract final class NotificationType {
  /// A student requested a booking (to the tutor).
  static const bookingRequested = 'BookingRequested';

  /// The tutor accepted a booking (to the student).
  static const bookingAccepted = 'BookingAccepted';

  /// The tutor declined a booking (to the student).
  static const bookingDeclined = 'BookingDeclined';

  /// The booking was paid and confirmed (to both).
  static const bookingConfirmed = 'BookingConfirmed';

  /// A booking was cancelled.
  static const bookingCancelled = 'BookingCancelled';

  /// The tutor moved a booking to a new time (to the student, who must
  /// confirm it).
  static const bookingPostponed = 'BookingPostponed';

  /// A payment went through.
  static const paymentReceived = 'PaymentReceived';

  /// A payment failed.
  static const paymentFailed = 'PaymentFailed';

  /// A new chat message ("New message").
  static const newMessage = 'NewMessage';

  /// Session reminder ("Upcoming lesson").
  static const upcomingSession = 'UpcomingSession';

  /// Tutor application approved.
  static const applicationApproved = 'ApplicationApproved';

  /// Tutor application rejected.
  static const applicationRejected = 'ApplicationRejected';

  /// Every valid type.
  static const all = {
    bookingRequested,
    bookingAccepted,
    bookingDeclined,
    bookingConfirmed,
    bookingCancelled,
    bookingPostponed,
    paymentReceived,
    paymentFailed,
    newMessage,
    upcomingSession,
    applicationApproved,
    applicationRejected,
  };
}

/// Thrown when Firestore cannot be reached or rejects a request.
class NotificationServiceException implements Exception {
  /// Creates the exception with Firestore's HTTP status, if there was one.
  const NotificationServiceException(this.message, [this.statusCode]);

  /// What went wrong (for the server log, not the user).
  final String message;

  /// Firestore's HTTP status code, or null for network errors.
  final int? statusCode;

  @override
  String toString() => 'NotificationServiceException($statusCode): $message';
}

/// One notification card, e.g. "New message" /
/// "You have a new message from Lerato." / 2 min ago.
class AppNotification {
  /// Creates a notification.
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.bookingId,
  });

  /// Builds a notification from a Firestore REST document.
  factory AppNotification.fromFirestore(Map<String, dynamic> doc) {
    final fields = (doc['fields'] as Map<String, dynamic>?) ?? const {};
    final name = doc['name'] as String;
    return AppNotification(
      id: name.substring(name.lastIndexOf('/') + 1), // last path segment
      type: _string(fields['type']) ?? '',
      title: _string(fields['title']) ?? '',
      body: _string(fields['body']) ?? '',
      bookingId: int.tryParse(_string(fields['bookingId']) ?? ''),
      read: _bool(fields['read']) ?? false,
      createdAt:
          DateTime.tryParse(_string(fields['createdAt']) ?? '') ??
          DateTime.tryParse(doc['createTime'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  /// Firestore document ID.
  final String id;

  /// One of [NotificationType.all].
  final String type;

  /// Short label shown above the message, e.g. "Upcoming lesson".
  final String title;

  /// The message, e.g. "You're tutoring Lesego in Maths in an hour."
  final String body;

  /// MySQL Booking_id this is about, if any ("View scheduled lesson").
  final int? bookingId;

  /// Whether the user has read it (unread cards show a blue dot).
  final bool read;

  /// When it was created.
  final DateTime createdAt;

  /// JSON for the app. [now] is only passed in by tests.
  Map<String, dynamic> toJson({DateTime? now}) {
    final current = now ?? DateTime.now();
    final minutesAgo = current.difference(createdAt).inMinutes;
    return {
      'id': id,
      'type': type,
      'title': title,
      'body': body,
      'bookingId': bookingId,
      'read': read,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'minutesAgo': minutesAgo < 0 ? 0 : minutesAgo, // "2 min ago"
      'section': sectionFor(createdAt, current), // "Today" / "Yesterday"
    };
  }

  /// Which heading the card goes under: 'today', 'yesterday' or 'earlier'
  /// (by the server's local date).
  static String sectionFor(DateTime createdAt, DateTime now) {
    final created = createdAt.toLocal();
    final current = now.toLocal();
    final day = DateTime(created.year, created.month, created.day);
    final today = DateTime(current.year, current.month, current.day);
    final yesterday = DateTime(current.year, current.month, current.day - 1);
    if (!day.isBefore(today)) return 'today';
    if (day == yesterday) return 'yesterday';
    return 'earlier';
  }

  /// Firestore field map for a new notification.
  Map<String, dynamic> toFirestoreFields() => {
    'type': {'stringValue': type},
    'title': {'stringValue': title},
    'body': {'stringValue': body},
    'bookingId': bookingId == null
        ? {'nullValue': null}
        : {'integerValue': '$bookingId'},
    'read': {'booleanValue': read},
    'createdAt': {'timestampValue': createdAt.toUtc().toIso8601String()},
  };

  static String? _string(dynamic value) {
    if (value is! Map) return null;
    final v =
        value['stringValue'] ??
        value['integerValue'] ??
        value['timestampValue'];
    return v is String ? v : null;
  }

  static bool? _bool(dynamic value) =>
      value is Map && value['booleanValue'] is bool
      ? value['booleanValue'] as bool
      : null;
}

/// Reads and writes notifications/{firebaseUid}/items through the
/// Firestore REST API.
class NotificationStore {
  /// Creates a store. Tests pass their own [client] and [accessToken].
  NotificationStore({
    required this.projectId,
    required Future<String> Function() accessToken,
    http.Client? client,
  }) : _accessToken = accessToken,
       _client = client ?? http.Client();

  /// A store signed in with the backend's Firebase service account.
  /// Throws a [FirebaseAdminException] if the service account is not set up.
  factory NotificationStore.fromFirebaseAdmin() {
    final admin = FirebaseAdmin.instance;
    return NotificationStore(
      projectId: admin.projectId,
      accessToken: admin.accessToken,
    );
  }

  /// Firebase project the notifications belong to.
  final String projectId;
  final Future<String> Function() _accessToken;
  final http.Client _client;

  /// Most notifications one list request returns.
  static const maxLimit = 100;

  // Firestore allows at most 500 writes per commit.
  static const _batchSize = 500;

  static final _documentId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  /// Whether [id] looks like a Firestore document ID (rejects path tricks).
  static bool isValidId(String id) => _documentId.hasMatch(id);

  String get _root => 'projects/$projectId/databases/(default)/documents';

  String _parent(String uid) =>
      '$_root/notifications/${Uri.encodeComponent(uid)}';

  Uri _url(String path, [Map<String, dynamic>? query]) => Uri.https(
    'firestore.googleapis.com',
    '/v1/$path',
    query,
  );

  static const _unreadFilter = {
    'fieldFilter': {
      'field': {'fieldPath': 'read'},
      'op': 'EQUAL',
      'value': {'booleanValue': false},
    },
  };

  /// The user's notifications, newest first.
  Future<List<AppNotification>> list(String uid, {int limit = 50}) async {
    final rows = await _send('POST', _url('${_parent(uid)}:runQuery'), {
      'structuredQuery': {
        'from': [
          {'collectionId': 'items'},
        ],
        'orderBy': [
          {
            'field': {'fieldPath': 'createdAt'},
            'direction': 'DESCENDING',
          },
        ],
        'limit': limit.clamp(1, maxLimit),
      },
    });
    return _documents(rows).map(AppNotification.fromFirestore).toList();
  }

  /// How many of the user's notifications are unread (the bell badge).
  Future<int> unreadCount(String uid) async {
    final rows = await _send(
      'POST',
      _url('${_parent(uid)}:runAggregationQuery'),
      {
        'structuredAggregationQuery': {
          'structuredQuery': {
            'from': [
              {'collectionId': 'items'},
            ],
            'where': _unreadFilter,
          },
          'aggregations': [
            {'alias': 'unread', 'count': <String, dynamic>{}},
          ],
        },
      },
    );
    for (final row in (rows as List).whereType<Map<String, dynamic>>()) {
      final result = row['result'];
      if (result is! Map<String, dynamic>) continue;
      final fields = result['aggregateFields'];
      if (fields is! Map<String, dynamic>) continue;
      final unread = fields['unread'];
      if (unread is Map<String, dynamic>) {
        return int.tryParse('${unread['integerValue']}') ?? 0;
      }
    }
    return 0;
  }

  /// Marks one notification as read. Returns false if it does not exist.
  Future<bool> markRead(String uid, String id) async {
    try {
      await _send(
        'PATCH',
        _url('${_parent(uid)}/items/$id', {
          'updateMask.fieldPaths': 'read',
          'currentDocument.exists': 'true', // never create a new document
        }),
        {
          'fields': {
            'read': {'booleanValue': true},
          },
        },
      );
      return true;
    } on NotificationServiceException catch (e) {
      if (e.statusCode == 404) return false;
      rethrow;
    }
  }

  /// Marks every unread notification as read ("Mark all as read").
  /// Returns how many were changed.
  Future<int> markAllRead(String uid) async {
    var total = 0;
    // Each pass reads up to 500 unread IDs and marks them read in one commit;
    // stop when a pass finds fewer than a full batch.
    for (var pass = 0; pass < 20; pass++) {
      final rows = await _send('POST', _url('${_parent(uid)}:runQuery'), {
        'structuredQuery': {
          'select': {
            'fields': [
              {'fieldPath': '__name__'},
            ],
          },
          'from': [
            {'collectionId': 'items'},
          ],
          'where': _unreadFilter,
          'limit': _batchSize,
        },
      });
      final names = _documents(rows).map((d) => d['name'] as String).toList();
      if (names.isEmpty) break;

      await _send('POST', _url('$_root:commit'), {
        'writes': [
          for (final name in names)
            {
              'update': {
                'name': name,
                'fields': {
                  'read': {'booleanValue': true},
                },
              },
              'updateMask': {
                'fieldPaths': ['read'],
              },
              'currentDocument': {'exists': true},
            },
        ],
      });
      total += names.length;
      if (names.length < _batchSize) break;
    }
    return total;
  }

  /// Adds a notification for a user. Booking, chat and admin code call this
  /// when an event in project documentation 4.8 happens.
  Future<AppNotification> create({
    required String uid,
    required String type,
    required String title,
    required String body,
    int? bookingId,
  }) async {
    if (!NotificationType.all.contains(type)) {
      throw ArgumentError.value(type, 'type', 'Unknown notification type');
    }
    if (title.trim().isEmpty || body.trim().isEmpty) {
      throw ArgumentError('title and body must not be empty');
    }

    final draft = AppNotification(
      id: '',
      type: type,
      title: title.trim(),
      body: body.trim(),
      bookingId: bookingId,
      read: false,
      createdAt: DateTime.now().toUtc(),
    );
    final doc = await _send('POST', _url('${_parent(uid)}/items'), {
      'fields': draft.toFirestoreFields(),
    });
    return AppNotification.fromFirestore(doc as Map<String, dynamic>);
  }

  // runQuery returns one row per document; an empty result is a single row
  // without a "document" key.
  static Iterable<Map<String, dynamic>> _documents(dynamic rows) =>
      (rows as List)
          .whereType<Map<String, dynamic>>()
          .map((row) => row['document'])
          .whereType<Map<String, dynamic>>();

  Future<dynamic> _send(String method, Uri url, Object body) async {
    // A service-account problem is a FirebaseAdminException (server error);
    // being unable to reach Google is treated like Firestore being down.
    final String token;
    try {
      token = await _accessToken();
    } on FirebaseAdminException {
      rethrow;
    } on Exception catch (e) {
      throw NotificationServiceException('Could not get an access token: $e');
    }
    final request = http.Request(method, url)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } on Exception catch (e) {
      throw NotificationServiceException('Firestore request failed: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NotificationServiceException(
        'Firestore returned ${response.statusCode}: ${response.body}',
        response.statusCode,
      );
    }
    return jsonDecode(response.body);
  }
}
