import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/account_suspension_api.dart';

// "Account suspended": what a suspended student or tutor sees instead of
// their dashboard (opened by the AuthGate), and where the "Account
// suspended" notification card leads. It shows the suspension notice and
// reason, lets the user send one appeal, and shows the appeal's status and
// the administrator's decision. It never opens the rest of the app: that
// stays closed until an administrator lifts the suspension.

const _blue = Color(0xFF356AE6);
const _red = Color(0xFFC62828);
const _redBg = Color(0xFFFDEDED);
const _amber = Color(0xFFB45309);
const _amberBg = Color(0xFFFDF3E1);
const _green = Color(0xFF1B7F3A);
const _greenBg = Color(0xFFE3F5E8);
const _muted = Color(0xFF6B7280);

String _when(DateTime? date) =>
    date == null ? '' : DateFormat('d MMM yyyy, HH:mm').format(date);

/// The link under a suspension or appeal-decision notification card (both
/// bells use it), or null for any other card. It opens this page.
String? accountNoticeLink(String type) => switch (type) {
  'AccountSuspended' => 'View suspension and appeal',
  'AppealApproved' || 'AppealRejected' => 'View appeal',
  _ => null,
};

class AccountSuspensionPage extends StatefulWidget {
  const AccountSuspensionPage({
    super.key,
    this.api,
    this.onSignOut,
    this.onReinstated,
  });

  /// Tests pass a fake.
  final AccountSuspensionApi? api;

  /// Shown as "Sign out" (from the AuthGate, where there is no going back).
  final Future<void> Function()? onSignOut;

  /// "Continue" once the account is active again: opens the app normally.
  final Future<void> Function()? onReinstated;

  @override
  State<AccountSuspensionPage> createState() => _AccountSuspensionPageState();
}

