import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Colours ────────────────────────────────────────────────────────────────
const _bg = Color(0xFF0D1117);
const _surface = Color(0xFF161B22);
const _surface2 = Color(0xFF1C2330);
const _border = Color(0xFF30363D);
const _accent = Color(0xFF1457D9);
const _fg = Color(0xFFE6EDF3);
const _fg2 = Color(0xFF8B949E);
const _fg3 = Color(0xFF484F58);
const _green = Color(0xFF3FB950);
const _red = Color(0xFFF85149);
const _yellow = Color(0xFFD29922);
const _avatarBg = Color(0xFFD0E4FF);

// ─── Entry point ────────────────────────────────────────────────────────────
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});
  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  _SettingsSection _section = _SettingsSection.general;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Row(
        children: [
          _Sidebar(current: 'Settings'),
          Expanded(
            child: Column(
              children: [
                const _TopBar(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingsNav(
                        current: _section,
                        onSelect: (s) => setState(() => _section = s),
                      ),
                      Expanded(child: _SettingsBody(section: _section)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section enum ───────────────────────────────────────────────────────────
enum _SettingsSection { general, notifications, roles, security, integrations, danger }

// ─── Settings left-nav ──────────────────────────────────────────────────────
class _SettingsNav extends StatelessWidget {
  final _SettingsSection current;
  final ValueChanged<_SettingsSection> onSelect;
  const _SettingsNav({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      color: _bg,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _navItem(_SettingsSection.general, Icons.settings_outlined, 'General'),
          _navItem(_SettingsSection.notifications, Icons.notifications_outlined, 'Notifications'),
          _navItem(_SettingsSection.roles, Icons.group_outlined, 'Roles & Permissions'),
          _navItem(_SettingsSection.security, Icons.shield_outlined, 'Security'),
          _navItem(_SettingsSection.integrations, Icons.link_outlined, 'Integrations'),
          _navItem(_SettingsSection.danger, Icons.warning_amber_rounded, 'Danger Zone', danger: true),
        ],
      ),
    );
  }

  Widget _navItem(_SettingsSection s, IconData icon, String label, {bool danger = false}) {
    final active = current == s;
    final color = danger ? _red : (active ? _accent : _fg2);
    return GestureDetector(
      onTap: () => onSelect(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _accent.withOpacity(.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 9),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.normal, color: color)),
          ],
        ),
      ),
    );
  }
}

// ─── Settings body router ───────────────────────────────────────────────────
class _SettingsBody extends StatelessWidget {
  final _SettingsSection section;
  const _SettingsBody({required this.section});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: switch (section) {
        _SettingsSection.general       => const _GeneralSection(),
        _SettingsSection.notifications => const _NotificationsSection(),
        _SettingsSection.roles         => const _RolesSection(),
        _SettingsSection.security      => const _SecuritySection(),
        _SettingsSection.integrations  => const _IntegrationsSection(),
        _SettingsSection.danger        => const _DangerSection(),
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION: GENERAL
// ═══════════════════════════════════════════════════════════════════════════
class _GeneralSection extends StatefulWidget {
  const _GeneralSection();
  @override
  State<_GeneralSection> createState() => _GeneralSectionState();
}

class _GeneralSectionState extends State<_GeneralSection> {
  bool recurringEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(title: 'Settings', subtitle: 'Manage platform configuration, permissions, and integrations.'),
        _SettingsCard(
          title: 'Platform Information',
          subtitle: 'Basic details about your tutoring platform',
          children: [
            _FormRow(label: 'Platform Name', hint: 'Shown across the app and emails', child: _textField('TheoTutoring')),
            _FormRow(label: 'Support Email', hint: 'Receives user queries and reports', child: _textField('support@theotutoring.co.za')),
            _FormRow(label: 'Default Currency', child: _dropdownField(['ZAR — South African Rand', 'USD — US Dollar', 'EUR — Euro'], 0)),
            _FormRow(label: 'Timezone', child: _dropdownField(['Africa/Johannesburg (UTC+2)', 'UTC', 'America/New_York'], 0)),
            _FormRow(label: 'Description', hint: 'Short description for listings',
              child: _textField("South Africa's peer-to-peer tutoring platform.", maxLines: 3)),
            const SizedBox(height: 4),
            _SaveRow(),
          ],
        ),
        const SizedBox(height: 20),
        _SettingsCard(
          title: 'Session & Booking Rules',
          subtitle: 'Control how tutoring sessions are scheduled',
          children: [
            _FormRow(label: 'Min Session Duration', hint: 'In minutes', child: _textField('30', width: 100)),
            _FormRow(label: 'Max Session Duration', hint: 'In minutes', child: _textField('120', width: 100)),
            _FormRow(label: 'Cancellation Window', hint: 'Hours before session for free cancel', child: _textField('24', width: 100)),
            _ToggleRow(
              title: 'Allow Recurring Sessions',
              hint: 'Students can book weekly repeat sessions',
              value: recurringEnabled,
              onChanged: (v) => setState(() => recurringEnabled = v),
            ),
            _SaveRow(),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION: NOTIFICATIONS
// ═══════════════════════════════════════════════════════════════════════════
class _NotificationsSection extends StatefulWidget {
  const _NotificationsSection();
  @override
  State<_NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<_NotificationsSection> {
  final Map<String, bool> emailToggles = {
    'New Tutor Application': true,
    'New Dispute Filed': true,
    'Payout Processed': false,
    'High Error Rate Alert': true,
    'Weekly Summary Report': true,
  };
  final Map<String, bool> pushToggles = {
    'Real-time Dispute Alerts': true,
    'System Downtime Alerts': true,
  };
  final Map<String, String> hints = {
    'New Tutor Application': 'When a new tutor submits an application for review',
    'New Dispute Filed': 'When a student or tutor opens a refund or issue ticket',
    'Payout Processed': 'Confirmation when a tutor payout batch completes',
    'High Error Rate Alert': 'When platform error rate exceeds 1% threshold',
    'Weekly Summary Report': 'Automated Monday morning digest of key metrics',
    'Real-time Dispute Alerts': 'Push immediately when a dispute needs action',
    'System Downtime Alerts': 'Push when uptime drops below 99.5%',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(title: 'Settings', subtitle: 'Manage platform configuration, permissions, and integrations.'),
        _SettingsCard(
          title: 'Email Notifications',
          subtitle: 'Choose which events trigger admin email alerts',
          children: [
            ...emailToggles.entries.map((e) => _ToggleRow(
              title: e.key,
              hint: hints[e.key] ?? '',
              value: e.value,
              onChanged: (v) => setState(() => emailToggles[e.key] = v),
            )),
            _SaveRow(label: 'Save Preferences'),
          ],
        ),
        const SizedBox(height: 20),
        _SettingsCard(
          title: 'Push Notifications',
          subtitle: 'In-app and mobile push alert settings',
          children: [
            ...pushToggles.entries.map((e) => _ToggleRow(
              title: e.key,
              hint: hints[e.key] ?? '',
              value: e.value,
              onChanged: (v) => setState(() => pushToggles[e.key] = v),
            )),
            _SaveRow(label: 'Save Preferences'),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION: ROLES
// ═══════════════════════════════════════════════════════════════════════════
class _RolesSection extends StatelessWidget {
  const _RolesSection();

  static const roles = [
    ('Super User', 'Super Admin', 'Full platform access including danger-zone actions and billing', _red),
    ('Admin', 'Platform Admin', 'Manage users, content, disputes, and payouts', _accent),
    ('Support', 'Support Agent', 'View and resolve disputes and refund tickets only', _yellow),
    ('Viewer', 'Read-Only Viewer', 'View dashboards and reports, no write access', _green),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(title: 'Settings', subtitle: 'Manage platform configuration, permissions, and integrations.'),
        _SettingsCard(
          title: 'Admin Roles',
          subtitle: 'Define what each admin role can access and do',
          trailing: _SmallButton(label: '+ New Role', onTap: () {}),
          children: roles.map((r) => _RoleRow(badge: r.$1, name: r.$2, desc: r.$3, color: r.$4)).toList(),
        ),
      ],
    );
  }
}

class _RoleRow extends StatelessWidget {
  final String badge, name, desc;
  final Color color;
  const _RoleRow({required this.badge, required this.name, required this.desc, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: color.withOpacity(.15), borderRadius: BorderRadius.circular(20)),
            child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _fg))),
          Expanded(flex: 2, child: Text(desc, style: const TextStyle(fontSize: 12, color: _fg2))),
          _SmallButton(label: 'Edit', onTap: () {}),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION: SECURITY
// ═══════════════════════════════════════════════════════════════════════════
class _SecuritySection extends StatefulWidget {
  const _SecuritySection();
  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  bool twoFA = true;
  bool auditLog = true;
  bool ipAllowlist = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(title: 'Settings', subtitle: 'Manage platform configuration, permissions, and integrations.'),
        _SettingsCard(
          title: 'Authentication',
          subtitle: 'Login and session security settings',
          children: [
            _ToggleRow(title: 'Two-Factor Authentication (2FA)', hint: 'Require 2FA for all admin accounts', value: twoFA, onChanged: (v) => setState(() => twoFA = v)),
            _FormRow(label: 'Session Timeout', hint: 'Auto-logout after inactivity (minutes)', child: _textField('60', width: 100)),
            _FormRow(label: 'Password Policy', child: _dropdownField([
              'Strong (min 12 chars, symbols required)',
              'Medium (min 8 chars, mixed case)',
              'Basic (min 6 chars)',
            ], 1)),
            _ToggleRow(title: 'IP Allowlist', hint: 'Restrict admin login to specific IP addresses', value: ipAllowlist, onChanged: (v) => setState(() => ipAllowlist = v)),
            _SaveRow(),
          ],
        ),
        const SizedBox(height: 20),
        _SettingsCard(
          title: 'Audit Log',
          subtitle: 'Track all admin actions for compliance',
          trailing: _StatusPill(label: 'Active', color: _green),
          children: [
            _ToggleRow(title: 'Log All Admin Actions', hint: 'Records every write action with timestamp and user', value: auditLog, onChanged: (v) => setState(() => auditLog = v)),
            _FormRow(label: 'Log Retention', child: _dropdownField(['30 days', '90 days', '1 year', 'Forever'], 1)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _SmallButton(label: 'Export Logs', onTap: () {}),
                const SizedBox(width: 10),
                _SmallButton(label: 'Save Changes', primary: true, onTap: () {}),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION: INTEGRATIONS
// ═══════════════════════════════════════════════════════════════════════════
class _IntegrationsSection extends StatefulWidget {
  const _IntegrationsSection();
  @override
  State<_IntegrationsSection> createState() => _IntegrationsSectionState();
}

class _IntegrationsSectionState extends State<_IntegrationsSection> {
  bool sandboxMode = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(title: 'Settings', subtitle: 'Manage platform configuration, permissions, and integrations.'),
        _SettingsCard(
          title: 'API Keys',
          subtitle: 'Keys for third-party integrations',
          trailing: _SmallButton(label: '+ Generate Key', onTap: () {}),
          children: [
            _FormRow(label: 'Live API Key', hint: 'Production environment',
              child: _ApiKeyField(maskedKey: 'tt_live_••••••••••••••••••••8f2a')),
            _FormRow(label: 'Test API Key', hint: 'Sandbox environment',
              child: _ApiKeyField(maskedKey: 'tt_test_••••••••••••••••••••3c91')),
          ],
        ),
        const SizedBox(height: 20),
        _SettingsCard(
          title: 'Payment Gateway',
          subtitle: 'Configure PayFast / Stripe integration',
          trailing: const _StatusPill(label: 'Connected', color: _green),
          children: [
            _FormRow(label: 'Provider', child: _dropdownField(['PayFast (ZAR)', 'Stripe', 'Peach Payments'], 0)),
            _FormRow(label: 'Merchant ID', child: _textField('10034582')),
            _ToggleRow(title: 'Sandbox Mode', hint: 'Process test payments only — disable for live', value: sandboxMode, onChanged: (v) => setState(() => sandboxMode = v)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _SmallButton(label: 'Test Connection', onTap: () {}),
                const SizedBox(width: 10),
                _SmallButton(label: 'Save Changes', primary: true, onTap: () {}),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _ApiKeyField extends StatelessWidget {
  final String maskedKey;
  const _ApiKeyField({required this.maskedKey});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: _border)),
            child: Text(maskedKey, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: _fg2, letterSpacing: .05)),
          ),
        ),
        const SizedBox(width: 8),
        _SmallButton(label: 'Reveal', onTap: () {}),
        const SizedBox(width: 6),
        _SmallButton(label: 'Copy', onTap: () {
          Clipboard.setData(ClipboardData(text: maskedKey));
        }),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION: DANGER ZONE
// ═══════════════════════════════════════════════════════════════════════════
class _DangerSection extends StatelessWidget {
  const _DangerSection();

  static const actions = [
    ('Clear All Cached Data', 'Removes all server-side caches. The platform will be slow for a few minutes while it rebuilds.', 'Clear Cache'),
    ('Suspend New Registrations', 'Temporarily prevents new students and tutors from signing up.', 'Suspend'),
    ('Export All User Data', 'Download a full data export (POPIA compliance). This may take several minutes.', 'Export Data'),
    ('Delete Platform', 'Permanently delete all data and shut down this platform. This cannot be undone.', 'Delete Platform'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(title: 'Settings', subtitle: 'Manage platform configuration, permissions, and integrations.'),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _red.withOpacity(.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _red.withOpacity(.2)))),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('⚠ Danger Zone', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _red)),
                    SizedBox(height: 2),
                    Text('These actions are irreversible. Proceed with caution.', style: TextStyle(fontSize: 12, color: _fg2)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: actions.map((a) => _DangerActionRow(title: a.$1, desc: a.$2, btnLabel: a.$3)).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DangerActionRow extends StatelessWidget {
  final String title, desc, btnLabel;
  const _DangerActionRow({required this.title, required this.desc, required this.btnLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _fg)),
                const SizedBox(height: 3),
                Text(desc, style: const TextStyle(fontSize: 12, color: _fg2)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () {},
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _red.withOpacity(.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _red.withOpacity(.3)),
              ),
              child: Text(btnLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _red)),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _PageTitle extends StatelessWidget {
  final String title, subtitle;
  const _PageTitle({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _fg)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: _fg2)),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title, subtitle;
  final Widget? trailing;
  final List<Widget> children;
  const _SettingsCard({required this.title, required this.subtitle, this.trailing, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _fg)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 12, color: _fg2)),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _separated(children),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _separated(List<Widget> items) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i < items.length - 1) {
        out.add(const Divider(color: _border, height: 24));
      }
    }
    return out;
  }
}

class _FormRow extends StatelessWidget {
  final String label;
  final String? hint;
  final Widget child;
  const _FormRow({required this.label, this.hint, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _fg)),
              if (hint != null) ...[
                const SizedBox(height: 2),
                Text(hint!, style: const TextStyle(fontSize: 11, color: _fg2)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: child),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String title, hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.title, required this.hint, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _fg)),
              const SizedBox(height: 2),
              Text(hint, style: const TextStyle(fontSize: 11, color: _fg2)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.white,
          activeTrackColor: _accent,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: _fg3,
        ),
      ],
    );
  }
}

class _SaveRow extends StatelessWidget {
  final String label;
  const _SaveRow({this.label = 'Save Changes'});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _SmallButton(label: 'Discard', onTap: () {}),
        const SizedBox(width: 10),
        _SmallButton(label: label, primary: true, onTap: () {}),
      ],
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _SmallButton({required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: primary ? _accent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: primary ? null : Border.all(color: _border),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary ? Colors.white : _fg2)),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

// ─── Dropdown helper ─────────────────────────────────────────────────────────
Widget _dropdownField(List<String> options, int selectedIndex) {
  return _DropdownField(options: options, selectedIndex: selectedIndex);
}

class _DropdownField extends StatefulWidget {
  final List<String> options;
  final int selectedIndex;
  const _DropdownField({required this.options, required this.selectedIndex});
  @override
  State<_DropdownField> createState() => _DropdownFieldState();
}

class _DropdownFieldState extends State<_DropdownField> {
  late int _selected;
  @override
  void initState() { super.initState(); _selected = widget.selectedIndex; }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: _border)),
      child: DropdownButton<int>(
        value: _selected,
        isExpanded: true,
        dropdownColor: _surface,
        underline: const SizedBox(),
        style: const TextStyle(fontSize: 13, color: _fg, fontFamily: 'Inter'),
        icon: const Icon(Icons.keyboard_arrow_down, color: _fg2, size: 18),
        items: widget.options.asMap().entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: (v) { if (v != null) setState(() => _selected = v); },
      ),
    );
  }
}

