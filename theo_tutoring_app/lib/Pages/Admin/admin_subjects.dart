import 'package:flutter/material.dart';

import 'Services/admin_subjects_service.dart';
import 'admin_shell.dart';
import 'models/admin_subject_models.dart';

const _subjectsBackground = Color(0xFFF5F7FA);
const _subjectsCard = Colors.white;
const _subjectsText = Color(0xFF202938);
const _subjectsMuted = Color(0xFF687386);
const _subjectsPrimary = Color(0xFF3157A4);
const _subjectsBorder = Color(0xFFE5E9F0);

String _message(Object error) {
  return error.toString().replaceFirst('Exception: ', '');
}

class AdminSubjectsScreen extends StatefulWidget {
  const AdminSubjectsScreen({
    super.key,
    this.service,
  });

  final AdminSubjectsService? service;

  @override
  State<AdminSubjectsScreen> createState() => _AdminSubjectsScreenState();
}

class _AdminSubjectsScreenState extends State<AdminSubjectsScreen> {
  late final AdminSubjectsService _service;
  late final bool _ownsService;

  final TextEditingController _searchController = TextEditingController();

  List<AdminSubject> _subjects = [];
  bool _loading = true;
  String? _error;
  // True once a load has succeeded; later failures keep the list shown.
  bool _hasLoaded = false;
  // A refresh after a successful load: the list stays visible and only a
  // small indicator replaces the refresh button.
  bool _refreshing = false;
  String _searchQuery = '';
  int _loadGeneration = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _ownsService = widget.service == null;
    _service = widget.service ?? AdminSubjectsService();

