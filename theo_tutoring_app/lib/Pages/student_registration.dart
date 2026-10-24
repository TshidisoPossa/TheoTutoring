import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/api.dart';
import 'cloudinary_upload.dart';
import 'privacy_policy.dart';
import 'terms_and_conditions.dart';

class _SafeRegistrationFailure implements Exception {
  const _SafeRegistrationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class _RegistrationOutcomeUnknown implements Exception {
  const _RegistrationOutcomeUnknown(this.message);

  final String message;

  @override
  String toString() => message;
}

class StudentRegistrationPage extends StatefulWidget {
  const StudentRegistrationPage({super.key});

  @override
  State<StudentRegistrationPage> createState() =>
      _StudentRegistrationPageState();
}

class _StudentRegistrationPageState extends State<StudentRegistrationPage> {
  bool isPasswordVisible = false;
  bool isConfirmPasswordVisible = false;
  bool termsAccepted = false;
  bool _isSubmitting = false;

  final fullNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  final institutionController = TextEditingController();
  final courseController = TextEditingController();
  final tutoringModuleController = TextEditingController();

  String? selectedYear;

  XFile? _proofFile;
  String? _proofUrl; // set after Cloudinary upload succeeds
  bool _uploadingProof = false;

  Uint8List? _photoBytes;
  String? _photoUrl;
  bool _uploadingPhoto = false;

