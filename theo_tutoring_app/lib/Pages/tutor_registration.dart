import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/api.dart';
import 'cloudinary_upload.dart';
import 'tutor_availability.dart';

class TutorRegistration extends StatefulWidget {
  const TutorRegistration({
    super.key,
    required this.fullName,
    required this.email,
    required this.password,
    required this.phoneNumber,
  });

  final String fullName;
  final String email;
  final String password;
  final String phoneNumber;

  @override
  State<TutorRegistration> createState() => _TutorRegistrationState();
}

class _TutorRegistrationState extends State<TutorRegistration> {
  static const _experienceOptions = <(String, String)>[
    ('0-1', 'Less than 1 year'),
    ('1-2', '1–2 years'),
    ('3-5', '3–5 years'),
    ('5+', '5+ years'),
  ];

  final _formKey = GlobalKey<FormState>();
  final _bioController = TextEditingController();
  final _qualifications = <_QualificationFields>[_QualificationFields()];
  final _selectedSubjectIds = <int>{};

  List<_TutorSubject> _subjects = [];
  String? _experience;
  String? _subjectsError;
  String? _profilePhotoUrl;
  Uint8List? _profilePhotoBytes;
  String? _certificateUrl;
  String? _certificateName;
  bool _loadingSubjects = true;
  bool _uploadingPhoto = false;
  bool _uploadingCertificate = false;
  bool _isSubmitting = false;
  bool _showValidation = false;
  bool _stepOneCompleted = false;
  User? _firebaseUser;
  String? _registrationPassword;

  @override
  void initState() {
    super.initState();
    _registrationPassword = widget.password;
    unawaited(_loadSubjects());
  }

