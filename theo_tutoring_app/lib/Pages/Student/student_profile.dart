import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../Tutor/tutor_theme.dart';
import '../auth_gate.dart';
import '../cloudinary_upload.dart';
import '../privacy_policy.dart';
import '../faq_page.dart';
import '../terms_and_conditions.dart';
import 'student_profile_api.dart';

/// The student's Profile tab, laid out like the tutor's profile.
///
/// View mode: photo (camera badge changes it), name, email and school, then
/// Subjects of Interest, an Edit Profile button, Dark Mode, Support and
/// Log Out.
///
/// Edit Profile makes the name, school and subjects editable; Save Changes
/// sends them to PATCH /students/profile and the back arrow throws the
/// changes away.
///
/// Everything comes from GET /students/profile. The values the dashboard
/// passes in are shown straight away while that loads, and stay if it fails.
class StudentProfileTab extends StatefulWidget {
  const StudentProfileTab({
    super.key,
    this.name,
    this.email,
    this.institution,
    this.photo,
    this.loadProfile,
    this.saveProfile,
    this.loadSubjects,
    this.choosePhoto,
    this.onChanged,
  });

  final String? name;
  final String? email;
  final String? institution;
  final String? photo;

  /// Loads the profile; null uses [StudentProfileApi] (tests pass a fake).
  final Future<StudentProfileData> Function()? loadProfile;

  /// Saves changed fields; null uses [StudentProfileApi.update].
  final Future<StudentProfileSaved> Function(Map<String, Object?> changes)?
  saveProfile;

  /// The subject catalogue for the chips; null uses GET /subjects.
  final Future<List<String>> Function()? loadSubjects;

  /// Picks and uploads a photo, returning its Cloudinary URL (null when the
  /// student cancels); null uses the gallery and [uploadToCloudinary].
  final Future<String?> Function()? choosePhoto;

  /// Called after the name or photo changed, so the dashboard can refresh.
  final VoidCallback? onChanged;

  @override
  State<StudentProfileTab> createState() => _StudentProfileTabState();
}

class _StudentProfileTabState extends State<StudentProfileTab> {
  static const _blue = Color(0xFF356AE6);
  static const _red = Color(0xFFE05252);

  // Same limits as PATCH /students/profile
  static const _maxName = 100;
  static const _maxInstitution = 150;
  static const _maxSubjects = 10;

  StudentProfileApi? _api;
  StudentProfileData? _profile; // null until the server answers

  bool _editing = false;
  bool _saving = false;
  bool _uploading = false;

  // Edit Profile draft
  final _nameController = TextEditingController();
  final _institutionController = TextEditingController();
  List<String> _subjects = [];
  List<String>? _catalogue; // GET /subjects, loaded on the first edit
  bool _catalogueFailed = false;

  StudentProfileApi get _client => _api ??= StudentProfileApi();

  // The server's value, or the dashboard's while it loads or if it failed
  String? get name => _pick(_profile?.name, widget.name);
  String? get email => _pick(_profile?.email, widget.email);
  String? get institution =>
      _profile != null ? _profile!.institution : widget.institution;
  String? get photo => _profile != null ? _profile!.photo : widget.photo;

