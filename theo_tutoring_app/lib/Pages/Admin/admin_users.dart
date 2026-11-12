// Users: the Admin accounts on the platform and their roles, and a form to
// create a new Admin (Firebase login + User/Admin records, created by the
// backend). Requires the `admin.users.manage` permission. Changing an Admin's
// role is shown only to Admins with `admin.roles.manage`.

import 'package:flutter/material.dart';

import 'Services/admin_access_service.dart';
import 'Services/admin_users_service.dart';
import 'admin_shell.dart';
import 'models/admin_user_models.dart';

String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, this.service, this.loadAccess});

  final AdminUsersService? service;

  // Injectable for tests; defaults to GET /admin/me.
  final Future<AdminAccessResult> Function()? loadAccess;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late final AdminUsersService _service;
  late final bool _ownsService;

  AdminUsersResult? _result;
  bool _loading = true;
  String? _error;
  AdminAccessResult? _access;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AdminUsersService();
    _ownsService = widget.service == null;
    _loadAccess();
    _load();
  }

  bool get _canChangeRoles =>
      _access?.permissions.contains('admin.roles.manage') ?? false;

  // Without verified permissions the role controls stay hidden; the backend
  // enforces the same permission on every change.
  Future<void> _loadAccess() async {
    AdminAccessResult access;
    try {
      access =
          await (widget.loadAccess ??
              () => AdminAccessService().checkCurrentUser())();
    } catch (_) {
      access = const AdminAccessResult.unavailable();
    }
    if (mounted) setState(() => _access = access);
  }

  @override
  void dispose() {
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.fetchAdmins();
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _msg(e);
        _loading = false;
      });
    }
  }

  Future<void> _addAdmin() async {
    final roles = _result?.roles ?? const <String>[];
    if (roles.isEmpty) return;
    final created = await showDialog<AdminAccount>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateAdminDialog(
        service: _service,
        roles: roles,
        rolePermissions: _result!.rolePermissions,
      ),
    );
    if (created == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${created.name} was added as ${adminRoleLabel(created.role)}. '
          'They can now sign in with the initial password.',
        ),
      ),
    );
    _load();
  }

  Future<void> _changeRole(AdminAccount admin) async {
    final result = _result;
    if (result == null || result.roles.isEmpty) return;
    final change = await showDialog<AdminRoleChange>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ChangeRoleDialog(
        service: _service,
        admin: admin,
        roles: result.roles,
        rolePermissions: result.rolePermissions,
        isSelf: _access?.adminId == admin.adminId,
      ),
    );
    if (change == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${admin.name} is now ${adminRoleLabel(change.role)} '
          '(was ${adminRoleLabel(change.previousRole)}).',
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      currentRoute: AdminRoutes.users,
      adminName: _result?.adminName,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                if (_loading && _result == null)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null && _result == null)
                  _Card(
                    child: _StateMessage(
                      icon: Icons.error_outline,
                      title: 'Could not load administrators.',
                      message: _error!,
                      action: ElevatedButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ),
                  )
                else
                  _buildList(_result!.admins),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 16,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Users',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AdminColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Administrator accounts and their roles.',
              style: TextStyle(fontSize: 14, color: AdminColors.textMuted),
            ),
            if (_access != null && !_canChangeRoles) ...[
              const SizedBox(height: 4),
              const Text(
                'Only a Super Admin can change administrator roles.',
                key: Key('roles-read-only-note'),
                style: TextStyle(fontSize: 12, color: AdminColors.textMuted),
              ),
            ],
          ],
        ),
        FilledButton.icon(
          onPressed: (_result?.roles.isNotEmpty ?? false) ? _addAdmin : null,
          style: FilledButton.styleFrom(backgroundColor: AdminColors.primary),
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('Add Administrator'),
        ),
      ],
    );
  }

  Widget _buildList(List<AdminAccount> admins) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text(
              admins.length == 1
                  ? '1 administrator'
                  : '${admins.length} administrators',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AdminColors.textMuted,
              ),
            ),
          ),
          const Divider(height: 1, color: AdminColors.border),
          if (admins.isEmpty)
            const _StateMessage(
              icon: Icons.group_outlined,
              title: 'No administrators found.',
              message: 'Administrator accounts you add will appear here.',
            )
          else
            for (var i = 0; i < admins.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AdminColors.border),
              _AdminRow(
                admin: admins[i],
                onChangeRole: _canChangeRoles
                    ? () => _changeRole(admins[i])
                    : null,
              ),
            ],
        ],
      ),
    );
  }
}

class _AdminRow extends StatelessWidget {
  const _AdminRow({required this.admin, this.onChangeRole});
  final AdminAccount admin;

  /// Null when the signed-in Admin cannot change roles.
  final VoidCallback? onChangeRole;

