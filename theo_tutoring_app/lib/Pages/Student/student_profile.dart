import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'dart:convert';

import '../../config/api.dart';

// ── Service ────────────────────────────────────────────────────────────────

class StudentSettingsService {
  static String get _base => apiBaseUrl;

  static Future<Map<String, dynamic>> fetchSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    final res = await http.get(
      Uri.parse('$_base/student/settings'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to load settings (${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> saveSettings({
    required String email,
    required String phone,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    final res = await http.put(
      Uri.parse('$_base/student/settings'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'email': email, 'phone': phone}),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body);
      throw Exception(body['error'] ?? 'Failed to save settings');
    }
  }

  static Future<void> changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    final res = await http.post(
      Uri.parse('$_base/student/settings/change-password'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to send password reset');
    }
  }
}

// ── Screen ────────────────────────────────────────────────────────────────

class StudentSettings extends StatefulWidget {
  const StudentSettings({super.key});

  @override
  State<StudentSettings> createState() => _StudentSettingsState();
}

class _StudentSettingsState extends State<StudentSettings> {
  // palette — matches dashboard light theme
  static const _bg = Color(0xFFF2F4F8);
  static const _blue = Color(0xFF246BFE);
  static const _text1 = Color(0xFF111827);
  static const _text2 = Color(0xFF374151);
  static const _text3 = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);
  static const _red = Color(0xFFDC2626);

  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String _fullName = '';
  String? _profilePhotoUrl;
  bool _loading = true;
  bool _saving = false;
  bool _loggingOut = false;
  String? _error;

  // notification toggles (UI only — backend returns hardcoded for now)
  bool _sessionReminders = true;
  bool _bookingConfirmations = true;
  bool _directMessages = true;

  final int _selectedIndex = 3; // Profile tab

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await StudentSettingsService.fetchSettings();
      final firebaseUser = FirebaseAuth.instance.currentUser;
      _emailCtrl.text = data['email']?.toString() ?? '';
      _phoneCtrl.text = data['phone']?.toString() ?? '';
      final notif = data['notifications'] as Map<String, dynamic>? ?? {};
      setState(() {
        _fullName =
            data['fullName']?.toString() ??
            data['name']?.toString() ??
            firebaseUser?.displayName ??
            'Student';
        _profilePhotoUrl =
            data['profilePhotoUrl']?.toString() ?? firebaseUser?.photoURL;
        _sessionReminders = notif['sessionReminders'] as bool? ?? true;
        _bookingConfirmations = notif['bookingConfirmations'] as bool? ?? true;
        _directMessages = notif['directMessages'] as bool? ?? true;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (email.isEmpty) {
      _showSnack('Email cannot be empty', isError: true);
      return;
    }
    if (phone.isEmpty) {
      _showSnack('Phone number cannot be empty', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await StudentSettingsService.saveSettings(email: email, phone: phone);
      _showSnack('Settings saved successfully');
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    try {
      await StudentSettingsService.changePassword();
      _showSnack('Password reset email sent');
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _text3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Log Out',
              style: TextStyle(color: _red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _loggingOut = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      _showSnack('Failed to log out: $e', isError: true);
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _red : const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onNavTap(int index) {
    if (index == _selectedIndex) return;
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/student/dashboard');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/student/schedule');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/student/chats');
        break;
      case 3:
        break; // already here
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: _text1),
        title: const Text(
          'My Profile',
          style: TextStyle(
            color: _text1,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.more_vert, color: _text1),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _blue))
          : _error != null
          ? _buildError()
          : _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: _blue,
        unselectedItemColor: _text3,
        backgroundColor: Colors.white,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inbox_rounded),
            label: 'Schedule',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: _text3, size: 40),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _text3, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileHeader(),
          const SizedBox(height: 16),
          // ── Account Settings ──────────────────────────────────────────
          _sectionCard([
            _sectionTitle('Personal Information'),
            const SizedBox(height: 12),
            _fieldLabel('Email Address'),
            const SizedBox(height: 4),
            _inputField(
              _emailCtrl,
              'Email address',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            _fieldLabel('Phone Number'),
            const SizedBox(height: 4),
            _inputField(
              _phoneCtrl,
              'Phone number',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            const Divider(height: 24),
            _chevronRow('Change Password', onTap: _sendPasswordReset),
          ]),

          const SizedBox(height: 16),

          // ── Notification Preferences ──────────────────────────────────
          _sectionCard([
            _sectionTitle('Notification Preferences'),
            const SizedBox(height: 12),
            _toggleRow(
              'Session Reminders',
              '24 hours before your session starts',
              _sessionReminders,
              (val) => setState(() => _sessionReminders = val),
            ),
            const Divider(height: 24),
            _toggleRow(
              'Booking Confirmations',
              'When tutor accepts your request',
              _bookingConfirmations,
              (val) => setState(() => _bookingConfirmations = val),
            ),
            const Divider(height: 24),
            _toggleRow(
              'Direct Messages',
              'New messages from your active tutors',
              _directMessages,
              (val) => setState(() => _directMessages = val),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Payment Methods ───────────────────────────────────────────
          _sectionCard([
            _sectionTitle('Payment Methods'),
            const SizedBox(height: 12),
            Row(
              children: const [
                Icon(Icons.credit_card, size: 20, color: _text3),
                SizedBox(width: 8),
                Text(
                  'Visa ends in *4321',
                  style: TextStyle(fontSize: 14, color: _text2),
                ),
                Spacer(),
                Text(
                  'Expires 08/27',
                  style: TextStyle(fontSize: 12, color: _text3),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {},
              child: const Text(
                '+ Add New Payment Method',
                style: TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // ── App Preferences ───────────────────────────────────────────
          _sectionCard([
            _sectionTitle('App Preferences'),
            const SizedBox(height: 12),
            _chevronRow(
              'App Language',
              trailing: const Text(
                'English',
                style: TextStyle(fontSize: 14, color: _text3),
              ),
            ),
          ]),

          const SizedBox(height: 24),

          // ── Log Out ───────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _loggingOut ? null : _logout,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _loggingOut
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        color: _red,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Log Out',
                      style: TextStyle(
                        color: _red,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    final email = _emailCtrl.text.trim();
    return _sectionCard([
      Center(
        child: CircleAvatar(
          radius: 42,
          backgroundColor: const Color(0xFFE8F0FE),
          backgroundImage: _profilePhotoUrl == null
              ? null
              : NetworkImage(_profilePhotoUrl!),
          child: _profilePhotoUrl == null
              ? Text(
                  _initials(_fullName),
                  style: const TextStyle(
                    color: _blue,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: Text(
          _fullName.isEmpty ? 'Student' : _fullName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _text1,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (email.isNotEmpty) ...[
        const SizedBox(height: 4),
        Center(
          child: Text(
            email,
            style: const TextStyle(color: _text3, fontSize: 13),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: [
            Icon(Icons.school_outlined, color: _blue, size: 20),
            SizedBox(width: 8),
            Text(
              'Student account',
              style: TextStyle(
                color: _text2,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((part) => part.isEmpty);
    if (parts.isEmpty) return 'S';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(
    title,
    style: const TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 15,
      color: _text1,
    ),
  );

  Widget _fieldLabel(String label) =>
      Text(label, style: const TextStyle(fontSize: 12, color: _text3));

  Widget _inputField(
    TextEditingController ctrl,
    String hint, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14, color: _text1),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _text3),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _blue, width: 1.5),
        ),
      ),
    );
  }

  Widget _chevronRow(String label, {Widget? trailing, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: _text2)),
          Row(
            children: [
              if (trailing != null) trailing,
              const Icon(Icons.chevron_right, color: _text3),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _text1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: _text3),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged, activeColor: _blue),
      ],
    );
  }
}
