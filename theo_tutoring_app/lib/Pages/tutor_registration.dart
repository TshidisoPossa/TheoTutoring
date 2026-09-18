import 'package:flutter/material.dart'; // This is to enable design widgets
import 'package:image_picker/image_picker.dart';

import 'cloudinary_upload.dart';

import 'dart:io';

class TutorRegistration extends StatefulWidget {
  const TutorRegistration({super.key});

  @override
  State<TutorRegistration> createState() => _TutorRegistrationState(); // ← returns the State class, not itself
}

class _TutorRegistrationState extends State<TutorRegistration> {
  File? _profileImage;
  String? _profileImageUrl; // set after Cloudinary upload succeeds
  bool _uploadingImage = false;

  final List<String> _allSubjects = [
    'Mathematics',
    'Physics',
    'Chemistry',
    'Biology',
    'English Lit',
    'Computer Science',
  ];
  final Set<String> _selectedSubjects = {};

  final _qualificationsController = TextEditingController();
  final _bioController = TextEditingController();
  String? _experience;

  Future<void> _pickProfilePicture() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 80,
    );
    if (picked == null) return;

    final file = File(picked.path);
    setState(() {
      _profileImage = file;
      _uploadingImage = true;
    });

    try {
      final url = await uploadToCloudinary(file);
      setState(() => _profileImageUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Photo upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  void _toggleSubject(String subject) {
    setState(() {
      if (_selectedSubjects.contains(subject)) {
        _selectedSubjects.remove(subject);
      } else {
        _selectedSubjects.add(subject);
      }
    });
  }

  @override
  void dispose() {
    _qualificationsController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  //building the actual UI that gets drawn on screen
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TheoTutoring')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinearProgressIndicator(value: 2 / 3),
              const SizedBox(height: 4),
              const Text('Step 2 of 3'),
              const SizedBox(height: 12),
              const Text(
                'What do you teach?',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tell students about your expertise and what makes you a great tutor.',
              ),
              const SizedBox(height: 20),

              // Profile photo picker
              const Text(
                'Upload Profile Photo',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 45,
                      backgroundColor: Colors.blue.shade50,
                      backgroundImage: _profileImage != null
                          ? FileImage(_profileImage!)
                          : null,
                      child: _uploadingImage
                          ? const CircularProgressIndicator()
                          : (_profileImage == null
                                ? Icon(
                                    Icons.camera_alt,
                                    color: Colors.blue.shade300,
                                    size: 28,
                                  )
                                : null),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: _pickProfilePicture,
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.blue,
                          child: const Icon(
                            Icons.edit,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Subjects — tappable, multi-select chips
              const Text(
                'Subjects You Teach',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final subject in _allSubjects)
                    FilterChip(
                      label: Text(subject),
                      selected: _selectedSubjects.contains(subject),
                      onSelected: (_) => _toggleSubject(subject),
                      selectedColor: Colors.blue.shade100,
                      checkmarkColor: Colors.blue,
                    ),
                  ActionChip(
                    label: const Icon(Icons.add, size: 18),
                    onPressed: () {
                      // TODO: open a dialog to add a subject not in the fixed list,
                      // or hide this entirely if subjects stay admin-managed only.
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Qualifications
              const Text(
                'Qualifications',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _qualificationsController,
                decoration: const InputDecoration(
                  hintText: 'e.g. BSc Mathematics, University of London',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.school_outlined),
                ),
              ),
              const SizedBox(height: 20),

              // Certificate upload (unchanged — already handled elsewhere)
              // ... keep your existing "Upload Certificate" widget here ...
              const SizedBox(height: 20),

              // Experience — hourly rate removed; tutors don't set their own price
              const Text(
                'Experience',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _experience,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: '<1 year', child: Text('<1 year')),
                  DropdownMenuItem(
                    value: '1-3 years',
                    child: Text('1-3 years'),
                  ),
                  DropdownMenuItem(
                    value: '3-5 years',
                    child: Text('3-5 years'),
                  ),
                  DropdownMenuItem(value: '5+ years', child: Text('5+ years')),
                ],
                onChanged: (v) => setState(() => _experience = v),
              ),
              const SizedBox(height: 20),

              const Text(
                'Short Bio',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _bioController,
                maxLength: 300,
                maxLines: 4,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // TODO: bundle _selectedSubjects, _profileImageUrl,
                    // _qualificationsController.text, _experience, _bioController.text
                    // and POST to the Dart Frog API.
                  },
                  child: const Text('Continue →'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
