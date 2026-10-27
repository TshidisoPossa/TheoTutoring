import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:theo_tutoring_backend/booking_availability.dart';
import 'package:theo_tutoring_backend/booking_domain.dart';
import 'package:theo_tutoring_backend/database.dart';
import 'package:theo_tutoring_backend/firebase_auth.dart';

typedef StudentIdResolver = Future<int> Function(String? authorization);

Future<Response> onRequest(RequestContext context) => handleAvailability(
  context,
);

Future<Response> handleAvailability(
  RequestContext context, {
  Future<BookingAvailabilityRepository> Function()? repositoryFactory,
  StudentIdResolver? studentIdResolver,
  DateTime Function()? clock,
}) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'Only GET requests are supported.'},
    );
  }

  final nowUtc = (clock ?? DateTime.now)().toUtc();
  final options = _parseOptions(context.request.uri, nowUtc);
  if (options == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {
        'error':
            'Provide one valid tutorId, subjectId, from, and through parameter. '
            'Dates must be within the next 90 days.',
      },
    );
  }

  final authorization =
      context.request.headers['authorization'] ??
      context.request.headers['Authorization'];
  try {
    final studentId = await (studentIdResolver ?? _resolveStudentId)(
      authorization,
    );
    final repository = await (repositoryFactory ?? _defaultRepository)();
    final request = AvailabilityRequest(
      studentId: studentId,
      tutorId: options.tutorId,
      subjectId: options.subjectId,
      from: options.from,
      through: options.through,
      nowUtc: nowUtc,
    );
    final snapshot = await repository.load(request);
    if (snapshot == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Approved tutor or tutor subject was not found.'},
      );
    }

    final price = calculateBookingPrice(
      platformRate: snapshot.platformRate,
      purchaseType: 'Single',
      lessonCount: 1,
    );
    final available = findAvailableLessons(
      from: options.from,
      through: options.through,
      nowUtc: nowUtc,
      availability: snapshot.weeklyAvailability,
      busyIntervals: snapshot.busyIntervals,
      overrides: snapshot.availabilityOverrides,
    );
    return Response.json(
      body: {
        'timezone': 'Africa/Johannesburg',
        'tutorId': options.tutorId,
        'from': options.from.iso,
        'through': options.through.iso,
        'hourlyRate': price.rate,
        'slots': [
          for (final slot in available)
            {
              'date': slot.date,
              'startTime': slot.startTime,
              'endTime': slot.endTime,
            },
        ],
      },
    );
  } on AuthTokenException catch (error) {
    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': error.message},
    );
  } on StudentAccountException catch (error) {
    return Response.json(
      statusCode: error.statusCode,
      body: {'error': error.message},
    );
  } on BookingAvailabilityUnavailable catch (error, stackTrace) {
    stderr.writeln(
      'Student availability configuration failure '
      '(${error.runtimeType}).\n$stackTrace',
    );
    return Response.json(
      statusCode: HttpStatus.serviceUnavailable,
      body: {'error': 'Availability is temporarily unavailable.'},
    );
  } catch (error, stackTrace) {
    stderr.writeln(
      'Student availability failure (${error.runtimeType}).\n$stackTrace',
    );
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Availability is temporarily unavailable.'},
    );
  }
}

class StudentAccountException implements Exception {
  const StudentAccountException(this.statusCode, this.message);

  final int statusCode;
  final String message;
}

class _AvailabilityOptions {
  const _AvailabilityOptions({
    required this.tutorId,
    required this.subjectId,
    required this.from,
    required this.through,
  });

  final int tutorId;
  final int subjectId;
  final BookingDate from;
  final BookingDate through;
}

_AvailabilityOptions? _parseOptions(Uri uri, DateTime nowUtc) {
  final parameters = uri.queryParametersAll;
  const allowed = {'tutorId', 'subjectId', 'from', 'through'};
  if (parameters.keys.any((key) => !allowed.contains(key)) ||
      parameters.values.any((values) => values.length != 1) ||
      parameters.length != allowed.length) {
    return null;
  }

  final rawTutorId = parameters['tutorId']?.single;
  final rawSubjectId = parameters['subjectId']?.single;
  if (rawTutorId == null ||
      rawSubjectId == null ||
      !RegExp(r'^[0-9]+$').hasMatch(rawTutorId) ||
      !RegExp(r'^[0-9]+$').hasMatch(rawSubjectId)) {
    return null;
  }
  final tutorId = int.tryParse(rawTutorId);
  final subjectId = int.tryParse(rawSubjectId);
  if (tutorId == null ||
      tutorId < 1 ||
      tutorId > 2147483647 ||
      subjectId == null ||
      subjectId < 1 ||
      subjectId > 2147483647) {
    return null;
  }

  try {
    final from = BookingDate.parse(parameters['from']!.single);
    final through = BookingDate.parse(parameters['through']!.single);
    final today = johannesburgDate(nowUtc);
    if (today.daysUntil(from) < 0 ||
        from.daysUntil(through) < 0 ||
        today.daysUntil(through) > maximumBookingDays) {
      return null;
    }
    return _AvailabilityOptions(
      tutorId: tutorId,
      subjectId: subjectId,
      from: from,
      through: through,
    );
  } on FormatException {
    return null;
  }
}

Future<int> _resolveStudentId(String? authorization) async {
  final firebaseUser = await verifyFirebaseToken(authorization);
  final connection = await getConnection();
  final result = await connection.execute(
    '''
    SELECT sp.StudentID, u.AccountStatus
    FROM `User` u
    INNER JOIN StudentProfile sp ON sp.UserID = u.UserId
    WHERE u.FirebaseUid = :uid AND u.Role = 'student'
    LIMIT 1
    ''',
    {'uid': firebaseUser.uid},
  );
  if (result.rows.isEmpty) {
    throw const StudentAccountException(
      HttpStatus.notFound,
      'Student account or profile not found.',
    );
  }
  if (result.rows.first.colByName('AccountStatus') != 'Active') {
    throw const StudentAccountException(
      HttpStatus.forbidden,
      'An active student account is required.',
    );
  }
  final studentId = result.rows.first.colByName('StudentID');
  final resolvedStudentId = int.tryParse(studentId ?? '');
  if (resolvedStudentId == null || resolvedStudentId < 1) {
    throw const BookingAvailabilityUnavailable();
  }
  return resolvedStudentId;
}

Future<BookingAvailabilityRepository> _defaultRepository() async =>
    MySqlBookingAvailabilityRepository(await getConnection());
