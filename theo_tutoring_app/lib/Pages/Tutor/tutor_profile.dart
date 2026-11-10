import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../services/google_meet_connect.dart';
import '../cloudinary_upload.dart';
import '../auth_gate.dart';
import '../privacy_policy.dart';
import '../terms_and_conditions.dart';
import 'tutor_api.dart';
import 'tutor_availability_calendar.dart';
import 'tutor_format.dart';
import 'tutor_nav.dart';
import 'tutor_report_problem.dart';
import 'tutor_theme.dart';

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
  String _accountStatus = 'Active'; // 'Active' or 'Pending'
  double _averageRating = 0; // 0 until the first review
  int _reviewCount = 0;
  double? _sessionRate; // fixed by the admin, read-only
  String? _about;
  List<({int id, String name})> _subjects = [];
  Set<int> _lockedSubjectIds = {}; // subjects with an upcoming booking
  bool _savingSubjects = false;
  List<Map<String, dynamic>> _qualifications = [];
  bool _meetConnected = false; // the tutor has a Google Meet room saved
  bool _connectingMeet = false;

  // Same limits as the backend (registration rules)
  static const _minAbout = 20;
  static const _maxAbout = 300;
  static const _maxSubjects = 10;

  // Availability grid, Monday to Saturday (documentation 9.3 / 11.1)
  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  ];
  static const _slots = ['Morning', 'Afternoon', 'Evening'];
  Map<String, Set<String>> _ticked = {}; // day -> ticked periods
  Map<String, Set<String>> _saved = {}; // what the server has
  Map<String, Set<String>> _locked = {}; // periods with an upcoming booking

  // Month view under the grid: single-date changes (day off / other hours)
  AvailabilityCalendarData? _calendar;
  bool _showCalendar = false;

  static const _blue = Color(0xFF2563EB);
  static const _red = Color(0xFFE11D48);

  // Light colours, or the dark ones when the tutor turned on Dark Mode
  bool get _dk => context.tutorDark;
  Color get _bg => _dk ? TutorDark.background : const Color(0xFFF3F4F8);
  Color get _surface => _dk ? TutorDark.card : Colors.white;
  Color get _cellEmpty => _dk ? TutorDark.cardAlt : const Color(0xFFF1F4F9);
  Color get _line => _dk ? TutorDark.border : const Color(0xFFEEF0F4);
  Color get _dark => _dk ? TutorDark.text : const Color(0xFF111827);
  Color get _grey => _dk ? TutorDark.textMuted : const Color(0xFF6B7280);
  Color get _muted => _dk ? TutorDark.textFaint : const Color(0xFF9CA3AF);
  Color get _blueText => _dk ? TutorDark.blueText : _blue;
  Color get _blueLight => _dk ? TutorDark.blueTint : const Color(0xFFE8F0FE);
  Color get _green => _dk ? TutorDark.greenText : const Color(0xFF15803D);
  Color get _greenLight => _dk ? TutorDark.greenTint : const Color(0xFFDCFCE7);
  Color get _amber => _dk ? TutorDark.amberText : const Color(0xFFB45309);
  Color get _amberLight => _dk ? TutorDark.amberTint : const Color(0xFFFEF3C7);

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
        _accountStatus = p['accountStatus']?.toString() ?? 'Active';
        _averageRating = (p['averageRating'] as num?)?.toDouble() ?? 0;
        _reviewCount = (p['reviewCount'] as num?)?.toInt() ?? 0;
        _sessionRate = (p['sessionRate'] as num?)?.toDouble();
        _about = p['about']?.toString();
        _readSubjects(p['subjects'], p['lockedSubjectIds']);
        _qualifications = (p['qualifications'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        _meetConnected = p['meetConnected'] == true;
        _readGrid(p['availability'] as List<dynamic>? ?? []);
        _readCalendar(p['availabilityCalendar']);
        _editMode = false;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // subjects: [{subjectId, subjectName}], locked: [3, 5]
  void _readSubjects(Object? subjects, Object? locked) {
    _subjects = [
      for (final s in (subjects as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>())
        (
          id: (s['subjectId'] as num).toInt(),
          name: s['subjectName']?.toString() ?? '',
        ),
    ];
    _lockedSubjectIds = {
      for (final id in locked as List<dynamic>? ?? []) (id as num).toInt(),
    };
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

  // {today, lastDate, dateChanges, bookings}; null on an older backend
  void _readCalendar(Object? calendar) {
    _calendar = calendar is Map<String, dynamic>
        ? AvailabilityCalendarData.fromJson(calendar)
        : null;
    if (_calendar == null) _showCalendar = false;
  }

  // A date in the calendar: Usual / Day off / Custom hours sheet
  Future<void> _openDate(DateTime date) async {
    final calendar = _calendar;
    if (calendar == null) return;
    final saved = await showDateHoursSheet(
      context,
      date: date,
      data: calendar,
      weekly: _saved, // what students see, not unsaved grid edits
      onSave: (mode, hours) async {
        final result = await saveTutorDateAvailability(
          date: dateKey(date),
          mode: mode.apiName,
          times: hoursToTimes(hours),
        );
        if (mounted) {
          setState(() => _readCalendar(result['availabilityCalendar']));
        }
      },
    );
    if (saved != true || !mounted) return;
    final day = DateFormat('EEE d MMM').format(date);
    final kind = _calendar == null
        ? null
        : calendarDayKind(date, _calendar!, _saved);
    _showMessage(switch (kind) {
      CalendarDayKind.off => 'Day off saved for $day.',
      CalendarDayKind.changed => 'Your hours for $day are saved.',
      _ => '$day is back to your usual hours.',
    });
  }

  bool get _gridChanged => _days.any((d) {
        final a = _ticked[d] ?? const {};
        final b = _saved[d] ?? const {};
        return a.length != b.length || !a.containsAll(b);
      });

  bool get _hasLocks => _locked.values.any((l) => l.isNotEmpty);

  void _toggle(String day, String slot) {
    if (!_editMode) {
      _showMessage('Tap Edit Profile to change your availability.');
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

  void _cancelEditing() {
    setState(() {
      _editMode = false;
      // throw away unsaved changes
      _ticked = {for (final e in _saved.entries) e.key: {...e.value}};
    });
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

  // Also stops "Available Now" and switches back to the light theme.
  Future<void> _logOut() => signOutToStart(context);

  // ✏️ on About Me: edit the bio in a sheet, saved straight away
  Future<void> _editAbout() async {
    final controller = TextEditingController(text: _about ?? '');
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _surface,
      builder: (sheetContext) {
        var saving = false;
        String? error;
        return StatefulBuilder(
          builder: (sheetContext, setSheet) {
            final length = controller.text.trim().length;
            final valid = length >= _minAbout && length <= _maxAbout;

            Future<void> save() async {
              setSheet(() {
                saving = true;
                error = null;
              });
              try {
                final result = await saveTutorAbout(controller.text.trim());
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext,
                      result['about']?.toString() ?? controller.text.trim());
                }
              } catch (e) {
                setSheet(() {
                  saving = false;
                  error = e.toString();
                });
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20,
                  MediaQuery.of(sheetContext).viewInsets.bottom + 20),
              // Scrolls when the phone keyboard leaves too little room, so
              // Save is never pushed off screen
              child: SingleChildScrollView(
               child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cardTitle('Edit About Me'),
                  const SizedBox(height: 4),
                  Text(
                      'Tell students about your experience and how you teach.',
                      style: TextStyle(fontSize: 12, color: _grey)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: _maxAbout,
                    enabled: !saving,
                    onChanged: (_) => setSheet(() {}),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      helperText: length < _minAbout
                          ? 'At least $_minAbout characters'
                          : null,
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 4),
                    Text(error!,
                        style: const TextStyle(
                            color: Color(0xFFDC2626), fontSize: 12)),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              saving ? null : () => Navigator.pop(sheetContext),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: valid && !saving ? save : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                          child: saving
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
               ),
              ),
            );
          },
        );
      },
    );
    controller.dispose();
    if (saved == null || !mounted) return;
    setState(() => _about = saved);
    _showMessage('About Me saved.');
  }

  // "+ Add Subject": pick from the subjects not taught yet
  Future<void> _addSubject() async {
    if (_subjects.length >= _maxSubjects) {
      _showMessage('You can teach up to $_maxSubjects subjects.');
      return;
    }
    final List<Map<String, dynamic>> all;
    try {
      all = await fetchAllSubjects();
    } catch (e) {
      _showMessage(e.toString(), error: true);
      return;
    }
    if (!mounted) return;
    final taught = {for (final s in _subjects) s.id};
    final options = [
      for (final s in all)
        if (!taught.contains((s['subjectId'] as num).toInt()))
          (
            id: (s['subjectId'] as num).toInt(),
            name: s['subjectName']?.toString() ?? '',
          ),
    ];
    if (options.isEmpty) {
      _showMessage('You already teach every subject on the platform.');
      return;
    }

    final picked = await showModalBottomSheet<({int id, String name})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _surface,
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (sheetContext, setSheet) {
            final matches = [
              for (final s in options)
                if (s.name.toLowerCase().contains(query.toLowerCase())) s,
            ];
            // 60% of the screen, but never taller than the room left above
            // the phone keyboard (or the search box is pushed off the top)
            final media = MediaQuery.of(sheetContext);
            final room = media.size.height -
                media.viewInsets.bottom -
                media.padding.top -
                96; // drag handle and margins
            final height =
                (media.size.height * 0.6).clamp(0.0, room < 160 ? 160.0 : room);
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16,
                  media.viewInsets.bottom + 16),
              child: SizedBox(
                height: height,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardTitle('Add a subject you teach'),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      // Filters as you type; Search just closes the keyboard
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Search subjects',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => setSheet(() => query = value),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: matches.isEmpty
                          ? const Center(child: Text('No subjects found.'))
                          : ListView(
                              children: [
                                for (final s in matches)
                                  ListTile(
                                    title: Text(s.name),
                                    trailing:
                                        const Icon(Icons.add, color: _blue),
                                    onTap: () =>
                                        Navigator.pop(sheetContext, s),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (picked == null || !mounted) return;
    await _saveSubjects([for (final s in _subjects) s.id, picked.id],
        done: '${picked.name} added.');
  }

  // × on a subject chip
  Future<void> _removeSubject(({int id, String name}) subject) async {
    if (_lockedSubjectIds.contains(subject.id)) {
      _showMessage(
          '${subject.name} has an upcoming booking, so you cannot remove it '
          'yet.');
      return;
    }
    if (_subjects.length == 1) {
      _showMessage('Keep at least one subject.');
      return;
    }
    await _saveSubjects(
        [for (final s in _subjects) if (s.id != subject.id) s.id],
        done: '${subject.name} removed.');
  }

  Future<void> _saveSubjects(List<int> ids, {required String done}) async {
    setState(() => _savingSubjects = true);
    try {
      final result = await saveTutorSubjects(ids);
      if (!mounted) return;
      setState(() {
        _readSubjects(result['subjects'], result['lockedSubjectIds']);
        _savingSubjects = false;
      });
      _showMessage(done);
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingSubjects = false);
      _showMessage(e.toString(), error: true);
    }
  }

  // Connect / Reconnect on the Google Meet card: Google's window gives a
  // token, the backend makes a new room and every lesson uses its link.
  Future<void> _connectMeet() async {
    setState(() => _connectingMeet = true);
    try {
      // Google's window first: after any other await the browser can block it
      final accessToken = await requestMeetAccessToken();
      await connectTutorMeet(accessToken);
      if (!mounted) return;
      final reconnected = _meetConnected;
      setState(() {
        _meetConnected = true;
        _connectingMeet = false;
      });
      _showMessage(reconnected
          ? 'Google Meet reconnected. Your lessons use the new link.'
          : 'Google Meet connected.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _connectingMeet = false);
      _showMessage(e.toString(), error: true);
    }
  }

  void _comingSoon(String feature) =>
      _showMessage('$feature will be available soon.');

  // Support → Report a Problem; the page pops with its confirmation message
  Future<void> _openReportProblem() async {
    final sent = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const TutorReportProblemPage()),
    );
    if (sent != null && mounted) _showMessage(sent);
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

  // ── PAGE ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      drawer: _buildDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _blue))
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _blue,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _buildHeaderCard(),
                      const SizedBox(height: 16),
                      _buildAboutCard(),
                      const SizedBox(height: 16),
                      _buildSubjectsCard(),
                      const SizedBox(height: 16),
                      _buildAvailabilityCard(),
                      const SizedBox(height: 16),
                      _buildEditButtons(),
                      const SizedBox(height: 16),
                      _buildMeetCard(),
                      const SizedBox(height: 16),
                      _buildPreferencesCard(),
                      const SizedBox(height: 16),
                      _buildSupportCard(),
                      const SizedBox(height: 16),
                      _buildLogOutCard(),
                    ],
                  ),
                ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _surface,
      surfaceTintColor: _surface,
      elevation: 0,
      centerTitle: true,
      leading: Builder(
        builder: (context) => IconButton(
          icon: Icon(Icons.menu_rounded, color: _dark),
          tooltip: 'Menu',
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _blueLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.school_rounded, color: _blue, size: 18),
          ),
          const SizedBox(width: 10),
          Text('My Profile',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: _dark)),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: _dark),
          onSelected: (value) => value == 'refresh' ? _load() : _logOut(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'refresh', child: Text('Refresh')),
            PopupMenuItem(value: 'logout', child: Text('Log Out')),
          ],
        ),
      ],
    );
  }

  // The ☰ menu: the tutor pages and Log Out
  Widget _buildDrawer() {
    Widget item(IconData icon, String label, int tab) => ListTile(
          leading: Icon(icon, color: tab == 3 ? _blue : _grey),
          title: Text(label,
              style: TextStyle(
                  color: tab == 3 ? _blue : _dark,
                  fontWeight: tab == 3 ? FontWeight.w600 : FontWeight.w500)),
          onTap: () {
            Navigator.pop(context); // close the menu
            openTutorTab(context, tab, current: 3);
          },
        );

    return Drawer(
      backgroundColor: _surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  _avatar(radius: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _dark)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            item(Icons.grid_view_rounded, 'Dashboard', 0),
            item(Icons.calendar_month_rounded, 'Schedule', 1),
            item(Icons.chat_bubble_outline_rounded, 'Chats', 2),
            item(Icons.person_rounded, 'Profile', 3),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: _red),
              title: const Text('Log Out',
                  style: TextStyle(color: _red, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _logOut();
              },
            ),
          ],
        ),
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
            Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: _grey, fontSize: 13)),
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

  // ── HEADER: photo, name, rating, badges, session rate ───────────────────────

  Widget _avatar({required double radius}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _blueLight,
      backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
      child: _uploading
          ? const CircularProgressIndicator(color: _blue)
          : _photoUrl == null
              ? Text(initialsOf(_name),
                  style: TextStyle(
                      fontSize: radius * 0.6,
                      fontWeight: FontWeight.w700,
                      color: _blue))
              : null,
    );
  }

  Widget _buildHeaderCard() {
    final approved = _accountStatus == 'Active';
    final hasRating = _reviewCount > 0;

    return _card(
      child: Row(
        children: [
          // Photo with the camera badge (changes the photo)
          GestureDetector(
            onTap: _uploading ? null : _changePhoto,
            child: Stack(
              children: [
                _avatar(radius: 40),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: _blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: _surface, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
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
                Text(_name,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _dark)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Color(0xFFF59E0B), size: 17),
                    const SizedBox(width: 3),
                    Text(
                      hasRating ? _averageRating.toStringAsFixed(1) : 'New',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _dark),
                    ),
                    Text(
                      hasRating
                          ? '  ·  $_reviewCount '
                              '${_reviewCount == 1 ? 'review' : 'reviews'}'
                          : '  ·  No reviews yet',
                      style: TextStyle(fontSize: 12, color: _grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _badge('TUTOR', _blueText, _blueLight),
                    approved
                        ? _badge('VERIFIED', _green, _greenLight)
                        : _badge('PENDING REVIEW', _amber, _amberLight),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Session rate: $_rateLabel',
                    style: TextStyle(fontSize: 12, color: _grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: color)),
    );
  }

  // ── ABOUT ME ────────────────────────────────────────────────────────────────

  Widget _buildAboutCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _cardTitle('About Me')),
              IconButton(
                onPressed: _editAbout,
                tooltip: 'Edit About Me',
                icon: const Icon(Icons.edit_outlined, color: _blue, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _about ?? 'You have not written an About Me yet.',
            style: TextStyle(
              color: _about == null ? _muted : _grey,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ── SUBJECTS & QUALIFICATIONS ───────────────────────────────────────────────

  Widget _buildSubjectsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Subjects & Qualifications'),
          const SizedBox(height: 14),
          _label('SUBJECTS'),
          const SizedBox(height: 8),
          if (_subjects.isEmpty)
            Text('No subjects added yet.',
                style: TextStyle(color: _muted, fontSize: 13))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final s in _subjects) _subjectChip(s)],
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _savingSubjects ? null : _addSubject,
            icon: _savingSubjects
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add, size: 18),
            label: const Text('Add Subject'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _blue,
              side: const BorderSide(color: _blue),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
          if (_lockedSubjectIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.lock, size: 12, color: _muted),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                      'Locked subjects have upcoming bookings and cannot be '
                      'removed.',
                      style: TextStyle(color: _muted, fontSize: 11)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _label('QUALIFICATIONS'),
          const SizedBox(height: 8),
          if (_qualifications.isEmpty)
            Text('No qualifications added yet.',
                style: TextStyle(color: _muted, fontSize: 13))
          else
            for (final q in _qualifications)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.school_outlined, color: _blue, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(q['degree']?.toString() ?? '',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: _dark)),
                          Text(q['institution']?.toString() ?? '',
                              style: TextStyle(
                                  color: _grey, fontSize: 12)),
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

  // A blue subject pill with × to remove it, or a lock when it is booked
  Widget _subjectChip(({int id, String name}) subject) {
    final locked = _lockedSubjectIds.contains(subject.id);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      decoration: BoxDecoration(
        color: _blue,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(subject.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _savingSubjects ? null : () => _removeSubject(subject),
            child: Tooltip(
              message: locked ? 'Has an upcoming booking' : 'Remove',
              child: Icon(
                locked ? Icons.lock : Icons.close_rounded,
                size: 14,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── AVAILABILITY ────────────────────────────────────────────────────────────

  Widget _buildAvailabilityCard() {
    final calendar = _calendar;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Availability'),
          if (calendar != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Weekly'),
                    icon: Icon(Icons.repeat_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Calendar'),
                    icon: Icon(Icons.calendar_month_rounded, size: 18),
                  ),
                ],
                selected: {_showCalendar},
                onSelectionChanged: (s) =>
                    setState(() => _showCalendar = s.first),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _showCalendar
                ? 'Tap a date to take the day off or change its hours. '
                    'Students see the change straight away.'
                : 'These hours repeat every week. Students can book up to '
                    '90 days ahead.',
            style: TextStyle(fontSize: 12, color: _grey, height: 1.4),
          ),
          if (_editMode && !_showCalendar) ...[
            const SizedBox(height: 4),
            const Text('Tap a slot to turn it on or off.',
                style: TextStyle(fontSize: 12, color: _blue)),
          ],
          if (_showCalendar && _gridChanged) ...[
            const SizedBox(height: 4),
            Text(
                'The calendar uses your saved weekly hours. Save Changes to '
                'include your grid edits.',
                style: TextStyle(fontSize: 12, color: _amber)),
          ],
          const SizedBox(height: 14),
          if (_showCalendar && calendar != null)
            AvailabilityCalendar(
              data: calendar,
              weekly: _saved,
              onDateTap: _openDate,
            )
          else
            ..._buildWeeklyGrid(),
        ],
      ),
    );
  }

  List<Widget> _buildWeeklyGrid() {
    return [
      // Day headers
      Row(
        children: [
          const SizedBox(width: 70),
          for (final d in _days)
            Expanded(
              child: Center(
                child: Text(d.substring(0, 3),
                    style: TextStyle(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      for (final slot in _slots)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(slot,
                        style:
                            TextStyle(color: _grey, fontSize: 11)),
                    Text(_periodRange(slot),
                        style:
                            TextStyle(color: _muted, fontSize: 10)),
                  ],
                ),
              ),
              for (final day in _days) _gridCell(day, slot),
            ],
          ),
        ),
      if (_hasLocks)
        Row(
          children: [
            Icon(Icons.lock, size: 12, color: _muted),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                  'Locked slots have upcoming bookings and cannot be '
                  'removed.',
                  style: TextStyle(color: _muted, fontSize: 11)),
            ),
          ],
        ),
    ];
  }

  // "Morning" -> "08:00–12:00"
  String _periodRange(String slot) {
    final hours = tutorPeriodHours[slot]!;
    return '${hourLabel(hours.start)}–${hourLabel(hours.end)}';
  }

  Widget _gridCell(String day, String slot) {
    final isAvailable = _ticked[day]?.contains(slot) ?? false;
    final isLocked = isAvailable && (_locked[day]?.contains(slot) ?? false);
    return Expanded(
      child: GestureDetector(
        onTap: () => _toggle(day, slot),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          height: 30,
          decoration: BoxDecoration(
            color: isAvailable ? _blue : _cellEmpty,
            borderRadius: BorderRadius.circular(6),
            border: _editMode && !isAvailable
                ? Border.all(color: _dk ? TutorDark.border : const Color(0xFFD6DEEB))
                : null,
          ),
          child: isLocked
              ? const Icon(Icons.lock, size: 12, color: Colors.white)
              : null,
        ),
      ),
    );
  }

  // "Edit Profile" turns on editing; then Cancel / Save Changes
  Widget _buildEditButtons() {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    if (!_editMode) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => setState(() => _editMode = true),
          style: ElevatedButton.styleFrom(
            backgroundColor: _blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: shape,
            elevation: 0,
          ),
          child: const Text('Edit Profile',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _saving ? null : _cancelEditing,
            style: OutlinedButton.styleFrom(
              foregroundColor: _grey,
              side: BorderSide(color: _dk ? TutorDark.border : const Color(0xFFD1D5DB)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: shape,
            ),
            child: const Text('Cancel',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _gridChanged && !_saving ? _saveAvailability : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: shape,
              elevation: 0,
            ),
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Save Changes',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // ── GOOGLE MEET ─────────────────────────────────────────────────────────────

  // Lessons happen in the tutor's own Meet room. Reconnect replaces a room
  // that stopped working (or switches Google account).
  Widget _buildMeetCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _cardTitle('Google Meet')),
              _meetConnected
                  ? _badge('CONNECTED', _green, _greenLight)
                  : _badge('NOT CONNECTED', _amber, _amberLight),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _meetConnected
                ? 'Your lessons take place in your own Google Meet room. '
                    'Reconnect if the link stops working.'
                : 'Connect Google Meet so students can join your lessons. '
                    'Sign in with Google once and the app creates your room.',
            style: TextStyle(fontSize: 12, color: _grey, height: 1.4),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _connectingMeet ? null : _connectMeet,
            icon: _connectingMeet
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.videocam_outlined, size: 18),
            label: Text(_meetConnected ? 'Reconnect' : 'Connect Google Meet'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _blue,
              side: const BorderSide(color: _blue),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ── PREFERENCES & SUPPORT ───────────────────────────────────────────────────

  Widget _buildPreferencesCard() {
    return _listCard(
      title: 'Preferences',
      rows: [
        _row(
          icon: Icons.dark_mode_outlined,
          title: 'Dark Mode',
          trailing: Switch(
            value: TutorTheme.darkChosen,
            activeThumbColor: Colors.white,
            activeTrackColor: _blue,
            // The whole app rebuilds in the new theme (main.dart)
            onChanged: (on) => TutorTheme.setDark(on),
          ),
          onTap: () => TutorTheme.setDark(!TutorTheme.darkChosen),
        ),
      ],
    );
  }

  Widget _buildSupportCard() {
    return _listCard(
      title: 'Support',
      rows: [
        _row(
          icon: Icons.help_outline_rounded,
          title: 'Help Center',
          onTap: () => _comingSoon('The Help Center'),
        ),
        _row(
          icon: Icons.outlined_flag_rounded,
          title: 'Report a Problem',
          onTap: _openReportProblem,
        ),
        _row(
          icon: Icons.description_outlined,
          title: 'Terms of Service',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TermsAndConditionsPage()),
          ),
        ),
        _row(
          icon: Icons.privacy_tip_outlined,
          title: 'Privacy Policy',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
          ),
        ),
      ],
    );
  }

  Widget _buildLogOutCard() {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _logOut,
        borderRadius: BorderRadius.circular(16),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, color: _red, size: 20),
              SizedBox(width: 8),
              Text('Log Out',
                  style: TextStyle(
                      color: _red, fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ── SHARED PIECES ───────────────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _cardTitle(String text) => Text(text,
      style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700, color: _dark));

  Widget _label(String text) => Text(text,
      style: TextStyle(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1));

  // A card with a title and tappable rows separated by lines
  Widget _listCard({required String title, required List<Widget> rows}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: _cardTitle(title),
          ),
          for (final row in rows) ...[
            Divider(height: 1, color: _line),
            row,
          ],
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      leading: Icon(icon, color: _blue, size: 22),
      title: Text(title, style: TextStyle(fontSize: 14, color: _dark)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: TextStyle(fontSize: 11, color: _muted)),
      trailing: trailing ??
          Icon(Icons.chevron_right_rounded, color: _muted),
      onTap: onTap,
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: 3,
      backgroundColor: _surface,
      elevation: 8,
      selectedItemColor: _blue,
      unselectedItemColor: _muted,
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
