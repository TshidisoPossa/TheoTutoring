// Subjects (Subject Management): the subject catalogue, with local search
// and actions to add, rename and delete subjects. The backend refuses to
// delete a subject that tutors or bookings still reference; that message is
// shown as-is and nothing else is removed.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'Services/admin_subjects_service.dart';
import 'admin_shell.dart';
import 'models/admin_subject_models.dart';

const _red = Color(0xFFC62828);
const _redBg = Color(0xFFFDE2E2);
const _maxNameLength = 100;

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

/// Returns an error message, or null when [value] is a valid subject name.
String? validateSubjectName(String? value) {
  final name = (value ?? '').trim();
  if (name.isEmpty) return 'Enter a subject name.';
  if (name.length > _maxNameLength) {
    return 'Use $_maxNameLength characters or fewer.';
  }
  return null;
}

class AdminSubjectsScreen extends StatefulWidget {
  const AdminSubjectsScreen({super.key, this.service});

  final AdminSubjectsService? service;

  @override
  State<AdminSubjectsScreen> createState() => _AdminSubjectsScreenState();
}

class _AdminSubjectsScreenState extends State<AdminSubjectsScreen> {
  late final AdminSubjectsService _service;
  late final bool _ownsService;
  final _search = TextEditingController();

  List<AdminSubject>? _subjects;
  bool _loading = true;
  bool _busy = false;
  Object? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AdminSubjectsService();
    _ownsService = widget.service == null;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.fetchSubjects();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _subjects = result.subjects;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<AdminSubject> get _filtered {
    final all = _subjects ?? const <AdminSubject>[];
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return all;
    return [
      for (final s in all)
        if (s.subjectName.toLowerCase().contains(query)) s,
    ];
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: error ? _red : null),
      );
  }

  /// Runs one change, then reloads the list from the server (no optimistic
  /// updates).
  Future<void> _mutate(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final success = await action();
      if (!mounted) return;
      _toast(success);
      await _load();
    } catch (e) {
      _toast(_msg(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSubject() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _SubjectNameDialog(
        title: 'Add subject',
        confirmLabel: 'Add subject',
      ),
    );
    if (name == null || !mounted) return;
    await _mutate(() async {
      final created = await _service.createSubject(name);
      return '"${created.subjectName}" was added.';
    });
  }

  Future<void> _renameSubject(AdminSubject subject) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _SubjectNameDialog(
        title: 'Rename subject',
        confirmLabel: 'Save name',
        initialName: subject.subjectName,
      ),
    );
    if (name == null || !mounted || name == subject.subjectName) return;
    await _mutate(() async {
      final renamed = await _service.renameSubject(subject.subjectId, name);
      return '"${subject.subjectName}" was renamed to '
          '"${renamed.subjectName}".';
    });
  }

  Future<void> _deleteSubject(AdminSubject subject) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${subject.subjectName}"?'),
        content: const Text(
          'This removes the subject from the catalogue. A subject that tutors '
          'or bookings still use cannot be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _red),
            child: const Text('Delete subject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _mutate(() async {
      await _service.deleteSubject(subject.subjectId);
      return '"${subject.subjectName}" was deleted.';
    });
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final subjects = _subjects;
    return AdminShell(
      currentRoute: AdminRoutes.subjects,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(onAdd: _busy || subjects == null ? null : _addSubject),
                const SizedBox(height: 20),
                if (_loading && subjects == null)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null && subjects == null)
                  _Card(
                    child: _StateMessage(
                      icon: Icons.error_outline,
                      title: 'Could not load subjects.',
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
                      message: 'Could not refresh subjects: ${_msg(_error!)}',
                      onRetry: _load,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildToolbar(subjects!),
                  const SizedBox(height: 16),
                  _buildList(subjects),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(List<AdminSubject> subjects) {
    final count = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'TOTAL SUBJECTS',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
            color: AdminColors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${subjects.length}',
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: AdminColors.textDark,
          ),
        ),
      ],
    );
    final search = TextField(
      controller: _search,
      onChanged: (_) => setState(() {}),
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Search subjects...',
        hintStyle: const TextStyle(fontSize: 13),
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(_search.clear),
              ),
        filled: true,
        fillColor: const Color(0xFFF3F4F6),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AdminColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AdminColors.border),
        ),
      ),
    );
    final refresh = IconButton(
      tooltip: 'Refresh',
      onPressed: _loading || _busy ? null : _load,
      icon: _loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
    );

    return _Card(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 600) {
            return Row(
              children: [
                count,
                const SizedBox(width: 24),
                Expanded(child: search),
                const SizedBox(width: 8),
                refresh,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [count, const Spacer(), refresh]),
              const SizedBox(height: 12),
              search,
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(List<AdminSubject> subjects) {
    final visible = _filtered;
    final searching = _search.text.trim().isNotEmpty;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xFFF8F9FB),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: const Row(
              children: [
                Expanded(child: _TableHeader('Subject')),
                _TableHeader('Actions'),
              ],
            ),
          ),
          if (subjects.isEmpty) ...[
            const Divider(height: 1, color: AdminColors.border),
            const _StateMessage(
              icon: Icons.menu_book_outlined,
              title: 'No subjects yet',
              message: 'Add a subject so tutors can offer it.',
            ),
          ] else if (visible.isEmpty) ...[
            const Divider(height: 1, color: AdminColors.border),
            const _StateMessage(
              icon: Icons.search_off_outlined,
              title: 'No subjects match',
              message: 'Try another search term.',
            ),
          ] else
            for (final subject in visible) ...[
              const Divider(height: 1, color: AdminColors.border),
              _SubjectRow(
                subject: subject,
                onRename: _busy ? null : () => _renameSubject(subject),
                onDelete: _busy ? null : () => _deleteSubject(subject),
              ),
            ],
          if (searching && subjects.isNotEmpty) ...[
            const Divider(height: 1, color: AdminColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Showing ${visible.length} of ${subjects.length} '
                '${subjects.length == 1 ? 'subject' : 'subjects'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ widgets

class _Header extends StatelessWidget {
  const _Header({required this.onAdd});
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.end,
    spacing: 16,
    runSpacing: 12,
    children: [
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Subject Management',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: AdminColors.textDark,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Maintain the subjects tutors can offer and students can book.',
            style: TextStyle(fontSize: 14, color: AdminColors.textMuted),
          ),
        ],
      ),
      FilledButton.icon(
        onPressed: onAdd,
        style: FilledButton.styleFrom(backgroundColor: AdminColors.primary),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add Subject'),
      ),
    ],
  );
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({
    required this.subject,
    required this.onRename,
    required this.onDelete,
  });

  final AdminSubject subject;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subject.subjectName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AdminColors.textDark,
                ),
              ),
              Text(
                'ID: ${subject.subjectId}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AdminColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Rename ${subject.subjectName}',
          icon: const Icon(Icons.edit_outlined, color: AdminColors.accent),
          onPressed: onRename,
        ),
        IconButton(
          tooltip: 'Delete ${subject.subjectName}',
          icon: const Icon(Icons.delete_outline, color: _red),
          onPressed: onDelete,
        ),
      ],
    ),
  );
}

/// Asks for a subject name and returns it trimmed, or null when cancelled.
class _SubjectNameDialog extends StatefulWidget {
  const _SubjectNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initialName = '',
  });

  final String title;
  final String confirmLabel;
  final String initialName;

  @override
  State<_SubjectNameDialog> createState() => _SubjectNameDialogState();
}

class _SubjectNameDialogState extends State<_SubjectNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _formKey,
        child: TextFormField(
          controller: _name,
          autofocus: true,
          maxLength: _maxNameLength,
          // Over-long names are rejected by the validator, not silently cut.
          maxLengthEnforcement: MaxLengthEnforcement.none,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          validator: validateSubjectName,
          decoration: const InputDecoration(
            labelText: 'Subject name',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submit,
        style: FilledButton.styleFrom(backgroundColor: AdminColors.primary),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AdminColors.border),
    ),
    child: child,
  );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      letterSpacing: 0.6,
      fontWeight: FontWeight.w600,
      color: AdminColors.textMuted,
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
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: AdminColors.textMuted),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AdminColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AdminColors.textMuted,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
    decoration: BoxDecoration(
      color: _redBg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, size: 18, color: _red),
        const SizedBox(width: 10),
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
