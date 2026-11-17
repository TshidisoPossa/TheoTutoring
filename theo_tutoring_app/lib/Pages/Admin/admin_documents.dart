import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_shell.dart';

/// One uploaded file an admin can open: [label] ("ID document") and the
/// Cloudinary [url] saved when it was uploaded (null if never uploaded).
typedef AdminDocument = ({String label, String? url});

/// The Documents section of an admin overview (tutors and students): one
/// "View ..." button per uploaded file, opened in the browser or the
/// phone's viewer, and "not provided" for files that were never uploaded.
class AdminDocumentLinks extends StatelessWidget {
  const AdminDocumentLinks({
    required this.documents,
    this.openUrl,
    super.key,
  });

  final List<AdminDocument> documents;

  /// Opens a link; tests pass a fake. Defaults to url_launcher.
  final Future<bool> Function(Uri uri)? openUrl;

  static bool _isOpenable(String? url) {
    final uri = url == null ? null : Uri.tryParse(url.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await (openUrl ?? launchUrl)(Uri.parse(url.trim()));
    if (!opened) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not open this document.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Documents',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AdminColors.textDark,
        ),
      ),
      const SizedBox(height: 6),
      for (final doc in documents)
        if (_isOpenable(doc.url))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _open(context, doc.url!),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text('View ${doc.label}'),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.remove_circle_outline,
                  size: 18,
                  color: AdminColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${doc.label}: not provided',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AdminColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
    ],
  );
}
