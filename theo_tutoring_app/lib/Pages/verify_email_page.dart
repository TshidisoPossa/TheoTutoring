import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import 'auth_gate.dart';
import 'login_page.dart';

/// "Enter the code": shown straight after registering, and at login while
/// the email is still not verified. Opening it emails a 6-digit code (the
/// backend sends it through Brevo); typing all 6 digits checks it.
///
/// After registering ([onVerified] is null) a right code shows a success
/// screen that leads to the login page. At login, [onVerified] opens the
/// app instead.
class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({
    super.key,
    required this.email,
    this.verifiedMessage =
        'Your email is verified. Log in to start using TheoTutoring.',
    this.onVerified,
    this.onSkip,
    this.onSignOut,
    this.service,
  });

  final String email;

  /// Shown on the success screen after registering.
  final String verifiedMessage;

  /// At login: open the app. Null after registering (go to the login page).
  final Future<void> Function()? onVerified;

  /// "Skip for now", only offered while [requireEmailVerification] is off.
  /// Defaults to going to the login page.
  final Future<void> Function()? onSkip;

  /// Defaults to signing out and going to the login page.
  final Future<void> Function()? onSignOut;

  /// Tests pass a fake; the app uses [AuthService.instance].
  final AuthService? service;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage>
    with SingleTickerProviderStateMixin {
  static const _length = 6;

  AuthService get _auth => widget.service ?? AuthService.instance;

  final _code = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  Timer? _countdown;
  int _resendIn = 0;
  bool _sending = false;
  bool _checking = false;
  bool _verified = false;
  bool _busy = false; // Log out / Skip / Continue is working
  String? _error;
  String? _info; // "We sent a new code"

  @override
  void initState() {
    super.initState();
    _code.addListener(_onCodeChanged);
    unawaited(_send(first: true));
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _code.dispose();
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _send({bool first = false}) async {
    if (_sending || _resendIn > 0) return;
    setState(() {
      _sending = true;
      _error = null;
      _info = null;
    });
    try {
      final result = await _auth.sendVerificationCode();
      if (!mounted) return;
      if (result.alreadyVerified) {
        await _succeed();
        return;
      }
      _startCooldown(result.resendIn);
      setState(() {
        if (!first) _info = 'We sent a new code. Older codes no longer work.';
      });
      if (first) _focus.requestFocus();
    } on VerificationCodeException catch (e) {
      if (!mounted) return;
      final wait = e.retryAfter;
      if (wait != null) {
        _startCooldown(wait);
        // Opening the page again soon after: the last code still works.
        if (first) {
          _focus.requestFocus();
          return;
        }
      }
      setState(() => _error = e.message);
    } on AuthAccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _onCodeChanged() {
    if (_error != null && _code.text.isNotEmpty) {
      setState(() => _error = null);
    } else {
      setState(() {}); // redraw the boxes
    }
    if (_code.text.length == _length) unawaited(_check());
  }

  Future<void> _check() async {
    if (_checking || _verified) return;
    final code = _code.text;
    setState(() {
      _checking = true;
      _info = null;
    });
    try {
      await _auth.verifyCode(code);
      if (!mounted) return;
      await _succeed();
    } on VerificationCodeException catch (e) {
      _wrong(e.message);
    } on AuthAccountException catch (e) {
      _wrong(e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _wrong(String message) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    _code.clear();
    setState(() => _error = message);
    _shake.forward(from: 0);
    _focus.requestFocus();
  }

  Future<void> _succeed() async {
    _countdown?.cancel();
    _focus.unfocus();
    final onVerified = widget.onVerified;
    if (onVerified != null) {
      await onVerified();
    } else if (mounted) {
      setState(() => _verified = true);
    }
  }

  void _startCooldown(int seconds) {
    _countdown?.cancel();
    setState(() => _resendIn = seconds);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length < _length) {
      _snack('There is no 6-digit code on your clipboard.');
      return;
    }
    _code.text = digits.substring(0, _length);
  }

  Future<void> _openInbox() async {
    final inbox = _inboxFor(widget.email);
    if (inbox == null) return;
    try {
      if (await launchUrl(inbox.$2, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
    _snack('Could not open ${inbox.$1}. Open your email app yourself.');
  }

  /// Signs out and opens the login page with the email filled in.
  Future<void> _goToLogin() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // The login page still works; Firebase forgets the session anyway.
    }
    if (!mounted) return;
    Navigator.of(context)
      ..pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => AuthGate(service: widget.service),
        ),
        (_) => false,
      )
      ..push(
        MaterialPageRoute<void>(
          builder: (_) => LoginPage(initialEmail: widget.email),
        ),
      );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // leaving is "Log out", so nobody lands on a dead page
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.96, end: 1.0).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _verified ? _successView() : _codeView(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _codeView() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final inbox = _inboxFor(widget.email);
    final error = _error;
    final info = _info;

    return Column(
      key: const ValueKey('code'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _Badge(icon: Icons.mark_email_unread_rounded, color: scheme.primary),
        const SizedBox(height: 28),
        Text(
          'Verify your email',
          textAlign: TextAlign.center,
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          _sending && _resendIn == 0
              ? 'Sending a 6-digit code to'
              : 'Enter the 6-digit code we sent to',
          textAlign: TextAlign.center,
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        _EmailChip(email: widget.email),
        const SizedBox(height: 28),
        AnimatedBuilder(
          animation: _shake,
          builder: (_, child) => Transform.translate(
            offset: Offset(
              math.sin(_shake.value * math.pi * 6) * 10 * (1 - _shake.value),
              0,
            ),
            child: child,
          ),
          child: _CodeBoxes(
            controller: _code,
            focusNode: _focus,
            length: _length,
            hasError: error != null,
            enabled: !_checking,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 44,
          child: Center(
            child: _checking
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('Checking…', style: text.bodyMedium),
                    ],
                  )
                : Text(
                    error ?? info ?? 'The code expires in 10 minutes.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: error != null
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                      fontWeight: error != null ? FontWeight.w600 : null,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              "Didn't get it? Check spam, or",
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            TextButton(
              onPressed: _sending || _resendIn > 0 ? null : _send,
              child: Text(
                _sending
                    ? 'sending…'
                    : _resendIn > 0
                    ? 'resend in ${_formatSeconds(_resendIn)}'
                    : 'resend code',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (inbox != null) ...[
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: FilledButton.tonalIcon(
                    onPressed: _openInbox,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text('Open ${inbox.$1}'),
                    style: _rounded,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _checking ? null : _paste,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('Paste code'),
                  style: _rounded,
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 40),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            if (!requireEmailVerification)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(widget.onSkip ?? _goToLogin),
                child: const Text('Skip for now'),
              ),
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(widget.onSignOut ?? _goToLogin),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Log out'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _successView() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    const green = Color(0xFF16A34A);

    return Column(
      key: const ValueKey('verified'),
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.4, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (_, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: const _Badge(icon: Icons.check_rounded, color: green),
        ),
        const SizedBox(height: 28),
        Text(
          'Email verified',
          textAlign: TextAlign.center,
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          widget.verifiedMessage,
          textAlign: TextAlign.center,
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _busy ? null : () => _run(_goToLogin),
            style: _rounded,
            child: const Text('Continue to log in'),
          ),
        ),
      ],
    );
  }

  static final _rounded = ButtonStyle(
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );
}

/// 0:42
String _formatSeconds(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// The web inbox for common providers, or null (university addresses etc.).
(String, Uri)? _inboxFor(String email) {
  final domain = email.split('@').last.trim().toLowerCase();
  return switch (domain) {
    'gmail.com' || 'googlemail.com' => (
      'Gmail',
      Uri.parse('https://mail.google.com/mail/u/0/#inbox'),
    ),
    'outlook.com' || 'hotmail.com' || 'live.com' || 'msn.com' => (
      'Outlook',
      Uri.parse('https://outlook.live.com/mail/'),
    ),
    'yahoo.com' || 'ymail.com' => (
      'Yahoo Mail',
      Uri.parse('https://mail.yahoo.com/'),
    ),
    'icloud.com' || 'me.com' => (
      'iCloud Mail',
      Uri.parse('https://www.icloud.com/mail'),
    ),
    _ => null,
  };
}

/// Six boxes over one invisible text field, so typing, backspace, pasting
/// and the phone's "code from Messages/Mail" suggestion all just work.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.hasError,
    required this.enabled,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool hasError;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final digits = controller.text;

    return Stack(
      children: [
        IgnorePointer(
          child: ListenableBuilder(
            listenable: focusNode,
            builder: (context, _) => Row(
              children: [
                for (var i = 0; i < length; i++) ...[
                  if (i > 0) SizedBox(width: i == length ~/ 2 ? 16 : 8),
                  Expanded(
                    child: _box(
                      context,
                      scheme,
                      i < digits.length ? digits[i] : '',
                      active:
                          focusNode.hasFocus &&
                          (i == digits.length ||
                              (i == length - 1 && digits.length == length)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(length),
              ],
              showCursor: false,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _box(
    BuildContext context,
    ColorScheme scheme,
    String digit, {
    required bool active,
  }) {
    final filled = digit.isNotEmpty;
    final borderColor = hasError
        ? scheme.error
        : active
        ? scheme.primary
        : filled
        ? scheme.primary.withValues(alpha: 0.45)
        : scheme.outlineVariant;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: active ? 2 : 1.4),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: Text(
          digit,
          key: ValueKey(digit),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _EmailChip extends StatelessWidget {
  const _EmailChip({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alternate_email, size: 18, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              email,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round icon with a soft halo.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 124,
      height: 124,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.1),
      ),
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.85), color],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, size: 44, color: Colors.white),
      ),
    );
  }
}
