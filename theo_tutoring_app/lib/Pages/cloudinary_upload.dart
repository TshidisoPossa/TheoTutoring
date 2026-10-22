import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// Fill these in from your Cloudinary dashboard (free tier — no card needed).
const String _cloudName = 'ejckimby';
const String _uploadPreset = 'theo_unsigned';

// Cloudinary's free plan rejects images larger than 10 MB.
const int _maxBytes = 10 * 1024 * 1024;

/// Thrown when an image could not be uploaded. [message] is written for the
/// user, so pages can show it as it is.
class CloudinaryUploadException implements Exception {
  const CloudinaryUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Uploads [file] to Cloudinary using an unsigned preset and returns the
/// resulting secure image URL. Store this URL string in MySQL, not the file.
///
/// Reads the file as bytes so it works on web as well as desktop and mobile.
/// Throws a [CloudinaryUploadException] explaining what went wrong.
Future<String> uploadToCloudinary(XFile file) async {
  final List<int> bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (_) {
    throw const CloudinaryUploadException(
      'Could not read the selected image. Please choose it again.',
    );
  }
  if (bytes.isEmpty) {
    throw const CloudinaryUploadException('The selected image is empty.');
  }
  if (bytes.length > _maxBytes) {
    throw const CloudinaryUploadException(
      'The image is larger than 10 MB. Please choose a smaller one.',
    );
  }

  final request = http.MultipartRequest(
    'POST',
    Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload'),
  )
    ..fields['upload_preset'] = _uploadPreset
    ..files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: _fileName(file)),
    );

  final int status;
  final String body;
  try {
    final response =
        await request.send().timeout(const Duration(seconds: 60));
    status = response.statusCode;
    body = await response.stream.bytesToString();
  } catch (_) {
    throw const CloudinaryUploadException(
      'Could not reach the image server. Check your internet connection '
      'and try again.',
    );
  }

  Map<String, dynamic>? json;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) json = decoded;
  } on FormatException {
    json = null;
  }

  if (status != 200) {
    // Cloudinary explains the problem in {"error": {"message": "..."}}
    final error = json?['error'];
    final reason = error is Map ? error['message'] : null;
    throw CloudinaryUploadException(
      reason is String && reason.isNotEmpty
          ? 'The image was rejected: $reason'
          : 'The image could not be uploaded (error $status). Please try again.',
    );
  }

  final url = json?['secure_url'];
  if (url is! String || url.isEmpty) {
    throw const CloudinaryUploadException(
      'The image server sent an unexpected reply. Please try again.',
    );
  }
  return url;
}

// The picker on web can hand back a name without an extension (or none at
// all); give it one from the file type so Cloudinary keeps the format.
String _fileName(XFile file) {
  final name = file.name.trim().isEmpty ? 'upload' : file.name.trim();
  if (name.contains('.')) return name;
  final type = (file.mimeType ?? '').toLowerCase();
  return '$name.${type.contains('png') ? 'png' : 'jpg'}';
}
