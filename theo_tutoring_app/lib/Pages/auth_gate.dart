import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'Admin/Services/admin_access_service.dart';
import 'Admin/admin_shell.dart';
import 'Student/student_dashboard.dart';
import 'Tutor/tutor_api.dart';
import 'Tutor/tutor_dashboard.dart';
import 'Tutor/tutor_presence.dart';
import 'Tutor/tutor_theme.dart';
import 'login_page.dart';
import 'role_selection.dart';
import 'tutor_registration.dart';
import 'verify_email_page.dart';

/// Whether students and tutors must verify their email before they can use
/// the app. Admin accounts are never asked.
///
/// Developer switch: set to false while testing with made-up emails that
/// have no inbox. Users then get "Skip for now", and are reminded once per
/// app run.
const bool requireEmailVerification = true;

/// Signs out and goes back to the start screen, clearing the history so
/// Back cannot return to the signed-in pages. Every Log Out button uses this.
Future<void> signOutToStart(BuildContext context) async {
  await AuthService.instance.signOut();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const AuthGate()),
    (_) => false,
  );
}

/// The first screen. Waits for Firebase to restore the saved sign-in, then
/// asks the backend who the user is (GET /auth/me) and opens their
/// dashboard. Nobody signed in: the splash screen with Log In / Register.
///
/// It decides once when it opens: the login page opens a new AuthGate after
/// signing in, so registration (which also signs the user in) is never
/// interrupted. It does notice signing out, e.g. at the end of registration.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.service});

  /// Tests pass a fake; the app uses [AuthService.instance].
  final AuthService? service;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

/// Users already reminded to verify their email during this app run.
final Set<String> _remindedToVerify = {};

class _AuthGateState extends State<AuthGate> {
  AuthService get _auth => widget.service ?? AuthService.instance;

  StreamSubscription<User?>? _signOuts;

  bool _loading = true;
  bool _signedOut = false;
  SignedInAccount? _verifyReminder;
  _GateMessage? _message;

  @override
  void initState() {
    super.initState();
    _signOuts = _auth.authStateChanges().listen((user) {
      if (user == null && mounted) _show(signedOut: true);
    });
    unawaited(_start());
  }

  @override
  void dispose() {
    _signOuts?.cancel();
    super.dispose();
  }

  void _show({
    bool loading = false,
    bool signedOut = false,
    SignedInAccount? verifyReminder,
    _GateMessage? message,
  }) {
    if (!mounted) return;
    setState(() {
      _loading = loading;
      _signedOut = signedOut;
      _verifyReminder = verifyReminder;
      _message = message;
    });
  }

  Future<void> _start() async {
    final User? user;
    try {
      user = await _auth.restoredUser();
    } catch (_) {
      _show(signedOut: true);
      return;
    }
    if (user == null) {
      _show(signedOut: true);
      return;
    }
    await _resolve();
  }

  Future<void> _resolve() async {
    _show(loading: true);

    final SignedInAccount account;
    try {
      account = await _auth.fetchAccount();
    } on AuthAccountException catch (e) {
      if (e.signedOut) {
        await _signOut(); // expired or disabled: sign in again
      } else if (e.notRegistered) {
        _show(
          message: const _GateMessage(
            'Your registration was not finished. Sign out and register '
            'again, or contact support if this keeps happening.',
          ),
        );
      } else {
        _show(message: _GateMessage(e.message, canRetry: true));
      }
      return;
    }

    if (await _needsVerifyReminder(account)) {
      _show(verifyReminder: account);
      return;
    }
    await _openHome(account);
  }

  Future<bool> _needsVerifyReminder(SignedInAccount account) async {
    if (account.role == 'admin' || account.emailVerified) return false;
    // A tutor only becomes Active once an admin approves their application,
    // so an approved tutor is already known to the platform and signs
    // straight in. New tutors (Incomplete or Pending) and all students are
    // still asked to verify their email.
    if (account.role == 'tutor' &&
        account.accountStatus.trim().toLowerCase() == 'active') {
      return false;
    }
    final uid = _auth.currentUser?.uid;
    if (!requireEmailVerification && _remindedToVerify.contains(uid)) {
      return false;
    }
    // The ID token may be older than the click on the email link.
    try {
      return !await _auth.checkEmailVerified();
    } catch (_) {
      return true;
    }
  }

  /// Opens the dashboard for the account's role.
  Future<void> _openHome(SignedInAccount account) async {
    final status = account.accountStatus.trim().toLowerCase();
    if (status == 'suspended' || status == 'deactivated') {
      _show(
        message: const _GateMessage(
          'This account is not active. Please contact support.',
        ),
      );
      return;
    }

    switch (account.role) {
      case 'student':
        TutorTheme.signedIn('student'); // dark mode, if they turned it on
        _replaceWith(
          StudentDashboard(
            studentName: account.name.isEmpty ? null : account.name,
          ),
        );
      case 'tutor':
        await _openTutorHome(account);
      case 'admin':
        await _openAdminHome();
      default:
        _show(
          message: const _GateMessage(
            'This account does not have a student, tutor or administrator '
            'profile. Please contact support.',
          ),
        );
    }
  }

