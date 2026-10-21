import 'package:theo_tutoring_backend/env.dart';

// Files (profile photos, certificates, ID documents) are uploaded by the app
// straight to Cloudinary. The backend only receives the URL, so it checks the
// URL really points at this project's Cloudinary account before saving it.

/// File types allowed for pictures (profile photo).
const cloudinaryImageTypes = {'jpg', 'jpeg', 'png'};

/// File types allowed for documents (certificate, ID document).
const cloudinaryDocumentTypes = {'pdf', 'jpg', 'jpeg', 'png'};

/// The project's Cloudinary cloud name, from CLOUDINARY_CLOUD_NAME.
/// Throws a StateError if it is not set.
String cloudinaryCloudName() {
  final cloudName = env['CLOUDINARY_CLOUD_NAME'];
  if (cloudName == null || cloudName.isEmpty) {
    throw StateError('CLOUDINARY_CLOUD_NAME is not set');
  }
  return cloudName;
}

/// Checks that a URL is an HTTPS link to a file in this project's
/// Cloudinary account, with an allowed file type.
/// Returns an error message, or null if the URL is valid.
String? checkCloudinaryUrl(
  String url,
  String label,
  Set<String> allowedTypes,
  String cloudName,
) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'res.cloudinary.com' ||
      uri.pathSegments.length < 2 ||
      uri.pathSegments.first != cloudName) {
    return '$label must be a file uploaded through the app.';
  }

  final fileName = uri.pathSegments.last;
  final dot = fileName.lastIndexOf('.');
  final extension = dot == -1 ? '' : fileName.substring(dot + 1).toLowerCase();

  if (!allowedTypes.contains(extension)) {
    final allowed = allowedTypes.map((t) => t.toUpperCase()).join(', ');
    return '$label must be one of these file types: $allowed.';
  }
  return null;
}
