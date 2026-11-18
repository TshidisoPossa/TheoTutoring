import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'Services/admin_chat_moderation_service.dart';
import 'admin_shell.dart';

/// Admin → Chat Moderation: every chat message the filter blocked (contact
/// details or abuse), with the sender's explanation. The admin restores the
/// sender's chat or keeps it suspended; the sender is told either way.
class AdminChatModerationScreen extends StatefulWidget {
  const AdminChatModerationScreen({super.key, this.service});

  /// Tests pass a fake.
  final AdminChatModerationService? service;

  @override
  State<AdminChatModerationScreen> createState() =>
      _AdminChatModerationScreenState();
}

class _AdminChatModerationScreenState extends State<AdminChatModerationScreen> {
  late final AdminChatModerationService _service =
      widget.service ?? AdminChatModerationService();

  List<ChatModerationCase> _cases = [];
  bool _loading = true;
  String? _error;
  bool _showClosed = false;

  static final _time = DateFormat('d MMM yyyy, HH:mm');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cases = await _service.cases();
      if (!mounted) return;
      setState(() {
        _cases = cases;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _decide(ChatModerationCase c, {required bool lift}) async {
    String? note;
    if (!lift) {
      note = await showDialog<String>(
        context: context,
        builder: (_) => _KeepDialog(name: c.name),
      );
      if (note == null) return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.decide(c.userId, lift: lift, note: note);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            lift
                ? "${c.name}'s chat has been restored."
                : "${c.name}'s chat stays suspended.",
          ),
        ),
      );
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _cases.where((c) => c.isOpen).toList();
    final shown = _showClosed ? _cases : open;
    return AdminShell(
      currentRoute: AdminRoutes.chatModeration,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Chat Moderation',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AdminColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Messages blocked for sharing contact details or abusive '
              "language. The sender's chat is suspended until you decide.",
              style: TextStyle(color: AdminColors.textMuted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text('${open.length} open')),
                FilterChip(
                  label: const Text('Show decided cases'),
                  selected: _showClosed,
                  onSelected: (v) => setState(() => _showClosed = v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Column(
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  TextButton(onPressed: _load, child: const Text('Try again')),
                ],
              )
            else if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(
                    'No chat messages waiting for review.',
                    style: TextStyle(color: AdminColors.textMuted),
                  ),
                ),
              )
            else
              for (final c in shown) _buildCase(c),
          ],
        ),
      ),
    );
  }

  Widget _buildCase(ChatModerationCase c) {
    final statusColor = switch (c.status) {
      'appealed' => const Color(0xFF0052D4),
      'suspended' => const Color(0xFFB45309),
      'lifted' => const Color(0xFF16A34A),
      _ => const Color(0xFFDC2626),
    };
    return Card(
      key: ValueKey('chat-case-${c.userId}'),
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AdminColors.border),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  c.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  c.role == 'tutor' ? 'Tutor' : 'Student',
                  style: const TextStyle(color: AdminColors.textMuted),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    c.statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (c.flagCount > 1)
                  Text(
                    '${c.flagCount} blocked messages in total',
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'To ${c.otherName.isEmpty ? 'another user' : c.otherName}'
              '${c.flaggedAt == null ? '' : ' · ${_time.format(c.flaggedAt!)}'}'
              ' · contained ${c.reason}',
              style: const TextStyle(
                fontSize: 12,
                color: AdminColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            _quote('Blocked message', c.flaggedText),
            const SizedBox(height: 10),
            if (c.appeal != null)
              _quote("${c.name}'s explanation", c.appeal!)
            else if (c.isOpen)
              const Text(
                'No explanation yet. You can decide now or wait for one.',
                style: TextStyle(
                  fontSize: 12,
                  color: AdminColors.textMuted,
                ),
              ),
            if (c.decidedBy != null) ...[
              const SizedBox(height: 10),
              Text(
                'Decided by ${c.decidedBy}'
                '${c.decisionNote == null ? '' : ': ${c.decisionNote}'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textMuted,
                ),
              ),
            ],
            if (c.isOpen) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _decide(c, lift: true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Restore chat'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _decide(c, lift: false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                    ),
                    icon: const Icon(Icons.block_rounded, size: 18),
                    label: const Text('Keep suspended'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _quote(String label, String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(8),
      border: const Border(
        left: BorderSide(color: AdminColors.border, width: 3),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AdminColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(text, style: const TextStyle(fontSize: 14)),
      ],
    ),
  );
}

/// Asks for the reason the user sees when their chat stays suspended.
class _KeepDialog extends StatefulWidget {
  const _KeepDialog({required this.name});

  final String name;

  @override
  State<_KeepDialog> createState() => _KeepDialogState();
}

class _KeepDialogState extends State<_KeepDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text("Keep ${widget.name}'s chat suspended?"),
    content: TextField(
      controller: _controller,
      maxLength: 1000,
      minLines: 2,
      maxLines: 4,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        labelText: 'Reason (the user sees this)',
        border: OutlineInputBorder(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _controller.text.trim().length >= 5
            ? () => Navigator.pop(context, _controller.text.trim())
            : null,
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
        child: const Text('Keep suspended'),
      ),
    ],
  );
}
