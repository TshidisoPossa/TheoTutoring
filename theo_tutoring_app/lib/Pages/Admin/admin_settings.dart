// Admin settings for the session rate, fixed refund policy and Firebase account.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth_gate.dart';
import 'Services/settings_services.dart';
import 'admin_access_guard.dart';
import 'admin_shell.dart';

const _surface2 = Color(0xFFF8F9FB);
const _red = Color(0xFFC62828);
const _blueBg = Color(0xFFDCE8FF);

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

// ─── Entry point ────────────────────────────────────────────────────────────
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key, this.service});

  final AdminSettingsService? service;
  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  late final AdminSettingsService _service =
      widget.service ?? AdminSettingsService();
  late final bool _ownsService = widget.service == null;
  _SettingsSection _section = _SettingsSection.sessionRate;

  @override
  void dispose() {
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  void _select(_SettingsSection s) => setState(() => _section = s);

  @override
  Widget build(BuildContext context) {
    final body = _SettingsBody(
      section: _section,
      service: _service,
      onOpenRefunds: () =>
          Navigator.pushReplacementNamed(context, AdminRoutes.refunds),
    );
    return AdminShell(
      currentRoute: AdminRoutes.settings,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Vertical section menu on wide screens, chip row on narrow ones.
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsChips(current: _section, onSelect: _select),
                Expanded(child: body),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsNav(current: _section, onSelect: _select),
              Expanded(child: body),
            ],
          );
        },
      ),
    );
  }
}

// ─── Section enum ───────────────────────────────────────────────────────────
enum _SettingsSection {
  sessionRate(Icons.payments_outlined, 'Session Rate'),
  refundPolicy(Icons.receipt_long_outlined, 'Refund Policy'),
  account(Icons.person_outline, 'Account');

  const _SettingsSection(this.icon, this.label);
  final IconData icon;
  final String label;
}