  @override
  void dispose() {
    _bioController.dispose();
    for (final fields in _qualifications) {
      fields.dispose();
    }
    _registrationPassword = null;
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    setState(() {
      _loadingSubjects = true;
      _subjectsError = null;
    });
    try {
      final response = await http
          .get(
            Uri.parse('$apiBaseUrl/subjects'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 ||
          decoded is! Map<String, dynamic> ||
          decoded['subjects'] is! List) {
        throw const FormatException('Invalid subject response.');
      }

      final subjects = <_TutorSubject>[];
      for (final item in decoded['subjects'] as List) {
        if (item is! Map<String, dynamic> ||
            item['subjectId'] is! int ||
            item['subjectName'] is! String ||
            (item['subjectName'] as String).trim().isEmpty) {
          throw const FormatException('Invalid subject entry.');
        }
        subjects.add(
          _TutorSubject(
            id: item['subjectId'] as int,
            name: (item['subjectName'] as String).trim(),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _subjects = subjects;
        _subjectsError = subjects.isEmpty
            ? 'No subjects are available yet. Please try again later.'
            : null;
      });
    } on Exception {
      if (mounted) {
        setState(() {
          _subjectsError =
              'Could not load subjects. Check your connection and retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _loadingSubjects = false);
    }
  }

  Future<void> _pickProfilePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _profilePhotoBytes = null;
      _profilePhotoUrl = null;
      _uploadingPhoto = true;
    });
    try {
      final bytes = await picked.readAsBytes();
      final url = await uploadToCloudinary(picked);
      if (mounted) {
        setState(() {
          _profilePhotoBytes = bytes;
          _profilePhotoUrl = url;
        });
      }
    } on Exception {
      if (mounted) {
        _showMessage('Profile photo upload failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _pickCertificate() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 95,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _certificateUrl = null;
      _certificateName = picked.name;
      _uploadingCertificate = true;
    });
    try {
      final url = await uploadToCloudinary(picked);
      if (!_isCloudinaryImageUrl(url)) {
        throw const FormatException(
          'The uploaded item is not a certificate image.',
        );
      }
      if (mounted) setState(() => _certificateUrl = url);
    } on Exception {
      if (mounted) {
        setState(() => _certificateName = null);
        _showMessage(
          'Certificate upload failed. Choose a JPG or PNG scan and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingCertificate = false);
    }
  }

  bool _isCloudinaryImageUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'res.cloudinary.com' ||
        uri.pathSegments.length < 2) {
      return false;
    }
    final file = uri.pathSegments.last.toLowerCase();
    return file.endsWith('.jpg') ||
        file.endsWith('.jpeg') ||
        file.endsWith('.png');
  }

  String? _validateBio(String? value) {
    final bio = value?.trim() ?? '';
    if (bio.length < 20) return 'Bio must be at least 20 characters.';
    if (bio.length > 300) return 'Bio must be 300 characters or fewer.';
    return null;
  }

  String? _validateQualification(String? value, String label) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label is required.';
    if (text.length > 100) return '$label must be 100 characters or fewer.';
    return null;
  }

  Future<String> _getFreshToken(User user) async {
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw const _TutorRequestFailure(
        'Could not verify your account. Please try again.',
      );
    }
    return token;
  }

  Future<void> _submitProfile() async {
    if (_isSubmitting) return;
    setState(() => _showValidation = true);

    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid ||
        _experience == null ||
        _selectedSubjectIds.isEmpty ||
        _certificateUrl == null ||
        _loadingSubjects ||
        _uploadingCertificate ||
        _uploadingPhoto) {
      _showMessage(
        _subjectsError != null
            ? _subjectsError!
            : _selectedSubjectIds.isEmpty
            ? 'Select at least one subject.'
            : _certificateUrl == null
            ? 'Upload your certificate scan before continuing.'
            : 'Complete all highlighted fields before continuing.',
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      var user = _firebaseUser;
      if (user == null) {
        final password = _registrationPassword;
        if (password == null) {
          throw const _TutorRequestFailure(
            'The registration session expired. Sign in or restart registration.',
          );
        }
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: widget.email.trim(),
              password: password,
            );
        user = credential.user;
        if (user == null) {
          throw const _TutorRequestFailure(
            'Could not create your Firebase account.',
          );
        }
        _firebaseUser = user;
        _registrationPassword = null;
      }

      final token = await _getFreshToken(user);
      if (!_stepOneCompleted) {
        final accountResponse = await http
            .post(
              Uri.parse('$apiBaseUrl/auth/tutor/register'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({
                'name': widget.fullName,
                'phoneNum': widget.phoneNumber,
              }),
            )
            .timeout(const Duration(seconds: 20));

        if (accountResponse.statusCode == 201) {
          final accountBody = _decodeBody(accountResponse);
          if (accountBody['userId'] is! int || accountBody['tutorId'] is! int) {
            throw const _TutorRequestFailure(
              'The server response was incomplete. Retry to safely resume registration.',
            );
          }
          _stepOneCompleted = true;
        } else if (accountResponse.statusCode != 409) {
          throw _TutorRequestFailure(
            _responseError(accountResponse, _decodeBody(accountResponse)),
          );
        }
        // 409 can mean a previous timed-out request created this same account.
        // The profile endpoint verifies the Firebase UID before any update.
      }

      final profileResponse = await http
          .post(
            Uri.parse('$apiBaseUrl/auth/tutor/profile'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'bio': _bioController.text.trim(),
              'experience': _experience,
              'certificateUrl': _certificateUrl,
              'profilePhotoUrl': _profilePhotoUrl,
              'subjectIds': _selectedSubjectIds.toList()..sort(),
              'qualifications': [
                for (final fields in _qualifications)
                  {
                    'degree': fields.degree.text.trim(),
                    'institution': fields.institution.text.trim(),
                  },
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));

      final profileBody = _decodeBody(profileResponse);
      if (profileResponse.statusCode != 200 || profileBody['tutorId'] is! int) {
        final message = _responseError(profileResponse, profileBody);
        if (profileResponse.statusCode == 404) {
          throw _TutorRequestFailure(
            'Your Firebase account exists, but the backend could not match it '
            'to a tutor record. Do not register again; contact support. $message',
          );
        }
        throw _TutorRequestFailure(message);
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TutorAvailabilityPage(firebaseUser: user!),
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final message = error.code == 'email-already-in-use'
          ? 'An account already exists for this email. No duplicate was created; sign in or contact support to resume tutor registration.'
          : error.message ?? 'Firebase account creation failed.';
      _showMessage(message);
    } on _TutorRequestFailure catch (error) {
      if (mounted) _showMessage(error.message);
    } on Exception {
      if (mounted) {
        _showMessage(
          _firebaseUser == null
              ? 'Account creation could not be confirmed. Retry, and check your email for an existing account.'
              : 'The server did not confirm this step. Your Firebase account is retained; retry here to resume without creating another account.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Fall back to the HTTP status message.
    }
    return {};
  }

  String _responseError(http.Response response, Map<String, dynamic> body) {
    final error = body['error'];
    if (error is String && error.trim().isNotEmpty) return error;
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is String && first.trim().isNotEmpty) return first;
    }
    return 'The server rejected registration (HTTP ${response.statusCode}).';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        title: const Text('TheoTutoring'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Form(
                key: _formKey,
                autovalidateMode: _showValidation
                    ? AutovalidateMode.onUserInteraction
                    : AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LinearProgressIndicator(value: 2 / 3),
                    const SizedBox(height: 4),
                    const Text('STEP 2 OF 3'),
                    const SizedBox(height: 12),
                    const Text(
                      'What do you teach?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Tell students about your expertise and what makes you a great tutor.',
                    ),
                    const SizedBox(height: 20),
                    _buildProfilePhoto(),
                    const SizedBox(height: 22),
                    const Text(
                      'Subjects You Teach',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (_loadingSubjects)
                      const Center(child: CircularProgressIndicator())
                    else if (_subjectsError != null)
                      Row(
                        children: [
                          Expanded(child: Text(_subjectsError!)),
                          TextButton(
                            onPressed: _loadSubjects,
                            child: const Text('Retry'),
                          ),
                        ],
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final subject in _subjects)
                            FilterChip(
                              label: Text(subject.name),
                              selected: _selectedSubjectIds.contains(
                                subject.id,
                              ),
                              onSelected: (selected) => setState(() {
                                if (selected) {
                                  _selectedSubjectIds.add(subject.id);
                                } else {
                                  _selectedSubjectIds.remove(subject.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    if (_showValidation && _selectedSubjectIds.isEmpty)
                      _fieldError('Select at least one subject.'),
                    const SizedBox(height: 20),
                    const Text(
                      'Qualifications',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    for (var index = 0; index < _qualifications.length; index++)
                      _buildQualification(index),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _qualifications.length >= 10
                            ? null
                            : () => setState(
                                () =>
                                    _qualifications.add(_QualificationFields()),
                              ),
                        icon: const Icon(Icons.add),
                        label: const Text('Add qualification'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Certificate',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Choose a clear certificate scan or photo (JPG/PNG).',
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _uploadingCertificate || _isSubmitting
                          ? null
                          : _pickCertificate,
                      icon: _uploadingCertificate
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file),
                      label: Text(
                        _uploadingCertificate
                            ? 'Uploading certificate…'
                            : _certificateUrl == null
                            ? 'Upload certificate'
                            : 'Certificate uploaded: ${_certificateName ?? 'scan'}',
                      ),
                    ),
                    if (_showValidation && _certificateUrl == null)
                      _fieldError('Upload your certificate scan.'),
                    const SizedBox(height: 20),
                    const Text(
                      'Experience',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _experience,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null ? 'Select your experience.' : null,
                      items: [
                        for (final option in _experienceOptions)
                          DropdownMenuItem(
                            value: option.$1,
                            child: Text(option.$2),
                          ),
                      ],
                      onChanged: (value) => setState(() => _experience = value),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Short Bio',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _bioController,
                      maxLength: 300,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Tell students about your teaching approach.',
                      ),
                      validator: _validateBio,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          disabledBackgroundColor: Colors.grey.shade300,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          _isSubmitting
                              ? 'Submitting…'
                              : 'Continue to availability →',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfilePhoto() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upload Profile Photo (optional)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            CircleAvatar(
              radius: 42,
              backgroundColor: Colors.blue.shade50,
              backgroundImage: _profilePhotoBytes == null
                  ? null
                  : MemoryImage(_profilePhotoBytes!),
              child: _uploadingPhoto
                  ? const CircularProgressIndicator()
                  : _profilePhotoBytes == null
                  ? Icon(Icons.camera_alt, color: Colors.blue.shade300)
                  : null,
            ),
            const SizedBox(width: 14),
            OutlinedButton.icon(
              onPressed: _uploadingPhoto || _isSubmitting
                  ? null
                  : _pickProfilePhoto,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(_uploadingPhoto ? 'Uploading…' : 'Choose photo'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQualification(int index) {
    final fields = _qualifications[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          TextFormField(
            controller: fields.degree,
            maxLength: 100,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Degree or qualification',
              hintText: 'e.g. BSc Mathematics',
              border: const OutlineInputBorder(),
              counterText: '',
              suffixIcon: _qualifications.length > 1
                  ? IconButton(
                      tooltip: 'Remove qualification',
                      onPressed: () => _removeQualification(index),
                      icon: const Icon(Icons.delete_outline),
                    )
                  : null,
            ),
            validator: (value) =>
                _validateQualification(value, 'Qualification'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: fields.institution,
            maxLength: 100,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Institution',
              hintText: 'e.g. University of Pretoria',
              border: OutlineInputBorder(),
              counterText: '',
            ),
            validator: (value) => _validateQualification(value, 'Institution'),
          ),
        ],
      ),
    );
  }

  void _removeQualification(int index) {
    setState(() => _qualifications.removeAt(index).dispose());
  }

  Widget _fieldError(String message) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

class _TutorSubject {
  const _TutorSubject({required this.id, required this.name});

  final int id;
  final String name;
}

class _QualificationFields {
  final degree = TextEditingController();
  final institution = TextEditingController();

  void dispose() {
    degree.dispose();
    institution.dispose();
  }
}

class _TutorRequestFailure implements Exception {
  const _TutorRequestFailure(this.message);
  final String message;
}