  String get _initials {
    final parts = admin.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final active = admin.accountStatus == 'Active';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AdminColors.selected,
            child: Text(
              _initials,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AdminColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  admin.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  admin.email,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              _Pill(
                label: adminRoleLabel(admin.role),
                color: AdminColors.primary,
                background: AdminColors.selected,
              ),
              _Pill(
                label: admin.accountStatus,
                color: active
                    ? const Color(0xFF1B7F3A)
                    : AdminColors.textMuted,
                background: active
                    ? const Color(0xFFD9F5E0)
                    : const Color(0xFFE8EAEE),
              ),
            ],
          ),
          if (onChangeRole != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Change role',
              icon: const Icon(Icons.manage_accounts_outlined, size: 20),
              color: AdminColors.primary,
              onPressed: onChangeRole,
            ),
          ],
        ],
      ),
    );
  }
}

class _CreateAdminDialog extends StatefulWidget {
  const _CreateAdminDialog({
    required this.service,
    required this.roles,
    required this.rolePermissions,
  });

  final AdminUsersService service;
  final List<String> roles;
  final Map<String, List<String>> rolePermissions;

  @override
  State<_CreateAdminDialog> createState() => _CreateAdminDialogState();
}

class _CreateAdminDialogState extends State<_CreateAdminDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late String _role = widget.roles.contains('admin')
      ? 'admin'
      : widget.roles.first;
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await widget.service.createAdmin(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        role: _role,
      );
      _password.clear();
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _msg(e);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add administrator'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.length < 2 || value.length > 100) {
                      return 'Enter 2 to 100 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  enabled: !_saving,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
                      return 'Enter a valid email address.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  enabled: !_saving,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Initial password',
                    helperText: 'At least 8 characters. Share it securely.',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    final length = v?.length ?? 0;
                    if (length < 8 || length > 128) {
                      return 'Use 8 to 128 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [
                    for (final role in widget.roles)
                      DropdownMenuItem(
                        value: role,
                        child: Text(adminRoleLabel(role)),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) {
                          if (v != null) setState(() => _role = v);
                        },
                ),
                if (adminRoleAccessNote(_role, widget.rolePermissions)
                    case final note?) ...[
                  const SizedBox(height: 8),
                  _RoleAccessNote(note: note),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _ErrorText(_error!),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: AdminColors.primary),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Create administrator'),
        ),
      ],
    );
  }
}

class _ChangeRoleDialog extends StatefulWidget {
  const _ChangeRoleDialog({
    required this.service,
    required this.admin,
    required this.roles,
    required this.rolePermissions,
    required this.isSelf,
  });

  final AdminUsersService service;
  final AdminAccount admin;
  final List<String> roles;
  final Map<String, List<String>> rolePermissions;
  final bool isSelf;

  @override
  State<_ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends State<_ChangeRoleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late String _role = widget.admin.role;
  bool _saving = false;
  String? _error;

  bool get _unchanged => _role == widget.admin.role;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_unchanged || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final change = await widget.service.changeRole(
        adminId: widget.admin.adminId,
        role: _role,
        reason: _reason.text.trim(),
      );
      if (mounted) Navigator.pop(context, change);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _msg(e);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Change role for ${widget.admin.name}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Current role: ${adminRoleLabel(widget.admin.role)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AdminColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: widget.roles.contains(_role) ? _role : null,
                  decoration: const InputDecoration(labelText: 'New role'),
                  items: [
                    for (final role in widget.roles)
                      DropdownMenuItem(
                        value: role,
                        child: Text(adminRoleLabel(role)),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) {
                          if (v != null) setState(() => _role = v);
                        },
                ),
                if (adminRoleAccessNote(_role, widget.rolePermissions)
                    case final note?) ...[
                  const SizedBox(height: 8),
                  _RoleAccessNote(note: note),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reason,
                  enabled: !_saving,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    helperText: 'Recorded in the role change audit.',
                  ),
                  validator: (v) {
                    final length = v?.trim().length ?? 0;
                    if (length < 3 || length > 500) {
                      return 'Enter 3 to 500 characters.';
                    }
                    return null;
                  },
                ),
                if (widget.isSelf) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'This is your own account. A role without administrator '
                    'management will remove your access to this page.',
                    key: Key('self-role-warning'),
                    style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _ErrorText(_error!),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || _unchanged ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: AdminColors.primary),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save role'),
        ),
      ],
    );
  }
}

class _RoleAccessNote extends StatelessWidget {
  const _RoleAccessNote({required this.note});
  final String note;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AdminColors.selected,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 16, color: AdminColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            note,
            key: const Key('role-access-note'),
            style: const TextStyle(fontSize: 12, color: AdminColors.textDark),
          ),
        ),
      ],
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: const TextStyle(fontSize: 13, color: Color(0xFFC62828)),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AdminColors.border),
    ),
    child: child,
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: color,
      ),
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
    child: Column(
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
          style: const TextStyle(fontSize: 12, color: AdminColors.textMuted),
        ),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    ),
  );
}