// ─── Settings left-nav ──────────────────────────────────────────────────────
class _SettingsNav extends StatelessWidget {
  final _SettingsSection current;
  final ValueChanged<_SettingsSection> onSelect;
  const _SettingsNav({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(12, 24, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final s in _SettingsSection.values) _navItem(s)],
      ),
    );
  }

  Widget _navItem(_SettingsSection s) {
    final active = current == s;
    final color = active ? AdminColors.primary : AdminColors.textMuted;
    return InkWell(
      onTap: () => onSelect(s),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: active ? AdminColors.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(s.icon, size: 16, color: color),
            const SizedBox(width: 9),
            Text(
              s.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Settings chip row (narrow screens) ─────────────────────────────────────
class _SettingsChips extends StatelessWidget {
  final _SettingsSection current;
  final ValueChanged<_SettingsSection> onSelect;
  const _SettingsChips({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          for (final s in _SettingsSection.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(s.icon, size: 16, color: AdminColors.primary),
                label: Text(s.label),
                selected: current == s,
                onSelected: (_) => onSelect(s),
                showCheckmark: false,
                selectedColor: AdminColors.selected,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AdminColors.border),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Settings body router ───────────────────────────────────────────────────
class _SettingsBody extends StatelessWidget {
  final _SettingsSection section;
  final AdminSettingsService service;
  final VoidCallback onOpenRefunds;
  const _SettingsBody({
    required this.section,
    required this.service,
    required this.onOpenRefunds,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PageTitle(),
              switch (section) {
                _SettingsSection.sessionRate => _SessionRateSection(
                  service: service,
                ),
                _SettingsSection.refundPolicy => _RefundPolicySection(
                  onOpenRefunds: onOpenRefunds,
                ),
                _SettingsSection.account => _AccountSection(service: service),
              },
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION: SESSION RATE
// ═══════════════════════════════════════════════════════════════════════════
class _SessionRateSection extends StatefulWidget {
  const _SessionRateSection({required this.service});

  final AdminSettingsService service;

  @override
  State<_SessionRateSection> createState() => _SessionRateSectionState();
}

class _SessionRateSectionState extends State<_SessionRateSection> {
  final _amount = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _current;
  bool _canRead = false;
  bool _canWrite = false;
  bool _loadStarted = false;
  int _loadGeneration = 0;

  // Permissions come from the verified AdminPermissionScope; no scope means
  // no access. The rate is only requested once read access is confirmed.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AdminPermissionScope.maybeOf(context);
    _canRead = scope?.has('admin.settings.rate.read') ?? false;
    _canWrite = _canRead && scope!.has('admin.settings.rate.write');
    if (_canRead) {
      if (!_loadStarted) {
        _loadStarted = true;
        _load();
      }
    } else {
      _loadStarted = false;
      _loadGeneration++;
      _loading = false;
      _current = null;
      _error = null;
      _amount.clear();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.service.fetchSessionRate();
      if (!mounted || !_canRead || generation != _loadGeneration) return;
      setState(() {
        _current = result['current'] as Map<String, dynamic>?;
        _amount.text = _current?['amount']?.toString() ?? '';
        _loading = false;
      });
    } catch (error) {
      if (!mounted || !_canRead || generation != _loadGeneration) return;
      setState(() {
        _error = _msg(error);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_canWrite) return;
    final value = _amount.text.trim();
    if (!RegExp(r'^\d{1,8}(?:\.\d{1,2})?$').hasMatch(value) ||
        double.tryParse(value) == null ||
        double.parse(value) <= 0) {
      setState(
        () => _error = 'Enter a positive amount with up to two decimals.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.service.updateSessionRate(value);
      if (!mounted) return;
      setState(() {
        _current = result['current'] as Map<String, dynamic>?;
        _amount.text = _current?['amount']?.toString() ?? value;
        _saving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Session rate updated.')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _msg(error);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _SettingsCard(
    title: 'Session Rate',
    subtitle: 'The fixed price students pay for one tutoring session',
    children: [
      if (!_canRead)
        const Text(
          'Access restricted: your administrator role cannot view the session rate.',
          style: TextStyle(fontSize: 13, color: AdminColors.textDark),
        )
      else if (_loading)
        const Center(child: CircularProgressIndicator())
      else if (_error != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!, style: const TextStyle(color: _red)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        )
      else ...[
        Text(
          _current == null
              ? 'No current rate is configured. Ask the database administrator to provision approved platform settings.'
              : 'Current rate: R ${_current!['amount']} · Updated ${_current!['effectiveFrom']} · Set by ${_current!['setBy'] ?? 'not recorded'}',
          style: const TextStyle(fontSize: 13, color: AdminColors.textDark),
        ),
        const SizedBox(height: 12),
        if (_canWrite) ...[
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'New session rate (R)',
              helperText:
                  'Updates the shared rate used when new bookings are priced.',
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _saving || _current == null ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Update session rate'),
            ),
          ),
        ],
      ],
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION: REFUND POLICY (read-only, documentation 4.6)
// ═══════════════════════════════════════════════════════════════════════════
class _RefundPolicySection extends StatelessWidget {
  final VoidCallback onOpenRefunds;
  const _RefundPolicySection({required this.onOpenRefunds});

  static const _rules = [
    ('48 hours or more before the session', '100% refund'),
    ('24 hours or more, but less than 48 hours', '50% refund'),
    ('Less than 24 hours before the session', 'No refund'),
    (
      'Exceptional circumstances',
      'Administrator may approve an alternative refund',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Cancellation & Refund Policy',
      subtitle: 'Applied automatically when a student cancels. This policy is fixed and cannot be edited here.',
      trailing: const _StatusPill(
        label: 'Fixed',
        color: AdminColors.primary,
        bg: _blueBg,
      ),
      children: [
        for (final r in _rules)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                r.$1,
                style: const TextStyle(
                  fontSize: 13,
                  color: AdminColors.textDark,
                ),
              ),
              Text(
                r.$2,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AdminColors.textDark,
                ),
              ),
            ],
          ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _surface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AdminColors.border),
          ),
          child: const Text(
            'A cancellation exactly 48 hours before the session receives a full '
            'refund, and exactly 24 hours before receives 50%. Unpaid bookings are '
            'simply cancelled. Every refund is recorded, including whether an '
            'administrator overrode the calculated amount.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AdminColors.textMuted,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            onPressed: onOpenRefunds,
            child: const Text('Review refund requests'),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION: ACCOUNT (Firebase Authentication)
// ═══════════════════════════════════════════════════════════════════════════
class _AccountSection extends StatefulWidget {
  final AdminSettingsService service;
  const _AccountSection({required this.service});

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  bool _sending = false;
  bool _changingPassword = false;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendReset(String email) async {
    setState(() => _sending = true);
    try {
      await widget.service.sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset link sent to $email.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _red,
          content: Text('Could not send the reset email: ${_msg(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _changePassword() async {
    final current = _currentPasswordController.text;
    final next = _newPasswordController.text;
    if (current.isEmpty || next.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter your current password and a new password of at least 6 characters.',
          ),
        ),
      );
      return;
    }
    if (next != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The new passwords do not match.')),
      );
      return;
    }

    setState(() => _changingPassword = true);
    try {
      await widget.service.changePassword(
        currentPassword: current,
        newPassword: next,
      );
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _red,
          content: Text('Could not change the password: ${_msg(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  Future<void> _logOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to sign in again to use the admin dashboard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _red),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.service.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    return _SettingsCard(
      title: 'Your Account',
      subtitle: 'Sign-in and passwords are managed by Firebase Authentication',
      children: [
        _FormRow(
          label: 'Name',
          child: Text(
            (user?.displayName?.trim().isNotEmpty ?? false)
                ? user!.displayName!
                : '—',
            style: const TextStyle(fontSize: 13, color: AdminColors.textDark),
          ),
        ),
        _FormRow(
          label: 'Email',
          child: Text(
            email ?? 'Not signed in',
            style: const TextStyle(fontSize: 13, color: AdminColors.textDark),
          ),
        ),
        _FormRow(
          label: 'Password',
          hint: 'Re-enter your current password to confirm the change',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _currentPasswordController,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _changingPassword ? null : _changePassword,
                  child: _changingPassword
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Change password'),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: email == null || _sending
                      ? null
                      : () => _sendReset(email),
                  child: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send password reset email'),
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _logOut,
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Log Out'),
            style: FilledButton.styleFrom(backgroundColor: _red),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _PageTitle extends StatelessWidget {
  const _PageTitle();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: AdminColors.textDark,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Review the refund policy and manage your account.',
            style: TextStyle(fontSize: 14, color: AdminColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title, subtitle;
  final Widget? trailing;
  final List<Widget> children;
  const _SettingsCard({
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AdminColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AdminColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdminColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    const Divider(color: AdminColors.border, height: 24),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  final String label;
  final String? hint;
  final Widget child;
  const _FormRow({required this.label, this.hint, required this.child});

  @override
  Widget build(BuildContext context) {
    final labelColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AdminColors.textDark,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(
            hint!,
            style: const TextStyle(fontSize: 11, color: AdminColors.textMuted),
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Label above the field when there isn't room for both side by side.
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelColumn, const SizedBox(height: 8), child],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 200, child: labelColumn),
            const SizedBox(width: 16),
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: child),
            ),
          ],
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _StatusPill({
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