  Future<void> _openTutorHome(SignedInAccount account) async {
    if (account.accountStatus.trim().toLowerCase() == 'incomplete') {
      _show(
        message: _GateMessage(
          'Your tutor registration is not finished yet.',
          action: ('Continue registration', () => _continueTutorSignUp(account)),
        ),
      );
      return;
    }

    _show(loading: true);
    try {
      final dashboard = await fetchTutorDashboard(
        idToken: await _auth.idToken(),
      );
      if (!mounted) return;
      // Students see "Available Now" on this tutor's profile from here on
      TutorPresence.instance.start();
      TutorTheme.signedIn('tutor'); // dark mode, if the tutor turned it on
      _replaceWith(TutorDashboard(initialData: dashboard));
    } on TutorApiException catch (e) {
      _show(
        message: _GateMessage(
          switch (e.statusCode) {
            403 || 404 => 'This tutor account cannot open the app right now. '
                'Please contact support.',
            _ => e.message,
          },
          canRetry: e.statusCode == null || e.statusCode! >= 500,
        ),
      );
    } on AuthAccountException {
      await _signOut();
    }
  }

  Future<void> _openAdminHome() async {
    _show(loading: true);
    final AdminAccessResult access;
    try {
      access = await AdminAccessService().checkToken(await _auth.idToken());
    } on AuthAccountException {
      await _signOut();
      return;
    }
    if (!mounted) return;
    switch (access.status) {
      case AdminAccessStatus.allowed:
        Navigator.of(context).pushReplacementNamed(AdminRoutes.dashboard);
      case AdminAccessStatus.denied:
        _show(
          message: const _GateMessage(
            'An active administrator account is required.',
          ),
        );
      case AdminAccessStatus.unavailable:
        _show(
          message: const _GateMessage(
            'Administrator access could not be verified. Please try again.',
            canRetry: true,
          ),
        );
    }
  }

  // Steps 2 and 3 again for a tutor who stopped half-way. The last step
  // signs out and comes back here.
  void _continueTutorSignUp(SignedInAccount account) {
    final user = _auth.currentUser;
    if (user == null) {
      _show(signedOut: true);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TutorRegistration(
          fullName: account.name,
          email: account.email,
          password: '',
          phoneNumber: user.phoneNumber ?? '',
          existingFirebaseUser: user,
        ),
      ),
    );
  }

  void _replaceWith(Widget page) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Still show the start screen; Firebase forgets the session anyway
      // once its token is rejected.
    }
    _show(signedOut: true);
  }

  // "Skip for now" (only while verification is not required)
  Future<void> _skipVerify() async {
    final account = _verifyReminder!;
    final uid = _auth.currentUser?.uid;
    if (uid != null) _remindedToVerify.add(uid);
    await _openHome(account);
  }

  @override
  Widget build(BuildContext context) {
    if (_signedOut) return const _SplashScreen();

    final reminder = _verifyReminder;
    if (reminder != null) {
      return VerifyEmailPage(
        email: reminder.email.isNotEmpty
            ? reminder.email
            : _auth.currentUser?.email ?? '',
        service: _auth,
        onVerified: () => _openHome(reminder),
        onSkip: _skipVerify,
        onSignOut: _signOut,
      );
    }

    final message = _message;
    if (message != null && !_loading) {
      return _MessageScreen(
        message: message,
        onRetry: message.canRetry ? _resolve : null,
        onSignOut: _signOut,
      );
    }

    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _GateMessage {
  const _GateMessage(this.text, {this.canRetry = false, this.action});

  final String text;
  final bool canRetry;
  final (String, VoidCallback)? action; // an extra button
}

/// First screen for someone who is not signed in (documentation 9.1).
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.blue.shade100,
                  child: const Icon(Icons.school, size: 66, color: Colors.blue),
                ),
                const SizedBox(height: 24),
                const Text(
                  'TheoTutoring',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Find the right tutor for your modules.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Log In',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const RoleSelectionPage(),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Register',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageScreen extends StatelessWidget {
  const _MessageScreen({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final _GateMessage message;
  final Future<void> Function()? onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final action = message.action;
    final onRetry = this.onRetry;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 48, color: Colors.blue),
              const SizedBox(height: 16),
              Text(
                message.text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 20),
              if (action != null) ...[
                FilledButton(onPressed: action.$2, child: Text(action.$1)),
                const SizedBox(height: 8),
              ],
              if (onRetry != null) ...[
                FilledButton(onPressed: onRetry, child: const Text('Try again')),
                const SizedBox(height: 8),
              ],
              TextButton(onPressed: onSignOut, child: const Text('Sign out')),
            ],
          ),
        ),
      ),
    );
  }
}
