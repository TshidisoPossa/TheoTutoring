import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// Fill these in from your Cloudinary dashboard (free tier — no card needed).
const String _cloudName = 'ejckimby';
const String _uploadPreset = 'theo_unsigned';

/// Uploads [file] to Cloudinary using an unsigned preset and returns the
/// resulting secure image URL. Store this URL string in MySQL, not the file.
///
/// Reads the file as bytes so it works on web as well as desktop and mobile.
Future<String> uploadToCloudinary(XFile file) async {
  final uri = Uri.parse(
    'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
  );

  final request = http.MultipartRequest('POST', uri)
    ..fields['upload_preset'] = _uploadPreset
    ..files.add(
      http.MultipartFile.fromBytes(
        'file',
        await file.readAsBytes(),
        filename: file.name,
      ),
    );

  final response = await request.send();
  final body = await response.stream.bytesToString();

  if (response.statusCode != 200) {
    throw Exception('Cloudinary upload failed: $body');
  }

  final match = RegExp(r'"secure_url":"([^"]+)"').firstMatch(body);
  if (match == null) {
    throw Exception('Could not parse Cloudinary response: $body');
  }
  return match.group(1)!.replaceAll(r'\/', '/');
}