class _AccountSuspensionPageState extends State<AccountSuspensionPage> {
  late final AccountSuspensionApi _api = widget.api ?? AccountSuspensionApi();
  final _explanation = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  AccountSuspensionStatus? _status;
  bool _loading = true;
  String? _error;
  bool _sending = false;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _explanation.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _api.fetch();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    if (_sending || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await _api.submitAppeal(_explanation.text.trim());
      if (!mounted) return;
      _explanation.clear();
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your appeal was sent.')),
      );
      await _load();
    } on AccountSuspensionException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendError = e.message;
      });
      // e.g. already appealed from another device: show the real state
      if (e.code == 'appeal_exists' || e.code == 'not_suspended') _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSignOut = widget.onSignOut;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FE),
      appBar: AppBar(
        automaticallyImplyLeading: onSignOut == null,
        title: const Text('Account status'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_loading && _status == null)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null && _status == null)
                  _Panel(
                    child: Column(
                      children: [
                        const Icon(Icons.cloud_off, size: 40, color: _muted),
                        const SizedBox(height: 12),
                        const Text(
                          'Your account details could not be loaded.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _muted, fontSize: 13),
                        ),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  )
                else
                  ..._content(_status!),
                if (onSignOut != null) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: onSignOut,
                      child: const Text('Sign out'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(AccountSuspensionStatus status) {
    final suspension = status.suspension;
    final appeal = status.appeal;
    final reinstated = !status.isSuspended && status.accountStatus.isNotEmpty;
    return [
      if (status.isSuspended)
        _SuspensionNotice(suspension: suspension)
      else
        _Panel(
          color: _greenBg,
          child: Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: _green),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  suspension == null
                      ? 'Your account is not suspended.'
                      : 'Your account is no longer suspended.',
                  style: const TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      if (!status.isSuspended && suspension != null) ...[
        const SizedBox(height: 12),
        _SuspensionNotice(suspension: suspension, past: true),
      ],
      const SizedBox(height: 16),
      if (appeal != null)
        _AppealStatusCard(appeal: appeal)
      else if (status.canAppeal)
        _buildForm(status)
      else if (status.isSuspended)
        const _Panel(
          child: Text(
            'This suspension cannot be appealed here. Please contact '
            'TheoTutoring support.',
            style: TextStyle(color: _muted),
          ),
        ),
      if (reinstated && widget.onReinstated != null) ...[
        const SizedBox(height: 16),
        FilledButton(
          onPressed: widget.onReinstated,
          style: FilledButton.styleFrom(backgroundColor: _blue),
          child: const Text('Continue to TheoTutoring'),
        ),
      ],
    ];
  }

  Widget _buildForm(AccountSuspensionStatus status) {
    final min = status.explanationMinLength;
    final max = status.explanationMaxLength;
    return _Panel(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Appeal this suspension',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Explain why you think the suspension should be reconsidered. '
              'An administrator will review it. You can send one appeal for '
              'this suspension.',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('appeal-explanation'),
              controller: _explanation,
              enabled: !_sending,
              minLines: 4,
              maxLines: 8,
              maxLength: max,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Your explanation',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Please write your explanation.';
                if (text.length < min) {
                  return 'Please write at least $min characters.';
                }
                if (text.length > max) {
                  return 'Please keep it under $max characters.';
                }
                return null;
              },
            ),
            if (_sendError != null) ...[
              const SizedBox(height: 4),
              Text(
                _sendError!,
                key: const ValueKey('appeal-error'),
                style: const TextStyle(color: _red, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _sending ? null : _send,
              style: FilledButton.styleFrom(backgroundColor: _blue),
              child: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Send appeal'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.color = Colors.white});
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: child,
  );
}

/// The suspension notice: the same message as the notification card.
class _SuspensionNotice extends StatelessWidget {
  const _SuspensionNotice({required this.suspension, this.past = false});
  final AccountSuspension? suspension;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final s = suspension;
    return _Panel(
      color: past ? Colors.white : _redBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.block,
                color: past ? _muted : _red,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  past
                      ? 'Previous suspension'
                      : 'Your account has been suspended',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: past ? Colors.black87 : _red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (s == null)
            const Text(
              'While your account is suspended you cannot book or give '
              'lessons, or use chat. Please contact TheoTutoring support.',
            )
          else ...[
            if (s.suspendedAt != null)
              Text(
                'Suspended on ${_when(s.suspendedAt)}',
                style: const TextStyle(color: _muted, fontSize: 12.5),
              ),
            const SizedBox(height: 8),
            const Text(
              'Reason',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(s.reason, key: const ValueKey('suspension-reason')),
            if (!past) ...[
              const SizedBox(height: 10),
              const Text(
                'While your account is suspended you cannot book or give '
                'lessons, or use chat.',
                style: TextStyle(color: _muted, fontSize: 12.5),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AppealStatusCard extends StatelessWidget {
  const _AppealStatusCard({required this.appeal});
  final SuspensionAppeal appeal;

  @override
  Widget build(BuildContext context) {
    final (title, message, color, background, icon) = switch (appeal.status) {
      AppealStatus.pending => (
        'Appeal under review',
        'An administrator will review your appeal. You will be told the '
            'decision here and by notification.',
        _amber,
        _amberBg,
        Icons.hourglass_top,
      ),
      AppealStatus.approved => (
        'Appeal approved',
        'Your suspension was lifted.',
        _green,
        _greenBg,
        Icons.check_circle_outline,
      ),
      AppealStatus.rejected => (
        'Appeal rejected',
        'Your account remains suspended. This decision is final for this '
            'suspension; contact TheoTutoring support if you need help.',
        _red,
        _redBg,
        Icons.cancel_outlined,
      ),
      AppealStatus.closed => (
        'Appeal closed',
        'The suspension ended before your appeal was decided.',
        _muted,
        Colors.white,
        Icons.info_outline,
      ),
      AppealStatus.unknown => (
        'Appeal',
        '',
        _muted,
        Colors.white,
        Icons.info_outline,
      ),
    };
    return _Panel(
      color: background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  key: const ValueKey('appeal-status'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(message),
          ],
          if (appeal.decisionNote != null) ...[
            const SizedBox(height: 10),
            const Text(
              "Administrator's explanation",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(appeal.decisionNote!, key: const ValueKey('decision-note')),
          ],
          if (appeal.decidedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Decided on ${_when(appeal.decidedAt)}',
              style: const TextStyle(color: _muted, fontSize: 12.5),
            ),
          ],
          const Divider(height: 24),
          Text(
            'Your appeal${appeal.submittedAt == null ? '' : ', sent ${_when(appeal.submittedAt)}'}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(appeal.explanation, style: const TextStyle(color: _muted)),
        ],
      ),
    );
  }
}
