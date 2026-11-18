// Appeals: suspended students and tutors asking for their suspension to be
// reconsidered. The administrator reads the original reason and the user's
// explanation, then approves (the suspension is lifted) or rejects (it
// stays), with an explanation the user is shown. The backend checks the
// permission again for every decision.

import 'package:flutter/material.dart';

import 'Services/admin_appeals_service.dart';
import 'admin_shell.dart';
import 'models/admin_appeal_models.dart';

const _green = Color(0xFF1B7F3A);
const _greenBg = Color(0xFFD9F5E0);
const _amber = Color(0xFFB45309);
const _amberBg = Color(0xFFFDEBD0);
const _red = Color(0xFFC62828);
const _redBg = Color(0xFFFDE2E2);
const _greyBg = Color(0xFFE8EAEE);

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

class AdminAppealsScreen extends StatefulWidget {
  const AdminAppealsScreen({super.key, this.service});

  final AdminAppealsService? service;

  @override
  State<AdminAppealsScreen> createState() => _AdminAppealsScreenState();
}

class _AdminAppealsScreenState extends State<AdminAppealsScreen> {
  late final AdminAppealsService _service;
  late final bool _ownsService;

  String _status = 'pending';
  AdminAppealsPage? _data;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AdminAppealsService();
    _ownsService = widget.service == null;
    _load();
  }

  @override
  void dispose() {
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetchAppeals(status: _status);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _setStatus(String status) {
    if (status == _status) return;
    setState(() => _status = status);
    _load();
  }

  Future<void> _review(AdminAppeal appeal, {required bool approve}) async {
    final result = await showDialog<AdminAppealDecisionResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DecisionDialog(
        appeal: appeal,
        approve: approve,
        service: _service,
      ),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.warning ??
              (approve
                  ? 'Appeal approved. ${appeal.user.name} has been reinstated '
                        'and notified.'
                  : 'Appeal rejected. ${appeal.user.name} has been notified.'),
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return AdminShell(
      currentRoute: AdminRoutes.appeals,
      adminName: data?.adminName,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(pending: data?.pending),
                const SizedBox(height: 20),
                _buildFilters(),
                const SizedBox(height: 12),
                if (_loading && data == null)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null && data == null)
                  _Card(
                    child: _StateMessage(
                      icon: Icons.error_outline,
                      title: 'Could not load appeals.',
                      message: _msg(_error!),
                      action: ElevatedButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ),
                  )
                else ...[
                  if (_error != null) ...[
                    _InlineError(
                      message: 'Could not refresh appeals: ${_msg(_error!)}',
                      onRetry: _load,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildList(data!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final (label, key) in adminAppealStatuses)
        _FilterChip(
          label: label,
          active: _status == key,
          onTap: () => _setStatus(key),
        ),
      if (_loading)
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      else
        IconButton(
          tooltip: 'Refresh',
          onPressed: _load,
          icon: const Icon(Icons.refresh, size: 20),
        ),
    ],
  );

  Widget _buildList(AdminAppealsPage data) {
    if (data.appeals.isEmpty) {
      return _Card(
        child: _StateMessage(
          icon: Icons.gavel_outlined,
          title: _status == 'pending'
              ? 'No appeals waiting'
              : 'No appeals match this filter.',
          message: _status == 'pending'
              ? 'Appeals from suspended students and tutors will appear here.'
              : 'Try a different status.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in data.appeals) ...[
          _AppealCard(
            appeal: a,
            onApprove: () => _review(a, approve: true),
            onReject: () => _review(a, approve: false),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.pending});
  final int? pending;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Appeals',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: AdminColors.textDark,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        pending == null
            ? 'Suspended students and tutors asking for a review.'
            : '$pending waiting for a decision.',
        style: const TextStyle(fontSize: 14, color: AdminColors.textMuted),
      ),
    ],
  );
}

class _AppealCard extends StatelessWidget {
  const _AppealCard({
    required this.appeal,
    required this.onApprove,
    required this.onReject,
  });

  final AdminAppeal appeal;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final a = appeal;
    final (fg, bg) = switch (a.status) {
      'Pending' => (_amber, _amberBg),
      'Approved' => (_green, _greenBg),
      'Rejected' => (_red, _redBg),
      _ => (AdminColors.textDark, _greyBg),
    };
    final u = a.user;
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Pill(label: a.status, color: fg, background: bg),
                _Pill(
                  label: u.roleLabel,
                  color: AdminColors.textDark,
                  background: _greyBg,
                ),
                Text(
                  'Sent ${a.submittedLabel}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              u.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AdminColors.textDark,
              ),
            ),
            Text(
              [
                if (u.email.isNotEmpty) u.email,
                if (u.phone != null) u.phone!,
                'Account: ${u.accountStatus}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: AdminColors.textMuted),
            ),
            const SizedBox(height: 14),
            _Block(
              heading:
                  'Suspension reason · ${a.suspension.suspendedLabel}'
                  '${a.suspension.suspendedBy == null ? '' : ' · by ${a.suspension.suspendedBy}'}',
              text: a.suspension.reason,
            ),
            const SizedBox(height: 10),
            _Block(heading: 'Appeal', text: a.explanation),
            if (!a.isPending) ...[
              const SizedBox(height: 10),
              _Block(
                heading:
                    'Decision · ${a.decidedLabel}'
                    '${a.reviewedBy == null ? '' : ' · by ${a.reviewedBy}'}',
                text: a.decisionNote ?? 'No explanation given.',
              ),
            ],
            if (a.isPending) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: onApprove,
                    style: FilledButton.styleFrom(backgroundColor: _green),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Approve'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(foregroundColor: _red),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DecisionDialog extends StatefulWidget {
  const _DecisionDialog({
    required this.appeal,
    required this.approve,
    required this.service,
  });

  final AdminAppeal appeal;
  final bool approve;
  final AdminAppealsService service;

  @override
  State<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<_DecisionDialog> {
  final _note = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.service.decide(
        widget.appeal.id,
        approve: widget.approve,
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _msg(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final approve = widget.approve;
    final name = widget.appeal.user.name;
    return AlertDialog(
      title: Text(approve ? 'Approve appeal?' : 'Reject appeal?'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                approve
                    ? 'The suspension will be lifted and $name can use '
                          'TheoTutoring again.'
                    : "$name's account stays suspended. This is final for "
                          'this suspension.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('decision-note'),
                controller: _note,
                enabled: !_saving,
                minLines: 3,
                maxLines: 6,
                maxLength: appealDecisionNoteMaxLength,
                decoration: InputDecoration(
                  labelText: approve
                      ? 'Note to the user (optional)'
                      : 'Reason, shown to the user',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (approve && text.isEmpty) return null;
                  if (text.length < appealDecisionNoteMinLength) {
                    return approve
                        ? 'Write at least $appealDecisionNoteMinLength '
                              'characters, or leave it empty.'
                        : 'Explain the decision in at least '
                              '$appealDecisionNoteMinLength characters.';
                  }
                  return null;
                },
              ),
              if (_error != null)
                Text(
                  _error!,
                  key: const ValueKey('decision-error'),
                  style: const TextStyle(color: _red, fontSize: 13),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _confirm,
          style: FilledButton.styleFrom(
            backgroundColor: approve ? _green : _red,
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(approve ? 'Approve and reinstate' : 'Reject appeal'),
        ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.heading, required this.text});
  final String heading;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F9FB),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: const TextStyle(fontSize: 11.5, color: AdminColors.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 13.5, color: AdminColors.textDark),
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AdminColors.border),
    ),
    child: child,
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: active ? AdminColors.primary : _greyBg,
    borderRadius: BorderRadius.circular(999),
    child: InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AdminColors.textDark,
          ),
        ),
      ),
    ),
  );
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: AdminColors.textMuted),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AdminColors.textDark,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AdminColors.textMuted),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: _redBg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: _red, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 13, color: _red),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