    _loadSubjects();
  }

  @override
  void dispose() {
    _searchController.dispose();

    if (_ownsService) {
      _service.dispose();
    }

    super.dispose();
  }

  Future<void> _loadSubjects({bool showLoading = true}) async {
    final generation = ++_loadGeneration;

    if (showLoading && mounted) {
      setState(() {
        if (_hasLoaded) {
          _refreshing = true;
        } else {
          _loading = true;
        }
        _error = null;
      });
    }

    try {
      final result = await _service.fetchSubjects();

      if (!mounted || generation != _loadGeneration) return;

      setState(() {
        _subjects = result.subjects;
        _hasLoaded = true;
        _loading = false;
        _refreshing = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;

      // A failed refresh keeps the subjects already loaded and reports the
      // problem in a snackbar; only a failed first load shows the error card.
      if (_hasLoaded) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
        _showError('Could not refresh subjects: ${_message(error)}');
        return;
      }

      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  List<AdminSubject> get _filteredSubjects {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) return _subjects;

    return _subjects
        .where((subject) => subject.subjectName.toLowerCase().contains(query))
        .toList();
  }

  Future<String?> _showSubjectDialog({
    AdminSubject? subject,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _SubjectNameDialog(
        initialName: subject?.subjectName ?? '',
        isEditing: subject != null,
      ),
    );
  }

  Future<void> _addSubject() async {
    if (_saving) return;

    final name = await _showSubjectDialog();
    if (!mounted || name == null) return;

    setState(() => _saving = true);

    try {
      await _service.createSubject(name);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subject added successfully.')),
      );

      await _loadSubjects(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _renameSubject(AdminSubject subject) async {
    if (_saving) return;

    final name = await _showSubjectDialog(subject: subject);
    if (!mounted || name == null) return;

    if (name == subject.subjectName) return;

    setState(() => _saving = true);

    try {
      await _service.renameSubject(subject.subjectId, name);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subject renamed successfully.')),
      );

      await _loadSubjects(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteSubject(AdminSubject subject) async {
    if (_saving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete subject?'),
          content: Text(
            'Are you sure you want to delete "${subject.subjectName}"? '
            'Subjects already used by tutors or bookings cannot be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;

    setState(() => _saving = true);

    try {
      await _service.deleteSubject(subject.subjectId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subject deleted successfully.')),
      );

      await _loadSubjects(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_message(error)),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredSubjects = _filteredSubjects;

    return AdminShell(
      currentRoute: AdminRoutes.subjects,
      child: Container(
        color: _subjectsBackground,
        width: double.infinity,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildSummaryCard(),
                  const SizedBox(height: 20),
                  _buildSearchAndAdd(),
                  const SizedBox(height: 16),
                  _buildSubjectList(filteredSubjects),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Subject Management',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: _subjectsText,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Manage the subjects available for tutoring on the platform.',
          style: TextStyle(
            fontSize: 14,
            color: _subjectsMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _subjectsCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _subjectsBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _subjectsPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.menu_book_outlined,
              color: _subjectsPrimary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total subjects',
                  style: TextStyle(
                    color: _subjectsMuted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _loading ? '—' : '${_subjects.length}',
                  style: const TextStyle(
                    color: _subjectsText,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (_refreshing)
            const Tooltip(
              message: 'Refreshing subjects',
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Refresh subjects',
              onPressed: _loading || _saving ? null : _loadSubjects,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchAndAdd() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final search = TextField(
          controller: _searchController,
          onChanged: (value) {
            setState(() => _searchQuery = value);
          },
          decoration: InputDecoration(
            hintText: 'Search subjects...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    icon: const Icon(Icons.close),
                  ),
            filled: true,
            fillColor: _subjectsCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _subjectsBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _subjectsBorder),
            ),
          ),
        );

        final addButton = FilledButton.icon(
          onPressed: _loading || _saving ? null : _addSubject,
          icon: const Icon(Icons.add),
          label: const Text('Add subject'),
          style: FilledButton.styleFrom(
            backgroundColor: _subjectsPrimary,
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 16,
            ),
          ),
        );

        if (constraints.maxWidth < 550) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 12),
              addButton,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 12),
            addButton,
          ],
        );
      },
    );
  }

  Widget _buildSubjectList(List<AdminSubject> subjects) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return _buildMessageCard(
        icon: Icons.error_outline,
        title: 'Could not load subjects',
        message: _error!,
        action: TextButton.icon(
          onPressed: _loadSubjects,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }

    if (subjects.isEmpty) {
      final searching = _searchQuery.trim().isNotEmpty;

      return _buildMessageCard(
        icon: searching ? Icons.search_off : Icons.menu_book_outlined,
        title: searching ? 'No matching subjects' : 'No subjects yet',
        message: searching
            ? 'Try a different search term.'
            : 'Add a subject to make it available for tutoring.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _subjectsCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _subjectsBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Subject name',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _subjectsMuted,
                    ),
                  ),
                ),
                Text(
                  '${subjects.length} shown',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _subjectsMuted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (var i = 0; i < subjects.length; i++) ...[
            _buildSubjectRow(subjects[i]),
            if (i != subjects.length - 1)
              const Divider(height: 1, indent: 20, endIndent: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildSubjectRow(AdminSubject subject) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 10,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _subjectsPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.book_outlined,
              size: 19,
              color: _subjectsPrimary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              subject.subjectName,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: _subjectsText,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Rename subject',
            onPressed: _saving
                ? null
                : () => _renameSubject(subject),
            icon: const Icon(Icons.edit_outlined),
            color: _subjectsPrimary,
          ),
          IconButton(
            tooltip: 'Delete subject',
            onPressed: _saving
                ? null
                : () => _deleteSubject(subject),
            icon: const Icon(Icons.delete_outline),
            color: Colors.red.shade700,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _subjectsCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _subjectsBorder),
      ),
      child: Column(
        children: [
          Icon(icon, size: 38, color: _subjectsMuted),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _subjectsText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _subjectsMuted),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action,
          ],
        ],
      ),
    );
  }
}

class _SubjectNameDialog extends StatefulWidget {
  const _SubjectNameDialog({
    required this.initialName,
    required this.isEditing,
  });

  final String initialName;
  final bool isEditing;

  @override
  State<_SubjectNameDialog> createState() => _SubjectNameDialogState();
}

class _SubjectNameDialogState extends State<_SubjectNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final name = value?.trim() ?? '';

    if (name.isEmpty) return 'Enter a subject name.';
    if (name.length > 100) return 'Maximum length is 100 characters.';

    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEditing ? 'Rename subject' : 'Add subject'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            maxLength: 100,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Subject name',
              hintText: 'e.g. Mathematics',
              border: OutlineInputBorder(),
            ),
            validator: _validate,
            onFieldSubmitted: (_) => _submit(),
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
          child: Text(widget.isEditing ? 'Save changes' : 'Add subject'),
        ),
      ],
    );
  }
}