// ─── Text field helper ───────────────────────────────────────────────────────
Widget _textField(String initial, {int maxLines = 1, double? width}) {
  return SizedBox(
    width: width,
    child: TextFormField(
      initialValue: initial,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 13, color: _fg),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: _bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _accent)),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// SIDEBAR (shared with other admin pages)
// ═══════════════════════════════════════════════════════════════════════════
class _Sidebar extends StatelessWidget {
  final String current;
  const _Sidebar({required this.current});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      color: _surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
            child: const Row(
              children: [
                Icon(Icons.grid_view_rounded, size: 18, color: _accent),
                SizedBox(width: 8),
                Text('TheoTutoring', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _fg)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Overview'),
                  _item(Icons.grid_view_rounded, 'Dashboard', current),
                  _sectionLabel('Users'),
                  _item(Icons.group_outlined, 'Students', current),
                  _item(Icons.person_outlined, 'Tutors', current),
                  _item(Icons.description_outlined, 'Applications', current),
                  _sectionLabel('Content'),
                  _item(Icons.menu_book_outlined, 'Subjects', current),
                  _item(Icons.star_border_rounded, 'Reviews', current),
                  _sectionLabel('Financials'),
                  _item(Icons.attach_money_rounded, 'Payouts', current),
                  _item(Icons.report_problem_outlined, 'Refunds & Issues', current),
                  _sectionLabel('Analytics'),
                  _item(Icons.bar_chart_rounded, 'Reports', current),
                  _sectionLabel('System'),
                  _item(Icons.monitor_heart_outlined, 'Monitor Platform', current),
                  _item(Icons.settings_outlined, 'Settings', current),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
    child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: .08, color: _fg3)),
  );

  Widget _item(IconData icon, String label, String current) {
    final active = label == current;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: active ? _accent.withOpacity(.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, size: 15, color: active ? _accent : _fg2),
        title: Text(label, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.normal, color: active ? _accent : _fg2)),
        onTap: () {},
      ),
    );
  }
}

// ─── Top bar ─────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      color: _surface,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 320,
            height: 32,
            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: _border)),
            child: const Row(
              children: [
                SizedBox(width: 12),
                Icon(Icons.search, size: 15, color: _fg2),
                SizedBox(width: 8),
                Expanded(child: TextField(
                  decoration: InputDecoration(hintText: 'Search platform...', hintStyle: TextStyle(fontSize: 13, color: _fg3), border: InputBorder.none, contentPadding: EdgeInsets.zero),
                  style: TextStyle(fontSize: 13, color: _fg),
                )),
              ],
            ),
          ),
          const Spacer(),
          const Icon(Icons.notifications_outlined, size: 18, color: _fg2),
          const SizedBox(width: 14),
          Container(
            width: 30, height: 30,
            decoration: const BoxDecoration(color: _avatarBg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Text('AC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _accent)),
          ),
          const SizedBox(width: 8),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Admin Central', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _fg)),
              Text('Super User', style: TextStyle(fontSize: 11, color: _fg2)),
            ],
          ),
        ],
      ),
    );
  }
}