  static String? _pick(String? server, String? fallback) =>
      server != null && server.trim().isNotEmpty ? server : fallback;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_redraw);
    _institutionController.addListener(_redraw);
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _institutionController.dispose();
    _api?.close();
    super.dispose();
  }

  void _redraw() {
    if (mounted && _editing) setState(() {});
  }

  Future<void> _load() async {
    try {
      final load = widget.loadProfile ?? _client.fetch;
      final profile = await load();
      if (mounted) setState(() => _profile = profile);
    } catch (error) {
      // Keep showing what the dashboard passed in
      debugPrint('Student profile could not be loaded: $error');
    }
  }

  // ── Editing ────────────────────────────────────────────────────────────

  Future<void> _startEditing() async {
    if (_profile == null) {
      await _load();
      if (!mounted) return;
      if (_profile == null) {
        _showMessage(
          'Your profile could not be loaded. Please try again.',
          error: true,
        );
        return;
      }
    }
    final p = _profile!;
    setState(() {
      _nameController.text = p.name ?? '';
      _institutionController.text = p.institution ?? '';
      _subjects = [...p.subjectsOfInterest];
      _editing = true;
    });
    if (_catalogue == null) _loadCatalogue();
  }

  Future<void> _loadCatalogue() async {
    setState(() => _catalogueFailed = false);
    try {
      final load = widget.loadSubjects ?? _client.fetchSubjects;
      final subjects = await load();
      if (mounted) setState(() => _catalogue = subjects);
    } catch (error) {
      debugPrint('Subjects could not be loaded: $error');
      if (mounted) setState(() => _catalogueFailed = true);
    }
  }

  /// The fields that differ from the saved profile.
  Map<String, Object?> get _changes {
    final p = _profile;
    if (p == null) return const {};
    final name = _nameController.text.trim();
    final school = _institutionController.text.trim();
    return {
      if (name != (p.name ?? '').trim()) 'name': name,
      if (school != (p.institution ?? '').trim()) 'institution': school,
      if (!_sameList(_subjects, p.subjectsOfInterest))
        'subjectsOfInterest': _subjects,
    };
  }

  static bool _sameList(List<String> a, List<String> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

  /// Why Save Changes is off, or null when the draft can be saved.
  String? get _problem {
    if (_nameController.text.trim().isEmpty) return 'Enter your name.';
    if (_institutionController.text.trim().isEmpty) {
      return 'Enter your school or university.';
    }
    if (_subjects.isEmpty) return 'Choose at least one subject.';
    return null;
  }

  Future<void> _cancelEditing() async {
    if (_changes.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('Your changes have not been saved.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Discard', style: TextStyle(color: _red)),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _editing = false);
  }

  Future<void> _save() async {
    final problem = _problem;
    if (problem != null) {
      _showMessage(problem, error: true);
      return;
    }
    final changes = _changes;
    if (changes.isEmpty) {
      setState(() => _editing = false);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final save = widget.saveProfile ?? _client.update;
      final saved = await save(changes);
      if (!mounted) return;
      setState(() {
        _profile = saved.profile;
        _editing = false;
        _saving = false;
      });
      _showMessage(saved.message);
      if (changes.containsKey('name')) widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(error.toString(), error: true);
    }
  }

  // Camera badge: pick a picture, upload it to Cloudinary, save its URL.
  Future<void> _changePhoto() async {
    setState(() => _uploading = true);
    try {
      final url = await (widget.choosePhoto ?? _pickAndUpload)();
      if (url == null) {
        if (mounted) setState(() => _uploading = false);
        return;
      }
      final save = widget.saveProfile ?? _client.update;
      final saved = await save({'photo': url});
      if (!mounted) return;
      setState(() {
        _profile = saved.profile;
        _uploading = false;
      });
      _showMessage(saved.message);
      widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _showMessage(switch (error) {
        StudentProfileException(:final message) => message,
        CloudinaryUploadException(:final message) => message,
        _ => 'Could not upload the photo.',
      }, error: true);
    }
  }

  static Future<String?> _pickAndUpload() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    return file == null ? null : uploadToCloudinary(file);
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? const Color(0xFFDC2626) : null,
        ),
      );
  }

  // ── Page ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = _ProfileColors.of(context);
    final children = _editing ? _editView(colors) : _profileView(colors);
    return ColoredBox(
      color: colors.background,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _editing ? () async {} : _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0) const SizedBox(height: 16),
                        children[i],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _profileView(_ProfileColors colors) {
    final p = _profile;
    return [
      Text(
        'My Profile',
        style: GoogleFonts.poppins(
          color: colors.text,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      _headerCard(colors),
      _card(
        colors,
        title: 'Subjects of Interest',
        child: p == null || p.subjectsOfInterest.isEmpty
            ? _placeholder(colors, 'No subjects chosen yet')
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final subject in p.subjectsOfInterest)
                    _chip(colors, subject, selected: true),
                ],
              ),
      ),
      _primaryButton('Edit Profile', onPressed: _startEditing),
      _listCard(colors, 'Preferences', [
        _row(
          colors,
          icon: Icons.dark_mode_outlined,
          title: 'Dark Mode',
          trailing: Switch(
            value: TutorTheme.darkChosen,
            activeThumbColor: Colors.white,
            activeTrackColor: _blue,
            // The whole app rebuilds in the new theme
            onChanged: (on) => TutorTheme.setDark(on),
          ),
          onTap: () => TutorTheme.setDark(!TutorTheme.darkChosen),
        ),
      ]),
      _listCard(colors, 'Support', [
        _row(
          colors,
          icon: Icons.quiz_outlined,
          title: 'FAQ',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  const FaqPage(initialAudience: FaqAudience.students),
            ),
          ),
        ),
        _row(
          colors,
          icon: Icons.description_outlined,
          title: 'Terms of Service',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const TermsAndConditionsPage(),
            ),
          ),
        ),
        _row(
          colors,
          icon: Icons.privacy_tip_outlined,
          title: 'Privacy Policy',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyPage()),
          ),
        ),
      ]),
      _logOutCard(colors),
    ];
  }

  List<Widget> _editView(_ProfileColors colors) {
    final catalogue = _catalogue ?? const <String>[];
    // Catalogue subjects, then any the student typed at registration
    final subjectChoices = [
      ...catalogue,
      for (final s in _subjects)
        if (!catalogue.any((c) => c.toLowerCase() == s.toLowerCase())) s,
    ];

    return [
      Row(
        children: [
          IconButton(
            onPressed: _saving ? null : _cancelEditing,
            tooltip: 'Back',
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.text),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Text(
            'Edit Profile',
            style: GoogleFonts.poppins(
              color: colors.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      _card(
        colors,
        child: Row(
          children: [
            _photoWithBadge(colors, radius: 44),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  _textField(
                    colors,
                    _nameController,
                    hint: 'Full name',
                    maxLength: _maxName,
                  ),
                  const SizedBox(height: 10),
                  _textField(
                    colors,
                    _institutionController,
                    hint: 'School or university',
                    maxLength: _maxInstitution,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      _card(
        colors,
        title: 'Subjects of Interest',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_catalogue == null && !_catalogueFailed)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final subject in subjectChoices)
                  _chip(
                    colors,
                    subject,
                    selected: _subjects.contains(subject),
                    onTap: () => _toggleSubject(subject),
                  ),
              ],
            ),
            if (_catalogueFailed) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _loadCatalogue,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Could not load subjects. Try again'),
              ),
            ],
          ],
        ),
      ),
      _primaryButton(
        'Save Changes',
        busy: _saving,
        onPressed: _saving ? null : _save,
      ),
    ];
  }

  void _toggleSubject(String subject) {
    setState(() {
      if (_subjects.contains(subject)) {
        _subjects.remove(subject);
      } else if (_subjects.length >= _maxSubjects) {
        _showMessage('Choose up to $_maxSubjects subjects.', error: true);
      } else {
        _subjects.add(subject);
      }
    });
  }

  // ── Pieces ─────────────────────────────────────────────────────────────

  Widget _headerCard(_ProfileColors colors) {
    final displayName = name == null || name!.trim().isEmpty
        ? 'Student'
        : name!.trim();
    final school = institution == null || institution!.trim().isEmpty
        ? null
        : institution!.trim();
    return _card(
      colors,
      child: Row(
        children: [
          _photoWithBadge(colors, radius: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: GoogleFonts.poppins(
                    color: colors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (email != null && email!.isNotEmpty)
                  Text(
                    email!,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: colors.muted,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 8),
                _badge(colors, 'STUDENT'),
                if (school != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.school_outlined,
                        size: 16,
                        color: colors.muted,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          school,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            color: colors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoWithBadge(_ProfileColors colors, {required double radius}) {
    final displayName = (name ?? '').trim().isEmpty ? 'Student' : name!;
    final url = photo;
    final initials = Text(
      _initials(displayName),
      style: GoogleFonts.poppins(
        color: colors.blueText,
        fontSize: radius * 0.6,
        fontWeight: FontWeight.w700,
      ),
    );
    return Semantics(
      button: true,
      label: 'Change profile photo',
      child: GestureDetector(
        onTap: _uploading || _saving ? null : _changePhoto,
        child: Stack(
          children: [
            CircleAvatar(
              radius: radius,
              backgroundColor: colors.blueTint,
              child: _uploading
                  ? const CircularProgressIndicator(color: _blue)
                  : url == null
                  ? initials
                  : ClipOval(
                      child: Image.network(
                        url,
                        width: radius * 2,
                        height: radius * 2,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Center(child: initials),
                      ),
                    ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: _blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(_ProfileColors colors, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: colors.blueTint,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: colors.blueText,
      ),
    ),
  );

  // A white card, with a bold title when given
  Widget _card(_ProfileColors colors, {String? title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title,
              style: GoogleFonts.poppins(
                color: colors.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }

  Widget _placeholder(_ProfileColors colors, String text) => Text(
    text,
    style: GoogleFonts.poppins(color: colors.faint, fontSize: 13),
  );

  // Filled blue when chosen, grey otherwise; tappable when [onTap] is set
  Widget _chip(
    _ProfileColors colors,
    String label, {
    bool selected = false,
    VoidCallback? onTap,
  }) {
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? colors.chipSelected : colors.field,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: selected ? Colors.white : colors.text,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: chip,
      ),
    );
  }

  Widget _textField(
    _ProfileColors colors,
    TextEditingController controller, {
    required String hint,
    required int maxLength,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      enabled: !_saving,
      textCapitalization: TextCapitalization.words,
      style: GoogleFonts.poppins(color: colors.text, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(color: colors.faint, fontSize: 13),
        counterText: '',
        filled: true,
        fillColor: colors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _blue, width: 1.5),
        ),
      ),
    );
  }

  Widget _primaryButton(
    String label, {
    required VoidCallback? onPressed,
    bool busy = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _blue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _blue.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: busy
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _logOutCard(_ProfileColors colors) {
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => signOutToStart(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.logout_rounded, color: _red, size: 20),
              const SizedBox(width: 8),
              Text(
                'Log Out',
                style: GoogleFonts.poppins(
                  color: _red,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // A card with a title and tappable rows separated by lines
  Widget _listCard(_ProfileColors colors, String title, List<Widget> rows) {
    // Material, so the rows' tap ripple shows on the card
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Text(
              title,
              style: GoogleFonts.poppins(
                color: colors.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final row in rows) ...[
            Divider(height: 1, color: colors.line),
            row,
          ],
        ],
      ),
    );
  }

  Widget _row(
    _ProfileColors colors, {
    required IconData icon,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      leading: Icon(icon, color: colors.blueText, size: 22),
      title: Text(
        title,
        style: GoogleFonts.poppins(fontSize: 14, color: colors.text),
      ),
      trailing:
          trailing ?? Icon(Icons.chevron_right_rounded, color: colors.muted),
      onTap: onTap,
    );
  }

  // "Lerato Dube" -> "LD"
  static String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
}

/// Light colours, or the dark ones while dark mode is on.
class _ProfileColors {
  const _ProfileColors(this.dark);

  factory _ProfileColors.of(BuildContext context) =>
      _ProfileColors(context.tutorDark);

  final bool dark;

  Color get background => dark ? TutorDark.background : const Color(0xFFF7F9FE);
  Color get surface => dark ? TutorDark.card : Colors.white;
  Color get field => dark ? TutorDark.cardAlt : const Color(0xFFF1F4F9);
  Color get line => dark ? TutorDark.border : const Color(0xFFE3E8F0);
  Color get text => dark ? TutorDark.text : const Color(0xFF17233D);
  Color get muted => dark ? TutorDark.textMuted : const Color(0xFF5B6478);
  Color get faint => dark ? TutorDark.textFaint : const Color(0xFF9AA3B5);
  Color get blueText => dark ? TutorDark.blueText : const Color(0xFF356AE6);
  Color get blueTint => dark ? TutorDark.blueTint : const Color(0xFFE4ECFF);
  Color get chipSelected =>
      dark ? const Color(0xFF3D6FE0) : const Color(0xFF2F5FAF);
}
