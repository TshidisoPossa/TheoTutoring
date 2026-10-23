import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'Services/tutapplication_services.dart';
import 'admin_shell.dart';
import 'models/Tutapplication.dart';

class AdminApplicationReviewScreen extends StatefulWidget {
  const AdminApplicationReviewScreen({super.key, required this.application});

  final TutorApplication? application;

  @override
  State<AdminApplicationReviewScreen> createState() =>
      _AdminApplicationReviewScreenState();
}

class _AdminApplicationReviewScreenState
    extends State<AdminApplicationReviewScreen> {
  final _service = AdminApplicationsService();
  final _feedback = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _decide(String decision) async {
    final application = widget.application;
    if (application == null || _submitting) return;
    if (decision == 'reject' && _feedback.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add feedback before rejecting.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await _service.reviewApplication(
        applicationId: application.id,
        decision: decision,
        feedback: _feedback.text.trim().isEmpty ? null : _feedback.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openDocument(String? value) async {
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This document link is unavailable.')),
      );
      return;
    }
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this document.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final application = widget.application;
    return AdminShell(
      currentRoute: AdminRoutes.applications,
      child: application == null
          ? const Center(child: Text('Application details are unavailable.'))
          : _buildApplication(application),
    );
  }

  Widget _buildApplication(
    TutorApplication application,
  ) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to applications'),
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
            ),
            const SizedBox(height: 12),
            Text(
              application.fullName,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AdminColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text('Application #${application.id}  •  ${application.status}'),
            const SizedBox(height: 24),
            _section('Applicant details', [
              _detail('Email', application.email),
              _detail('Phone', application.phone),
              _detail('Applied', application.appliedAt.toLocal().toString()),
              _detail('Experience', application.experience),
              _detail('Bio', application.bio),
            ]),
            const SizedBox(height: 16),
            _section(
              'Qualifications',
              application.qualifications.isEmpty
                  ? const [Text('No qualifications were provided.')]
                  : application.qualifications
                        .map((qualification) => Text('• $qualification'))
                        .toList(),
            ),
            const SizedBox(height: 16),
            _section(
              'Subjects',
              application.subjects.isEmpty
                  ? const [Text('No subjects were provided.')]
                  : application.subjects
                        .map((subject) => Text('• $subject'))
                        .toList(),
            ),
            const SizedBox(height: 16),
            _section('Uploaded documents', [
              _documentButton(
                'Qualification certificate',
                application.certificateUrl,
              ),
              _documentButton('Identity document', application.idDocumentUrl),
              if (application.certificateUrl == null &&
                  application.idDocumentUrl == null)
                const Text('No document URLs are stored for this application.'),
            ]),
            if (application.status.toLowerCase() == 'pending') ...[
              const SizedBox(height: 20),
              TextField(
                controller: _feedback,
                maxLength: 2000,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Reviewer feedback',
                  hintText: 'Required when rejecting an application',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: _submitting ? null : () => _decide('reject'),
                    child: const Text('Reject'),
                  ),
                  FilledButton.icon(
                    onPressed: _submitting ? null : () => _decide('approve'),
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 16),
              _section('Review record', [
                _detail('Reviewed by', application.reviewerName),
                _detail('Reviewed at', application.reviewedAt),
                _detail('Feedback', application.adminFeedback),
              ]),
              const SizedBox(height: 12),
              const Text(
                'This application has already been reviewed.',
                textAlign: TextAlign.right,
                style: TextStyle(color: AdminColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget _detail(String label, String? value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      '$label: ${value?.isNotEmpty == true ? value : 'Not provided'}',
    ),
  );

  Widget _documentButton(String label, String? url) {
    if (url == null || url.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('$label: not provided'),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _openDocument(url),
        icon: const Icon(Icons.open_in_new),
        label: Text('View $label'),
      ),
    );
  }
}
