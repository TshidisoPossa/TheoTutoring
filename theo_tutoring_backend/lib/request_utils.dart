import 'package:dart_frog/dart_frog.dart';

/// Builds a JSON error response.
Response jsonError(int statusCode, String? message) {
  return Response.json(
    statusCode: statusCode,
    body: {'error': message ?? 'Invalid request.'},
  );
}

/// Reads the request body as a JSON object.
/// Throws a FormatException (turned into a 400) if it is not one.
Future<Map<String, dynamic>> readJsonObject(RequestContext context) async {
  dynamic raw;
  try {
    raw = await context.request.json();
  } on FormatException {
    throw const FormatException('Request body must be valid JSON.');
  }

  if (raw is! Map<String, dynamic>) {
    throw const FormatException('Request body must be a JSON object.');
  }
  return raw;
}

/// Returns a trimmed string, or null if the field is missing or blank.
/// Throws a FormatException if the field is present but not text,
/// or is longer than [maxLength].
String? optionalString(
  Map<String, dynamic> body,
  String key, {
  int maxLength = 2000,
}) {
  final value = body[key];
  if (value == null) return null;

  if (value is! String) {
    throw FormatException('$key must be text.');
  }

  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  if (trimmed.length > maxLength) {
    throw FormatException('$key must be $maxLength characters or fewer.');
  }
  return trimmed;
}
