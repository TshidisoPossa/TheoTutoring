import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // ============================================================
  // FIREBASE WIRING — logic only, no UI
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
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // TODO: navigate to Student or Tutor dashboard based on role
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'Login failed. Please try again.';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // UI — intentionally left empty. Teammate builds the full
  // Figma-matched layout here, using the controllers, _formKey,
  // _login(), _obscurePassword, _isLoading, and _errorMessage above.
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SizedBox.shrink(), // placeholder — replace with actual UI
    );
  }
}
