import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/api.dart';
import 'Student/student_dashboard.dart';
import 'Tutor/tutor_api.dart';
import 'Tutor/tutor_dashboard.dart';
import 'role_selection.dart';
import 'forgot_password.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // ============================================================
  // FIREBASE WIRING — logic only
  // ============================================================

  // Form validation key — teammate wraps their fields in a Form
  // widget using this same key
  final _formKey = GlobalKey<FormState>();

  // Controllers — teammate attaches these to their email/password
  // TextFormFields so this logic can read what the user typed
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // State flags — teammate wires these into their UI:
  // _obscurePassword -> controls a show/hide password icon
  // _isLoading       -> disables the button / shows a spinner
  // _errorMessage    -> displayed as error text if not null
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Call this from the teammate's "Log In" button onPressed
  Future<void> _login() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final user = credential.user;
      if (user == null) {
        if (mounted) {
          setState(() => _errorMessage = 'Login failed. Please try again.');
        }
        return;
      }

      final String? idToken;
      try {
        idToken = await user.getIdToken();
      } on Exception {
        if (mounted) {
          setState(() {
            _errorMessage =
                'Could not verify your account. Please sign in again.';
          });
        }
        return;
      }

      if (idToken == null || idToken.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage =
                'Could not verify your account. Please sign in again.';
          });
        }
        return;
      }

      final http.Response response;
      try {
        response = await http
            .get(
              Uri.parse('$apiBaseUrl/StudentlandingPage/myprofile'),
              headers: {
                'Authorization': 'Bearer $idToken',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 15));
      } on Exception {
        if (mounted) {
          setState(() {
            _errorMessage =
                'Could not connect to the server. Please try again.';
          });
        }
        return;
      }

      // No student profile: this may be a tutor account
      if (response.statusCode == 404) {
        await _openTutorDashboard(idToken);
        return;
      }

      if (response.statusCode != 200) {
        if (mounted) {
          setState(() {
            _errorMessage = switch (response.statusCode) {
              401 =>
                'Your session could not be verified. Please sign in again.',
              404 => 'No student profile was found for this account.',
              _ =>
                'We could not verify your student profile. Please try again.',
            };
          });
        }
        return;
      }

      final dynamic profile;
      try {
        profile = jsonDecode(response.body);
      } on FormatException {
        if (mounted) {
          setState(() {
            _errorMessage =
                'The server returned an invalid response. Please try again.';
          });
        }
        return;
      }

      if (profile is! Map<String, dynamic> ||
          profile['userId'] is! int ||
          profile['studentId'] is! int ||
          profile['name'] is! String ||
          (profile['name'] as String).trim().isEmpty ||
          profile['email'] is! String ||
          (profile['email'] as String).trim().isEmpty ||
          profile['role'] is! String ||
          profile['accountStatus'] is! String ||
          (profile['accountStatus'] as String).trim().isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = 'The server returned an invalid student profile. Please try again.';
          });
        }
        return;
      }

      if (profile['role'] != 'student') {
        if (mounted) {
          setState(() {
            _errorMessage = 'This account is not registered as a student.';
          });
        }
        return;
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => StudentDashboard(
              studentName: (profile['name'] as String).trim(),
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message ?? 'Login failed. Please try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Login failed. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Loads the tutor dashboard; opens it if this account is a tutor
  Future<void> _openTutorDashboard(String idToken) async {
    try {
      final dashboard = await fetchTutorDashboard(idToken: idToken);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TutorDashboard(initialData: dashboard),
        ),
      );
    } on TutorApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = switch (e.statusCode) {
          403 || 404 =>
            'No active student or tutor profile was found for this account.',
          _ => e.message,
        };
      });
    }
  }

  // ============================================================
  // UI — intentionally left empty. Teammate builds the full
  // Figma-matched layout here, using the controllers, _formKey,
  // _login(), _obscurePassword, _isLoading, and _errorMessage above.
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 30),

                // TheoTutoring logo
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.blue.shade100,
                  child: const Icon(Icons.school, size: 55, color: Colors.blue),
                ),

                const SizedBox(height: 20),

                // Welcome message
                const Text(
                  'Welcome Back!',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 35),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Email Address',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 8),

                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'Enter your email address',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email address';
                    }

                    if (!value.contains('@')) {
                      return 'Please enter a valid email address';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Password',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 8),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ForgotPasswordPage(),
                        ),
                      );
                    },
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(color: Colors.blue, fontSize: 14),
                    ),
                  ),
                ),

                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Log In',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                // Error message
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),

                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Don't have an account? ",
                      style: TextStyle(fontSize: 14),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RoleSelectionPage(),
                          ),
                        );
                        // Sign up navigation will be added later
                      },
                      child: const Text(
                        'Sign up',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 35),
                const Divider(),

                const SizedBox(height: 15),

                const Text(
                  '© TheoTutoring',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),

                const SizedBox(height: 8),

                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () {
                        // Privacy Policy will be added later
                      },
                      child: const Text(
                        'Privacy Policy',
                        style: TextStyle(color: Colors.blue, fontSize: 13),
                      ),
                    ),

                    const Text('|', style: TextStyle(color: Colors.grey)),

                    TextButton(
                      onPressed: () {
                        // Terms of Service will be added later
                      },
                      child: const Text(
                        'Terms of Service',
                        style: TextStyle(color: Colors.blue, fontSize: 13),
                      ),
                    ),

                    const Text('|', style: TextStyle(color: Colors.grey)),

                    TextButton(
                      onPressed: () {
                        // Help Center will be added later
                      },
                      child: const Text(
                        'Help Center',
                        style: TextStyle(color: Colors.blue, fontSize: 13),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
