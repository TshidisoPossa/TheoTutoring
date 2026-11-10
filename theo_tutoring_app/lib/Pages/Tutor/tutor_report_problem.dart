import 'package:flutter/material.dart';

import 'tutor_api.dart';
import 'tutor_theme.dart';

/// Sends the report (replaced in widget tests).
typedef SendTutorReport =
    Future<Map<String, dynamic>> Function({
      required String category,
      required String description,
      int? studentUserId,
    });

/// Report a Problem (tutor Profile → Support). The tutor picks a category,
/// and a student for Student issues, and describes the problem. It is saved
/// for the admin team (Report table, GET /admin/reports).
///
/// Pops with the confirmation message once the report is sent.
class TutorReportProblemPage extends StatefulWidget {
  const TutorReportProblemPage({
    super.key,
    this.loadStudents = fetchReportableStudents,
    this.sendReport = sendTutorReport,
  });

  /// Loads the students who booked this tutor (tests pass their own).
  final Future<List<Map<String, dynamic>>> Function() loadStudents;

  final SendTutorReport sendReport;

  @override
  State<TutorReportProblemPage> createState() => _TutorReportProblemPageState();
}

class _TutorReportProblemPageState extends State<TutorReportProblemPage> {
  // Same names as the backend (lib/tutor_reports.dart)
  static const _categories = [
    (
      name: 'Payments & Payouts',
      icon: Icons.payments_outlined,
      hint:
          'What went wrong with the payment? Include the lesson date and '
          'amount if you can.',
    ),
    (
      name: 'Student issues',
      icon: Icons.person_off_outlined,
      hint:
          'What happened with this student? Include the lesson date if you '
          'can.',
    ),
    (
      name: 'Other',
      icon: Icons.help_outline_rounded,
      hint: 'Tell us what went wrong.',
    ),
  ];
  static const _studentIssues = 'Student issues';
  static const _minLength = 10;
  static const _maxLength = 1000;

  static const _blue = Color(0xFF2563EB);
  static const _red = Color(0xFFDC2626);

  // Light colours, or the dark ones while dark mode is on
  bool get _dk => context.tutorDark;
  Color get _bg => _dk ? TutorDark.background : const Color(0xFFF3F4F8);
  Color get _surface => _dk ? TutorDark.card : Colors.white;
  Color get _dark => _dk ? TutorDark.text : const Color(0xFF111827);
  Color get _grey => _dk ? TutorDark.textMuted : const Color(0xFF6B7280);
  Color get _line => _dk ? TutorDark.border : const Color(0xFFE5E7EB);
  Color get _redTint => _dk ? TutorDark.redTint : const Color(0xFFFEE2E2);
  Color get _redText => _dk ? TutorDark.redText : _red;

  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();

  String? _category;
  int? _studentUserId;

