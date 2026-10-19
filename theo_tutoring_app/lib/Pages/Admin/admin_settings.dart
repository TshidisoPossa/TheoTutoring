// Admin settings. Per the project documentation the administrator sets the
// fixed session rate (2.3, business rule 6, FR27, SessionRate table in 11.1);
// the refund policy is fixed (4.6) and is shown read-only; sign-in and password
// resets are handled by Firebase Authentication (4.1, 12.1).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../login_page.dart';
import 'models/session_rate_models.dart';
import 'Services/settings_services.dart';
import 'admin_shell.dart';

const _fieldFill = Color(0xFFF3F4F6);
const _surface2 = Color(0xFFF8F9FB);
const _green = Color(0xFF1B7F3A);
const _greenBg = Color(0xFFD9F5E0);
const _amber = Color(0xFFB45309);
const _amberBg = Color(0xFFFDEBD0);
const _red = Color(0xFFC62828);
const _blueBg = Color(0xFFDCE8FF);

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

// ─── Entry point ────────────────────────────────────────────────────────────
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});
  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _service = AdminSettingsService();
  _SettingsSection _section = _SettingsSection.sessionRate;
  String? _adminName;

  void _select(_SettingsSection s) => setState(() => _section = s);

  @override
  Widget build(BuildContext context) {
    final body = _SettingsBody(
      section: _section,
      service: _service,
      onAdminName: (name) {
        if (name != _adminName) setState(() => _adminName = name);
      },
      onOpenRefunds: () =>
          Navigator.pushReplacementNamed(context, AdminRoutes.refunds),
    );
    return AdminShell(
      currentRoute: AdminRoutes.settings,
      adminName: _adminName,
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
  final ValueChanged<String> onAdminName;
  final VoidCallback onOpenRefunds;
  const _SettingsBody({
    required this.section,
    required this.service,
    required this.onAdminName,
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
                  onAdminName: onAdminName,
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
  final AdminSettingsService service;
  final ValueChanged<String> onAdminName;
  const _SessionRateSection({required this.service, required this.onAdminName});

  @override
  State<_SessionRateSection> createState() => _SessionRateSectionState();
}

class _SessionRateSectionState extends State<_SessionRateSection> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  DateTime _effectiveFrom = DateUtils.dateOnly(DateTime.now());

  SessionRateResult? _result;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.service.fetchSessionRate();
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
      if (result.adminName.isNotEmpty) widget.onAdminName(result.adminName);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _msg(e);
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveFrom.isBefore(today) ? today : _effectiveFrom,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Rate applies to bookings from',
    );
    if (picked != null) setState(() => _effectiveFrom = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amount.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set new session rate?'),
        content: Text(
          'New bookings from ${formatRateDate(_effectiveFrom)} will cost '
          '${formatRand(amount)} per session. Existing bookings keep the rate '
          'they were made at.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Set Rate'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await widget.service.setSessionRate(amount, _effectiveFrom);
      if (!mounted) return;
      _amount.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session rate saved.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _red,
          content: Text('Could not save the rate: ${_msg(e)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _result == null) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _result == null) {
      return _SettingsCard(
        title: 'Session Rate',
        subtitle: 'The fixed price students pay for one tutoring session',
        children: [
          Column(
            children: [
              const Text('Could not load the session rate.'),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AdminColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ],
      );
    }

    final result = _result!;
    final current = result.current;
    final scheduled = result.history.where((r) => r.isScheduled).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsCard(
          title: 'Current Session Rate',
          subtitle:
              'Applies to every new booking. Tutors cannot set their own prices.',
          children: [
            if (current == null)
              const Text(
                'No session rate has been set yet. Students cannot be charged '
                'until a rate is set below.',
                style: TextStyle(color: _red, fontSize: 13),
              )
            else
              Wrap(
                spacing: 24,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Text(
                    formatRand(current.amount),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.textDark,
                    ),
                  ),
                  Text(
                    'per session · since ${formatRateDate(current.effectiveFrom)}'
                    '${current.setBy == null ? '' : ' · set by ${current.setBy}'}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AdminColors.textMuted,
                    ),
                  ),
                ],
              ),
            for (final rate in scheduled)
              Row(
                children: [
                  const _StatusPill(label: 'Scheduled', color: _amber, bg: _amberBg),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${formatRand(rate.amount)} from ${formatRateDate(rate.effectiveFrom)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AdminColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 20),
        _SettingsCard(
          title: 'Set a New Rate',
          subtitle:
              'Previous rates are kept so past payments still match what was charged.',
          children: [
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FormRow(
                    label: 'Amount (ZAR)',
                    hint: 'Price of one session',
                    child: SizedBox(
                      width: 200,
                      child: TextFormField(
                        controller: _amount,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                        decoration: _inputDecoration(prefix: 'R '),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AdminColors.textDark,
                        ),
                        validator: (v) {
                          final n = double.tryParse(v?.trim() ?? '');
                          if (n == null) return 'Enter an amount.';
                          if (n <= 0) return 'The rate must be more than R0.';
                          return null;
                        },
                      ),
                    ),
                  ),
                  const Divider(color: AdminColors.border, height: 24),
                  _FormRow(
                    label: 'Effective From',
                    hint: 'First day new bookings use this rate',
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(formatRateDate(_effectiveFrom)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminColors.textDark,
                        side: const BorderSide(color: AdminColors.border),
                      ),
                    ),
                  ),
                  const Divider(color: AdminColors.border, height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AdminColors.primary,
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
                          : const Text('Save Rate'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SettingsCard(
          title: 'Rate History',
          subtitle: 'Every rate that has been set, newest first',
          children: [
            if (result.history.isEmpty)
              const Text(
                'No rates recorded yet.',
                style: TextStyle(color: AdminColors.textMuted, fontSize: 13),
              )
            else
              for (final rate in result.history)
                _RateHistoryRow(
                  rate: rate,
                  isCurrent: rate.id == current?.id,
                ),
          ],
        ),
      ],
    );
  }
}

class _RateHistoryRow extends StatelessWidget {
  final SessionRate rate;
  final bool isCurrent;
  const _RateHistoryRow({required this.rate, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            formatRand(rate.amount),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AdminColors.textDark,
            ),
          ),
        ),
        SizedBox(
          width: 160,
          child: Text(
            'From ${formatRateDate(rate.effectiveFrom)}',
            style: const TextStyle(fontSize: 12.5, color: AdminColors.textMuted),
          ),
        ),
        if (rate.setBy != null)
          Text(
            'Set by ${rate.setBy}',
            style: const TextStyle(fontSize: 12.5, color: AdminColors.textMuted),
          ),
        if (isCurrent)
          const _StatusPill(label: 'Current', color: _green, bg: _greenBg)
        else if (rate.isScheduled)
          const _StatusPill(label: 'Scheduled', color: _amber, bg: _amberBg),
      ],
    );
  }
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
    ('Exceptional circumstances', 'Administrator may approve an alternative refund'),
  ];

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      title: 'Cancellation & Refund Policy',
      subtitle:
          'Applied automatically when a student cancels. This policy is fixed and cannot be edited here.',
      trailing: const _StatusPill(label: 'Fixed', color: AdminColors.primary, bg: _blueBg),
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

  Future<void> _logOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to use the admin dashboard.'),
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
      MaterialPageRoute(builder: (_) => const LoginPage()),
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
          hint: 'We email you a secure link to choose a new one',
          child: Align(
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

InputDecoration _inputDecoration({String? prefix}) => InputDecoration(
  isDense: true,
  prefixText: prefix,
  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  filled: true,
  fillColor: _fieldFill,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: AdminColors.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: AdminColors.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: const BorderSide(color: AdminColors.primary),
  ),
);

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
            'Manage the session rate, review the refund policy and your account.',
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
