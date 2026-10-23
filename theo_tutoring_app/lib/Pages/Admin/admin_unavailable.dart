// Placeholder for Admin sidebar sections that have not been built yet
// (Students, Tutors, Subjects, Reviews, Payouts, Reports). It keeps the shared
// AdminShell around it so the sidebar highlights the section and the admin can
// move on to another area.

import 'package:flutter/material.dart';

import 'Services/admin_access_service.dart';
import 'admin_shell.dart';

class AdminSectionUnavailableScreen extends StatefulWidget {
  const AdminSectionUnavailableScreen({
    super.key,
    required this.currentRoute,
    required this.title,
    this.loadAccess,
  });

  /// The sidebar route this page stands in for, so it is highlighted.
  final String currentRoute;
  final String title;

  /// Supplies the signed-in admin's name for the top bar; injectable for tests.
  final Future<AdminAccessResult> Function()? loadAccess;

  @override
  State<AdminSectionUnavailableScreen> createState() =>
      _AdminSectionUnavailableScreenState();
}

class _AdminSectionUnavailableScreenState
    extends State<AdminSectionUnavailableScreen> {
  String? _adminName;

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  // The route guard has already verified access; this only fills the top bar.
  Future<void> _loadName() async {
    try {
      final access = await (widget.loadAccess ??
          () => AdminAccessService().checkCurrentUser())();
      if (mounted && access.isAllowed) {
        setState(() => _adminName = access.adminName);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      currentRoute: widget.currentRoute,
      adminName: _adminName,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textDark,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 48,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminColors.border),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AdminColors.selected,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.construction_outlined,
                          color: AdminColors.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "This section isn't available yet",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AdminColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${widget.title} is still being built. Use the '
                        'sidebar to open another area.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AdminColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => Navigator.pushReplacementNamed(
                          context,
                          AdminRoutes.dashboard,
                        ),
                        child: const Text('Back to Dashboard'),
                      ),
                    ],
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
