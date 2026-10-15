import 'package:flutter/material.dart';

import 'tutor_registration.dart';

class TutorRegistrationPage1 extends StatefulWidget {
  const TutorRegistrationPage1({super.key});

  @override
  State<TutorRegistrationPage1> createState() => _TutorRegistrationPage1State();
}

class _TutorRegistrationPage1State extends State<TutorRegistrationPage1> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _hasInteracted = false;
  bool _canContinue = false;
  bool _isNavigating = false;

  static final _emailPattern = RegExp(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$",
  );
  static final _phonePattern = RegExp(r'^\+?[\d\s-]{8,15}$');

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _fullNameController,
      _emailController,
      _passwordController,
      _confirmPasswordController,
      _phoneController,
    ]) {
      controller.addListener(_refreshFormState);
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool get _formIsValid {
    final name = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final phone = _phoneController.text.trim();
    return name.length >= 2 &&
        name.length <= 100 &&
        email.length <= 150 &&
        _emailPattern.hasMatch(email) &&
        password.length >= 8 &&
        _confirmPasswordController.text == password &&
        phone.isNotEmpty &&
        _phonePattern.hasMatch(phone) &&
        RegExp(r'\d').allMatches(phone).length >= 8;
  }

  void _refreshFormState() {
    if (!mounted) return;
    setState(() {
      _hasInteracted = true;
      _canContinue = _formIsValid;
    });
  }

  void _goToNextStep() {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please correct the highlighted fields.')),
      );
      return;
    }
    if (_isNavigating) return;

    setState(() => _isNavigating = true);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TutorRegistration(
          fullName: _fullNameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          phoneNumber: _phoneController.text.trim(),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isNavigating = false);
    });
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Please enter your full name.';
    if (name.length < 2 || name.length > 100) {
      return 'Name must be between 2 and 100 characters.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Please enter your email address.';
    if (email.length > 150 || !_emailPattern.hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    return null;
  }

  String? _validateConfirmation(String? value) {
    if (value == null || value.isEmpty) return 'Please confirm your password.';
    if (value != _passwordController.text) return 'Passwords do not match.';
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return 'Please enter your phone number.';
    if (!_phonePattern.hasMatch(phone) ||
        RegExp(r'\d').allMatches(phone).length < 8) {
      return 'Enter a valid phone number with 8–15 digits.';
    }
    return null;
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
          child: Form(
            key: _formKey,
            autovalidateMode: _hasInteracted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LinearProgressIndicator(value: 1 / 3),
                const SizedBox(height: 4),
                const Text(
                  'STEP 1 OF 3',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Welcome to TheoTutoring',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Let's start by getting your basic information set up so students can reach you.",
                ),
                const SizedBox(height: 24),
                _fieldLabel('Full Name'),
                TextFormField(
                  controller: _fullNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateName,
                ),
                const SizedBox(height: 20),
                _fieldLabel('Email Address'),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateEmail,
                ),
                const SizedBox(height: 20),
                _fieldLabel('Password'),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: _validatePassword,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Must be at least 8 characters.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                _fieldLabel('Confirm Password'),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () => setState(
                        () =>
                            _obscureConfirmPassword = !_obscureConfirmPassword,
                      ),
                    ),
                  ),
                  validator: _validateConfirmation,
                ),
                const SizedBox(height: 20),
                _fieldLabel('Phone Number'),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: '+27 82 123 4567',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validatePhone,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canContinue && !_isNavigating
                        ? _goToNextStep
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      disabledBackgroundColor: Colors.grey.shade300,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.grey.shade600,
                    ),
                    child: Text(_isNavigating ? 'Please wait…' : 'Next Step →'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
  );
}
