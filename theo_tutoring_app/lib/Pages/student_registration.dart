import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StudentRegistrationPage extends StatefulWidget {
  const StudentRegistrationPage({super.key});

  @override
  State<StudentRegistrationPage> createState() =>
      _StudentRegistrationPageState();
}

class _StudentRegistrationPageState
    extends State<StudentRegistrationPage> {
bool isPasswordVisible = false;
bool isConfirmPasswordVisible = false;
bool termsAccepted = false;

final fullNameController = TextEditingController();
final emailController = TextEditingController();
final passwordController = TextEditingController();
final confirmPasswordController = TextEditingController();
final phoneController = TextEditingController();
final addressController = TextEditingController();
final courseController = TextEditingController();
final tutoringModuleController = TextEditingController();

String? selectedYear;
Future<UserCredential> _createFirebaseAccount() async {
  return await FirebaseAuth.instance.createUserWithEmailAndPassword(
    email: emailController.text.trim(),
    password: passwordController.text,
  );
}

Future<void> _registerStudent(String firebaseUid) async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    throw Exception('No authenticated Firebase user found.');
  }

  final idToken = await user.getIdToken();

  if (idToken == null || idToken.isEmpty) {
    throw Exception('Could not obtain Firebase ID token.');
  }

  final response = await http.post(
    Uri.parse('http://localhost:8080/auth/student/register'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
    },
    body: jsonEncode({
      'firebaseUid': firebaseUid,
      'fullName': fullNameController.text.trim(),
      'email': emailController.text.trim(),
      'password': passwordController.text,
      'confirmPassword': confirmPasswordController.text,
      'phone': phoneController.text.trim(),
      'address': addressController.text.trim(),
      'institutionYear': selectedYear!.replaceAll('Year ', ''),
      'course': courseController.text.trim(),
      'tutoringModule': tutoringModuleController.text.trim(),
      'termsAccepted': termsAccepted,
    }),
  );

  if (response.statusCode != 201) {
    throw Exception('Registration failed: ${response.body}');
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
     appBar: AppBar(
  title: Row(
    children: [
      const Icon(
        Icons.school,
        size: 28,
      ),
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
              child: Stack(
                children: [
                  const CircleAvatar(
                    radius: 55,
                    backgroundColor: Colors.blue,
                    child: Icon(
                      Icons.person,
                      size: 60,
                      color: Colors.white,
                    ),
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
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
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
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
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
                        // Password
            const Text(
              'Password',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
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
                    isPasswordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
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
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
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
                      isConfirmPasswordVisible =
                          !isConfirmPasswordVisible;
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Phone Number
            const Text(
              'Phone Number',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
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
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
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

            // Institution Year
            const Text(
              'Institution Year',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
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
                DropdownMenuItem(
                  value: 'Year 1',
                  child: Text('Year 1'),
                ),
                DropdownMenuItem(
                  value: 'Year 2',
                  child: Text('Year 2'),
                ),
                DropdownMenuItem(
                  value: 'Year 3',
                  child: Text('Year 3'),
                ),
                DropdownMenuItem(
                  value: 'Year 4',
                  child: Text('Year 4'),
                ),
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
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  // File upload will be added later.
                },
                icon: const Icon(
                  Icons.upload_file,
                  color: Colors.blue,
                ),
                label: const Text(
                  'Upload Proof of Registration',
                  style: TextStyle(
                    color: Colors.blue,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                    color: Colors.blue,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 15,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Course of Study
            const Text(
              'Course of Study',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
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
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
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
                          const TextSpan(
                            text: 'I agree to the ',
                          ),
                          TextSpan(
                            text: 'Terms of Service',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const TextSpan(
                            text: ' and ',
                          ),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const TextSpan(
                            text: '.',
                          ),
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
                onPressed: termsAccepted
    ? () async {
        if (fullNameController.text.isEmpty ||
            emailController.text.isEmpty ||
            passwordController.text.isEmpty ||
            confirmPasswordController.text.isEmpty ||
            phoneController.text.isEmpty ||
            addressController.text.isEmpty ||
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

        if (passwordController.text !=
            confirmPasswordController.text) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Passwords do not match.',
              ),
            ),
          );
          return;
        }

        try {
          final userCredential = await _createFirebaseAccount();

        final firebaseUser = userCredential.user;

        if (firebaseUser == null) {
      throw Exception('Could not get Firebase user.');
    }

        try {
            await _registerStudent(firebaseUser.uid);
        } catch (e) {
            await firebaseUser.delete();
           rethrow;
}

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Registration successful!',
              ),
            ),
          );
        } on FirebaseAuthException catch (e) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e.message ?? 'Firebase registration failed.',
              ),
            ),
          );
        } catch (e) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Registration failed: $e',
              ),
            ),
          );
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
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
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