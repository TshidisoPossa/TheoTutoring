import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../Booking/booking_flow_context.dart';
import '../Booking/booking_select_lesson.dart';
import '../../models/tutor.dart';
import '../../services/tutor_search_api.dart';
import 'student_bottom_nav.dart';
import 'student_tutor_profile.dart';

/// Find a Tutor. Pops with the bottom-nav tab the student tapped (0 Home,
/// 1 Lessons, ...) so the dashboard can switch to it.
class SearchTutorPage extends StatefulWidget {
  const SearchTutorPage({super.key, this.studentName, this.studentPhoto});

  /// For the avatar in the header (initials when there is no photo).
  final String? studentName;
  final String? studentPhoto;

  @override
  State<SearchTutorPage> createState() => _SearchTutorPageState();
}

class _SearchTutorPageState extends State<SearchTutorPage> {
  static const Color _brandBlue = Color(0xFF0B4FC8);
  static const Color _darkBlue = Color(0xFF173B8F);
  static const Color _background = Color(0xFFF7F8FC);
  static const Color _fieldFill = Color(0xFFEEF1FA);
  static const Color _textDark = Color(0xFF17233D);
  static const Color _textMuted = Color(0xFF6B7385);
  static const Color _tagFill = Color(0xFFE8ECF6);
  static const Color _tagText = Color(0xFF4A5470);
  static const Color _star = Color(0xFFF5B301);