  // The Student issues list, loaded the first time it is needed
  List<Map<String, dynamic>>? _students;
  bool _loadingStudents = false;
  String? _studentsError;

  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    setState(() {
      _loadingStudents = true;
      _studentsError = null;
    });
    try {
      final students = await widget.loadStudents();
      if (!mounted) return;
      setState(() => _students = students);
    } catch (e) {
      if (mounted) setState(() => _studentsError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  void _chooseCategory(String? category) {
    setState(() {
      _category = category;
      _error = null;
      if (category != _studentIssues) _studentUserId = null;
    });
    if (category == _studentIssues && _students == null && !_loadingStudents) {
      _loadStudents();
    }
  }

  Future<void> _send() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await widget.sendReport(
        category: _category!,
        description: _description.text.trim(),
        studentUserId: _category == _studentIssues ? _studentUserId : null,
      );
      if (!mounted) return;
      final message = result['message'];
      Navigator.pop(
        context,
        message is String && message.isNotEmpty
            ? message
            : 'Report sent. The admin team will look into it.',
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        surfaceTintColor: _surface,
        foregroundColor: _dark,
        elevation: 0,
        title: Text(
          'Report a Problem',
          style: TextStyle(
            color: _dark,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Tell us what went wrong. Your report goes to the '
                        'TheoTutoring admin team.',
                        style: TextStyle(color: _grey, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      _card(_buildFields()),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _errorBox(_error!),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: _sending ? null : _send,
                          style: FilledButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 18),
                          label: Text(_sending ? 'Sending…' : 'Send report'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFields() {
    final hint = _categories
        .where((c) => c.name == _category)
        .map((c) => c.hint)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('Category'),
        DropdownButtonFormField<String>(
          key: const ValueKey('report-category'),
          initialValue: _category,
          isExpanded: true,
          dropdownColor: _surface,
          decoration: _inputDecoration(hint: 'Choose a category'),
          style: TextStyle(color: _dark, fontSize: 14),
          items: [
            for (final c in _categories)
              DropdownMenuItem(
                value: c.name,
                child: Row(
                  children: [
                    Icon(c.icon, size: 20, color: _blue),
                    const SizedBox(width: 10),
                    Text(c.name),
                  ],
                ),
              ),
          ],
          onChanged: _sending ? null : _chooseCategory,
          validator: (value) => value == null ? 'Choose a category.' : null,
        ),
        if (_category == _studentIssues) ...[
          const SizedBox(height: 18),
          _label('Student'),
          _buildStudentField(),
        ],
        const SizedBox(height: 18),
        _label('Description'),
        TextFormField(
          key: const ValueKey('report-description'),
          controller: _description,
          enabled: !_sending,
          minLines: 5,
          maxLines: 8,
          maxLength: _maxLength,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: _dark, fontSize: 14),
          decoration: _inputDecoration(
            hint: hint ?? 'Choose a category, then tell us what went wrong.',
          ),
          validator: (value) => (value ?? '').trim().length < _minLength
              ? 'Describe the problem in at least $_minLength characters.'
              : null,
        ),
      ],
    );
  }

  Widget _buildStudentField() {
    if (_loadingStudents) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text('Loading your students…', style: TextStyle(color: _grey)),
          ],
        ),
      );
    }
    final error = _studentsError;
    if (error != null) {
      return Row(
        children: [
          Expanded(
            child: Text(error, style: TextStyle(color: _redText)),
          ),
          TextButton(onPressed: _loadStudents, child: const Text('Retry')),
        ],
      );
    }
    final students = _students ?? const [];
    return DropdownButtonFormField<int>(
      key: const ValueKey('report-student'),
      initialValue: _studentUserId,
      isExpanded: true,
      dropdownColor: _surface,
      decoration: _inputDecoration(
        hint: students.isEmpty
            ? 'No students have booked lessons with you yet'
            : 'Choose the student',
      ),
      style: TextStyle(color: _dark, fontSize: 14),
      items: [
        for (final s in students)
          if (s['userId'] is int)
            DropdownMenuItem(
              value: s['userId'] as int,
              child: Text(
                '${s['name'] ?? 'Student'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
      ],
      onChanged: _sending || students.isEmpty
          ? null
          : (id) => setState(() => _studentUserId = id),
      validator: (value) =>
          value == null ? 'Choose the student this report is about.' : null,
    );
  }

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        color: _dark,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  InputDecoration _inputDecoration({required String hint}) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _grey, fontSize: 14),
      hintMaxLines: 3,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(_line),
      enabledBorder: border(_line),
      disabledBorder: border(_line),
      focusedBorder: border(_blue, 1.5),
      errorBorder: border(_red),
      focusedErrorBorder: border(_red, 1.5),
      counterStyle: TextStyle(color: _grey, fontSize: 11),
    );
  }

  Widget _errorBox(String message) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _redTint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(Icons.error_outline_rounded, color: _redText, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: TextStyle(color: _redText)),
        ),
      ],
    ),
  );
}
