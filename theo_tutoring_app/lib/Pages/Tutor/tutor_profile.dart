import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../cloudinary_upload.dart';
import 'tutor_api.dart';
import 'tutor_format.dart';
import 'tutor_nav.dart';

class TutorProfileScreen extends StatefulWidget {
  const TutorProfileScreen({super.key});

  @override
  State<TutorProfileScreen> createState() => _TutorProfileScreenState();
}

class _TutorProfileScreenState extends State<TutorProfileScreen> {
  bool _loading = true;
  String? _error;
  bool _editMode = false;
  bool _saving = false;
  bool _uploading = false;

  // From GET /TutorLandingpage/Profile
  String _name = '';
  String? _photoUrl;
  double? _sessionRate; // fixed by the admin, read-only
  String? _about;
  List<String> _subjects = [];
  List<Map<String, dynamic>> _qualifications = [];

  // Availability grid, Monday to Saturday (documentation 9.3 / 11.1)
  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  ];
  static const _slots = ['Morning', 'Afternoon', 'Evening'];
  Map<String, Set<String>> _ticked = {}; // day -> ticked periods
  Map<String, Set<String>> _saved = {}; // what the server has
  Map<String, Set<String>> _locked = {}; // periods with an upcoming booking

  static const _blue = Color(0xFF1457D9);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final p = await fetchTutorProfile();
      if (!mounted) return;
      setState(() {
        _name = p['name']?.toString() ?? '';
        _photoUrl = p['profilePhotoUrl']?.toString();
        _sessionRate = (p['sessionRate'] as num?)?.toDouble();
        _about = p['about']?.toString();
        _subjects = [
          for (final s in p['subjects'] as List<dynamic>? ?? [])
            (s as Map<String, dynamic>)['subjectName']?.toString() ?? '',
        ];
        _qualifications = (p['qualifications'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        _readGrid(p['availability'] as List<dynamic>? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // [{day: Monday, slots: [{period: Morning, ...}], locked: [Morning]}, ...]
  void _readGrid(List<dynamic> availability, {bool keepLocks = false}) {
    final ticked = <String, Set<String>>{};
    final locked = <String, Set<String>>{};
    for (final d in availability.cast<Map<String, dynamic>>()) {
      final day = d['day']?.toString() ?? '';
      ticked[day] = {
        for (final s in d['slots'] as List<dynamic>? ?? [])
          (s as Map<String, dynamic>)['period']?.toString() ?? '',
      };
      locked[day] = {
        for (final p in d['locked'] as List<dynamic>? ?? []) p.toString(),
      };
    }
    _ticked = ticked;
    _saved = {for (final e in ticked.entries) e.key: {...e.value}};
    if (!keepLocks) _locked = locked;
  }

  bool get _gridChanged => _days.any((d) {
        final a = _ticked[d] ?? const {};
        final b = _saved[d] ?? const {};
        return a.length != b.length || !a.containsAll(b);
      });

  void _toggle(String day, String slot) {
    if (!_editMode) {
      _showMessage('Turn on Edit to change your availability.');
      return;
    }
    final periods = _ticked.putIfAbsent(day, () => {});
    if (periods.contains(slot) && (_locked[day]?.contains(slot) ?? false)) {
      _showMessage(
          'You have an upcoming booking on $day ($slot), so it must stay '
          'available.');
      return;
    }
    setState(() => periods.contains(slot)
        ? periods.remove(slot)
        : periods.add(slot));
  }

  Future<void> _saveAvailability() async {
    setState(() => _saving = true);
    try {
      final result = await saveTutorAvailability({
        for (final day in _days)
          if ((_ticked[day] ?? const {}).isNotEmpty)
            day: [
              for (final s in _slots)
                if (_ticked[day]!.contains(s)) s,
            ],
      });
      if (!mounted) return;
      setState(() {
        _readGrid(result['availability'] as List<dynamic>? ?? [],
            keepLocks: true);
        _editMode = false;
        _saving = false;
      });
      _showMessage(result['message']?.toString() ?? 'Availability saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(e.toString(), error: true);
    }
  }

  // Camera badge: pick a picture, upload it to Cloudinary, save its URL.
  Future<void> _changePhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final url = await uploadToCloudinary(file);
      final result = await saveTutorPhoto(url);
      if (!mounted) return;
      final tutor = result['tutor'] as Map<String, dynamic>?;
      setState(() {
        _photoUrl = tutor?['profilePhotoUrl']?.toString() ?? url;
        _uploading = false;
      });
      _showMessage(result['message']?.toString() ?? 'Profile photo updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _showMessage(
          switch (e) {
            TutorApiException(:final message) => message,
            CloudinaryUploadException(:final message) => message,
            _ => 'Could not upload the photo.',
          },
          error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFDC2626) : null,
      ));
  }

  // 250.0 -> "R250", 262.5 -> "R262.50"
  String get _rateLabel {
    final r = _sessionRate;
    if (r == null) return 'Not set yet';
    final amount = r == r.roundToDouble()
        ? r.toStringAsFixed(0)
        : r.toStringAsFixed(2);
    return 'R$amount / session';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _blue))
            : _error != null
                ? _buildError()
                : RefreshIndicator(
                    onRefresh: _load,
                    color: _blue,
                    child: _buildContent(),
                  ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _blue, foregroundColor: Colors.white),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Top bar
        Row(
          children: [
            GestureDetector(
              onTap: () => openTutorTab(context, 0, current: 3),
              child: const Icon(Icons.arrow_back, color: Colors.black87),
            ),
            const SizedBox(width: 12),
            const Text(
              'Edit Profile',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Avatar + name
        Row(
          children: [
            GestureDetector(
              onTap: _uploading ? null : _changePhoto,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: const Color(0xFFD0E4FF),
                    backgroundImage:
                        _photoUrl != null ? NetworkImage(_photoUrl!) : null,
                    child: _uploading
                        ? const CircularProgressIndicator(color: _blue)
                        : _photoUrl == null
                            ? Text(initialsOf(_name),
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: _blue))
                            : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: _blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt,
                          size: 13, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      text: 'Session Rate:  ',
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                      children: [
                        TextSpan(
                          text: _rateLabel,
                          style: const TextStyle(
                            color: _blue,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text('Set by the administrator',
                      style: TextStyle(color: Colors.black38, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // About Me
        _sectionCard(
          title: 'About Me',
          child: Text(
            _about ?? 'You have not written an About Me yet.',
            style: TextStyle(
              color: _about == null ? Colors.black38 : Colors.black54,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Subjects
        _sectionCard(
          title: 'Subjects',
          child: _subjects.isEmpty
              ? const Text('No subjects added yet.',
                  style: TextStyle(color: Colors.black38, fontSize: 13))
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _subjects.map((s) => _chip(s, true)).toList(),
                ),
        ),
        const SizedBox(height: 16),

        // Qualifications
        _sectionCard(
          title: 'Qualifications',
          child: _qualifications.isEmpty
              ? const Text('No qualifications added yet.',
                  style: TextStyle(color: Colors.black38, fontSize: 13))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final q in _qualifications)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.school_outlined, color: _blue, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(q['degree']?.toString() ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: Colors.black87)),
                                  Text(q['institution']?.toString() ?? '',
                                      style: const TextStyle(
                                          color: Colors.black45, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),

        // Edit toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            children: [
              const Text('Edit', style: TextStyle(color: Colors.black54, fontSize: 14)),
              const SizedBox(width: 12),
              Switch(
                value: _editMode,
                onChanged: (val) => setState(() {
                  _editMode = val;
                  if (!val) {
                    // turning Edit off throws away unsaved changes
                    _ticked = {for (final e in _saved.entries) e.key: {...e.value}};
                  }
                }),
                activeThumbColor: _blue,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Availability Grid
        _sectionCard(
          title: 'Availability Grid',
          child: Column(
            children: [
              // Day headers
              Row(
                children: [
                  const SizedBox(width: 70),
                  ..._days.map((d) => Expanded(
                        child: Center(
                          child: Text(d.substring(0, 3),
                              style: const TextStyle(
                                  color: Colors.black45, fontSize: 11, fontWeight: FontWeight.w500)),
                        ),
                      )),
                ],
              ),
              const SizedBox(height: 8),
              // Rows
              ..._slots.map((slot) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: Text(slot,
                            style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      ),
                      ..._days.map((day) {
                        final isAvailable = _ticked[day]?.contains(slot) ?? false;
                        final isLocked =
                            isAvailable && (_locked[day]?.contains(slot) ?? false);
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => _toggle(day, slot),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              height: 28,
                              decoration: BoxDecoration(
                                color: isAvailable
                                    ? _blue
                                    : const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: isLocked
                                  ? const Icon(Icons.lock,
                                      size: 12, color: Colors.white)
                                  : null,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              }),
              if (_locked.values.any((l) => l.isNotEmpty)) ...[
                const SizedBox(height: 4),
                const Row(
                  children: [
                    Icon(Icons.lock, size: 12, color: Colors.black38),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          'Locked slots have upcoming bookings and cannot be removed.',
                          style: TextStyle(color: Colors.black38, fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Save button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _editMode && _gridChanged && !_saving
                ? _saveAvailability
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Save Changes',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _chip(String label, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? _blue : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? _blue : Colors.grey[300]!,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.black54,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: 3,
      backgroundColor: Colors.white,
      elevation: 8,
      selectedItemColor: _blue,
      unselectedItemColor: Colors.black38,
      type: BottomNavigationBarType.fixed,
      selectedFontSize: 11,
      unselectedFontSize: 11,
      onTap: (i) => openTutorTab(context, i, current: 3),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Dashboard'),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_month_rounded), label: 'Schedule'),
        BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline_rounded), label: 'Chats'),
        BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
      ],
    );
  }
}