  final _searchController = TextEditingController();
  final _api = TutorSearchApi();
  Timer? _debounce;
  int _requestVersion = 0;
  int _page = 1;
  int _total = 0;
  int? _selectedSubjectId;
  List<TutorSubject> _subjects = const [];
  List<Tutor> _tutors = const [];
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load(loadSubjects: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _load({bool loadSubjects = false}) async {
    final version = ++_requestVersion;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final subjectsFuture = loadSubjects
          ? _api.subjects()
          : Future<List<TutorSubject>>.value(_subjects);
      final results = await Future.wait([
        subjectsFuture,
        _api.search(
          query: _searchController.text,
          subjectId: _selectedSubjectId,
          page: _page,
        ),
      ]);
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _subjects = results[0] as List<TutorSubject>;
        final resultPage = results[1] as TutorSearchPage;
        _tutors = resultPage.tutors;
        _page = resultPage.page;
        _total = resultPage.total;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _error = error is TutorSearchException
            ? error.message
            : 'Could not load tutors. Check your connection and retry.';
        _isLoading = false;
      });
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _requestVersion++;
    _page = 1;
    setState(() => _isLoading = true);
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_load()),
    );
  }

  void _selectSubject(int? id) {
    setState(() {
      _selectedSubjectId = id;
      _page = 1;
    });
    unawaited(_load());
  }

  void _openProfile(Tutor tutor) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudentTutorProfilePage(tutor: tutor),
      ),
    );
  }

  Future<void> _chooseSubject(Tutor tutor) async {
    final subject = await showModalBottomSheet<TutorSubject>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Choose a subject',
              style: GoogleFonts.poppins(
                color: _textDark,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            ...tutor.subjects.map(
              (item) => ListTile(
                title: Text(item.subjectName),
                onTap: () => Navigator.pop(context, item),
              ),
            ),
          ],
        ),
      ),
    );
    if (subject != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BookingSelectLessonPage(
            flow: BookingFlowContext(tutor: tutor, subject: subject),
          ),
        ),
      );
    }
  }

  static String _initials(String? name) => (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(72),
        child: _buildTopBar(),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                _buildSearchHeader(),
                Expanded(child: _buildResults()),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: StudentBottomNav(
        currentIndex: 0,
        onTap: (index) => Navigator.of(context).pop(index),
      ),
    );
  }

  Widget _buildTopBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 20,
      title: Row(
        children: [
          Image.asset(
            'assets/logo.png',
            height: 40,
            width: 40,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: _brandBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.school_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Find a Tutor',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: _brandBlue,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 18),
          child: _buildStudentAvatar(),
        ),
      ],
    );
  }

  Widget _buildStudentAvatar() {
    final fallback = Text(
      _initials(widget.studentName),
      style: GoogleFonts.poppins(
        color: _brandBlue,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
    final photo = widget.studentPhoto;
    return CircleAvatar(
      radius: 20,
      backgroundColor: const Color(0xFFE4ECFF),
      child: photo == null
          ? fallback
          : ClipOval(
              child: Image.network(
                photo,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(child: fallback),
              ),
            ),
    );
  }

  Widget _buildSearchHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: _searchChanged,
            textInputAction: TextInputAction.search,
            style: GoogleFonts.poppins(color: _textDark, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search tutors...',
              hintStyle: GoogleFonts.poppins(color: _textMuted, fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded, color: _textDark),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        _searchChanged('');
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: _fieldFill,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _brandBlue, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: _subjects.isEmpty
                ? const SizedBox.shrink()
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _subjects.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final subject = index == 0 ? null : _subjects[index - 1];
                      return _buildSubjectChip(subject);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectChip(TutorSubject? subject) {
    final selected = subject?.subjectId == _selectedSubjectId;
    return Material(
      color: selected ? _brandBlue : _fieldFill,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => _selectSubject(subject?.subjectId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Center(
            child: Text(
              subject?.subjectName ?? 'All',
              style: GoogleFonts.poppins(
                color: selected ? Colors.white : _textDark,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    unawaited(_load(loadSubjects: _subjects.isEmpty)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_tutors.isEmpty) {
      return _buildEmptyState();
    }
    final pages = (_total / 20).ceil();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        ..._tutors.map(_buildTutorCard),
        if (pages > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _page > 1
                    ? () {
                        setState(() => _page--);
                        unawaited(_load());
                      }
                    : null,
                child: const Text('Previous'),
              ),
              Text('Page $_page of $pages'),
              TextButton(
                onPressed: _page < pages
                    ? () {
                        setState(() => _page++);
                        unawaited(_load());
                      }
                    : null,
                child: const Text('Next'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildTutorCard(Tutor tutor) {
    final initials = _initials(tutor.name);
    final firstName = tutor.name.trim().split(RegExp(r'\s+')).first;
    final rating = tutor.averageRating;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _darkBlue.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: const Color(0xFFE4ECFF),
                child: tutor.profilePhoto == null
                    ? Text(
                        initials,
                        style: GoogleFonts.poppins(
                          color: _darkBlue,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : ClipOval(
                        child: Image.network(
                          tutor.profilePhoto!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Text(
                            initials,
                            style: GoogleFonts.poppins(
                              color: _darkBlue,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tutor.name,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        color: _textDark,
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (tutor.qualification != null)
                      Text(
                        tutor.qualification!,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: _textMuted,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          rating == null
                              ? Icons.star_border_rounded
                              : Icons.star_rounded,
                          color: _star,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        if (rating != null) ...[
                          Text(
                            rating.toStringAsFixed(1),
                            style: GoogleFonts.poppins(
                              color: _textDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            rating == null
                                ? 'New tutor · no reviews yet'
                                : '(${tutor.reviewCount} '
                                      '${tutor.reviewCount == 1 ? 'review' : 'reviews'})',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: _textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            tutor.bio ?? 'This tutor has not written a bio yet.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              color: _textDark.withValues(alpha: 0.85),
              fontSize: 14,
              height: 1.55,
            ),
          ),
          if (tutor.subjects.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tutor.subjects
                  .map(
                    (subject) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _tagFill,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        subject.subjectName,
                        style: GoogleFonts.poppins(
                          color: _tagText,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (tutor.hourlyRate != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.sell_outlined, size: 16, color: _brandBlue),
                const SizedBox(width: 6),
                Text(
                  'R${tutor.hourlyRate!.toStringAsFixed(2)} per session',
                  style: GoogleFonts.poppins(
                    color: _brandBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message:
                      "See $firstName's qualifications, reviews and "
                      'availability',
                  child: OutlinedButton.icon(
                    onPressed: () => _openProfile(tutor),
                    icon: const Icon(Icons.account_circle_outlined, size: 19),
                    label: const Text('View Profile'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _brandBlue,
                      backgroundColor: const Color(0xFFE6EDFF),
                      side: const BorderSide(color: Color(0xFFC3D4FF)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Tooltip(
                  message: tutor.subjects.isEmpty
                      ? '$firstName has not added any subjects yet'
                      : 'Choose a subject and time with $firstName',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: tutor.subjects.isEmpty
                          ? null
                          : [
                              BoxShadow(
                                color: _brandBlue.withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                    ),
                    child: FilledButton.icon(
                      onPressed: tutor.subjects.isEmpty
                          ? null
                          : () => _chooseSubject(tutor),
                      icon: const Icon(Icons.event_available_rounded, size: 19),
                      label: const Text('Book Session'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _brandBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 55, horizontal: 20),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.person_search_rounded,
          color: Color(0xFF9BAAC5),
          size: 54,
        ),
        const SizedBox(height: 12),
        Text(
          'No tutors found',
          style: GoogleFonts.poppins(
            color: _textDark,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Try another name or choose a different subject.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(color: _textMuted, fontSize: 12),
        ),
      ],
    ),
  );
}