  Future<void> _pickProfilePhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _photoUrl = null;
        _uploadingPhoto = true;
      });

      final url = await uploadToCloudinary(picked);
      if (mounted) setState(() => _photoUrl = url);
    } catch (e) {
      if (mounted) {
        setState(() {
          _photoBytes = null;
          _photoUrl = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile photo upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _pickProofOfRegistration() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() {
      _proofFile = picked;
      _proofUrl = null;
      _uploadingProof = true;
    });

    try {
      final url = await uploadToCloudinary(picked);
      setState(() => _proofUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Proof of registration upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingProof = false);
    }
  }

  Future<UserCredential> _createFirebaseAccount() async {
    return await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: emailController.text.trim(),
      password: passwordController.text,
    );
  }

  Future<void> _registerStudent(User firebaseUser) async {
    // The backend identifies the student from this Firebase ID token.
    late final String? idToken;
    try {
      idToken = await firebaseUser.getIdToken();
    } on Exception {
      throw const _SafeRegistrationFailure(
        'Could not obtain a Firebase ID token. Please try again.',
      );
    }
    if (idToken == null || idToken.isEmpty) {
      throw const _SafeRegistrationFailure(
        'Could not obtain a Firebase ID token. Please try again.',
      );
    }

    late final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$apiBaseUrl/students/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'fullName': fullNameController.text.trim(),
          'email': emailController.text.trim(),
          'phone': phoneController.text.trim(),
          'address': addressController.text.trim(),
          'institution': institutionController.text.trim(),
          'institutionYear': selectedYear!.replaceAll('Year ', ''),
          'course': courseController.text.trim(),
          'tutoringModule': tutoringModuleController.text.trim(),
          'profilePhotoUrl': _photoUrl,
          'proofOfRegistrationUrl': _proofUrl,
          'termsAccepted': termsAccepted,
        }),
      );
    } on Exception {
      throw const _RegistrationOutcomeUnknown(
        'The server did not confirm registration. Your Firebase account was '
        'kept because the request may have completed. Try signing in before '
        'retrying.',
      );
    }

    if (response.statusCode != 201) {
      final message = _registrationResponseMessage(response);
      if (response.statusCode >= 500 ||
          (response.statusCode >= 200 && response.statusCode < 300)) {
        throw _RegistrationOutcomeUnknown(
          '$message Your Firebase account was kept because the request may '
          'have completed. Try signing in before retrying.',
        );
      }
      throw _SafeRegistrationFailure(message);
    }
  }

  String _registrationResponseMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        final error = body['error'];
        if (error is String && error.trim().isNotEmpty) return error;

        final errors = body['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final firstError = errors.values.first;
          if (firstError is String) return firstError;
        }
      }
    } on FormatException {
      // Use the status-based message below when the response is not JSON.
    }
    return 'The server rejected registration (HTTP ${response.statusCode}).';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.school, size: 28),
            const SizedBox(width: 10),
            const Text('TheoTutoring'),
          ],
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile photo
            Center(
              child: GestureDetector(
                onTap: _uploadingPhoto ? null : _pickProfilePhoto,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 55,
                      backgroundColor: Colors.blue,
                      backgroundImage: _photoBytes == null
                          ? null
                          : MemoryImage(_photoBytes!),
                      child: _uploadingPhoto
                          ? const CircularProgressIndicator(color: Colors.white)
                          : _photoBytes == null
                          ? const Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            Center(
              child: Text(
                _uploadingPhoto
                    ? 'Uploading photo...'
                    : _photoUrl != null
                    ? 'Tap the photo to change it'
                    : 'Tap to add a profile photo (optional)',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),

            const SizedBox(height: 25),

            const Text(
              'Student Registration',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),

            const SizedBox(height: 25),

            // Full Name
            const Text(
              'Full Name',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: fullNameController,
              decoration: InputDecoration(
                hintText: 'Enter your full name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Email
            const Text(
              'Email',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'Enter your email address',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 20),
            // Password
            const Text(
              'Password',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: passwordController,
              obscureText: !isPasswordVisible,
              decoration: InputDecoration(
                hintText: 'Enter your password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      isPasswordVisible = !isPasswordVisible;
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Confirm Password
            const Text(
              'Confirm Password',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: confirmPasswordController,
              obscureText: !isConfirmPasswordVisible,
              decoration: InputDecoration(
                hintText: 'Confirm your password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    isConfirmPasswordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      isConfirmPasswordVisible = !isConfirmPasswordVisible;
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Phone Number
            const Text(
              'Phone Number',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            TextField(
              keyboardType: TextInputType.phone,
              controller: phoneController,
              decoration: InputDecoration(
                hintText: 'Enter your phone number',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Address
            const Text(
              'Address',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            TextField(
              maxLines: 2,
              controller: addressController,
              decoration: InputDecoration(
                hintText: 'Enter your address',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // University (shown to tutors on the booking details page)
            const Text(
              'University',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: institutionController,
              textCapitalization: TextCapitalization.words,
              maxLength: 150,
              decoration: InputDecoration(
                hintText: 'e.g. University of Johannesburg',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Institution Year
            const Text(
              'Institution Year',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                hintText: 'Select your current year',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'Year 1', child: Text('Year 1')),
                DropdownMenuItem(value: 'Year 2', child: Text('Year 2')),
                DropdownMenuItem(value: 'Year 3', child: Text('Year 3')),
                DropdownMenuItem(value: 'Year 4', child: Text('Year 4')),
              ],
              onChanged: (value) {
                setState(() {
                  selectedYear = value;
                });
              },
            ),

            const SizedBox(height: 20),
            // Proof of Registration
            const Text(
              'Proof of Registration',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _uploadingProof ? null : _pickProofOfRegistration,
                icon: _uploadingProof
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _proofUrl != null
                            ? Icons.check_circle
                            : Icons.upload_file,
                        color: _proofUrl != null ? Colors.green : Colors.blue,
                      ),
                label: Text(
                  _uploadingProof
                      ? 'Uploading...'
                      : _proofUrl != null
                      ? 'Uploaded: ${_proofFile!.name}'
                      : 'Upload Proof of Registration',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _proofUrl != null ? Colors.green : Colors.blue,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.blue),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Course of Study
            const Text(
              'Course of Study',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: courseController,
              decoration: InputDecoration(
                hintText: 'Enter your course of study',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Tutoring Module
            const Text(
              'Tutoring Module',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 8),

            TextField(
              maxLines: 4,
              controller: tutoringModuleController,
              decoration: InputDecoration(
                hintText: 'Enter the module you need tutoring support with',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Terms and Conditions
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: termsAccepted,
                  activeColor: Colors.blue,
                  onChanged: (value) {
                    setState(() {
                      termsAccepted = value ?? false;
                    });
                  },
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                        children: [
                          const TextSpan(text: 'I agree to the '),
                                                    WidgetSpan(
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const TermsAndConditionsPage(),
                                ),
                              ),
                              child: const Text(
                                'Terms of Service',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          const TextSpan(text: ' and '),
                          WidgetSpan(
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PrivacyPolicyPage(),
                                ),
                              ),
                              child: const Text(
                                'Privacy Policy',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Create Account
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: termsAccepted && !_isSubmitting
                    ? () async {
                        if (_isSubmitting) return;

                        if (fullNameController.text.isEmpty ||
                            emailController.text.isEmpty ||
                            passwordController.text.isEmpty ||
                            confirmPasswordController.text.isEmpty ||
                            phoneController.text.isEmpty ||
                            addressController.text.isEmpty ||
                            institutionController.text.trim().isEmpty ||
                            selectedYear == null ||
                            courseController.text.isEmpty ||
                            tutoringModuleController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please complete all required fields.',
                              ),
                            ),
                          );
                          return;
                        }

                        if (_uploadingProof || _proofUrl == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _uploadingProof
                                    ? 'Please wait for your proof of registration to finish uploading.'
                                    : 'Please upload your proof of registration.',
                              ),
                            ),
                          );
                          return;
                        }

                        if (_uploadingPhoto) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please wait for your profile photo to finish uploading.',
                              ),
                            ),
                          );
                          return;
                        }

                        if (passwordController.text !=
                            confirmPasswordController.text) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Passwords do not match.'),
                            ),
                          );
                          return;
                        }

                        setState(() => _isSubmitting = true);
                        try {
                          final userCredential = await _createFirebaseAccount();

                          final firebaseUser = userCredential.user;

                          if (firebaseUser == null) {
                            throw Exception('Could not get Firebase user.');
                          }

                          try {
                            await _registerStudent(firebaseUser);
                          } on _SafeRegistrationFailure catch (error) {
                            try {
                              await firebaseUser.delete();
                            } on FirebaseAuthException catch (cleanupError) {
                              throw Exception(
                                '${error.message} Firebase account cleanup failed: '
                                '${cleanupError.message ?? 'Please contact support.'}',
                              );
                            }
                            rethrow;
                          }

                          // Creating the account signs the user in; sign out so they log in
                          // themselves on the login page.
                          await FirebaseAuth.instance.signOut();

                          if (!context.mounted) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Registration successful! Please log in.',
                              ),
                            ),
                          );

                          // Back to the LoginPage (the first route), closing role selection
                          // and this registration page.
                          Navigator.of(context)
                              .popUntil((route) => route.isFirst);
                        } on FirebaseAuthException catch (e) {
                          if (!context.mounted) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e.message ?? 'Firebase registration failed.',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Registration failed: $e')),
                          );
                        } finally {
                          if (mounted) setState(() => _isSubmitting = false);
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  disabledBackgroundColor: Colors.grey.shade300,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.grey.shade600,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Create Account',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
