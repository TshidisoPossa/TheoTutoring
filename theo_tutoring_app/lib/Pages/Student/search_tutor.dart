import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../Booking/booking_flow_context.dart';
import '../Booking/booking_select_lesson.dart';
import '../../models/tutor.dart';
import '../../services/tutor_search_api.dart';
import 'student_tutor_profile.dart';

class SearchTutorPage extends StatefulWidget {
  const SearchTutorPage({super.key});

  @override
  State<SearchTutorPage> createState() => _SearchTutorPageState();
}

class _SearchTutorPageState extends State<SearchTutorPage> {
  static const Color _primaryBlue = Color(0xFF356AE6);
  static const Color _darkBlue = Color(0xFF173B8F);
  static const Color _background = Color(0xFFF7F9FE);
  static const Color _textDark = Color(0xFF17233D);
  static const Color _textMuted = Color(0xFF7B8498);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          'Find a Tutor',
          style: GoogleFonts.poppins(
            color: _textDark,
            fontSize: 19,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          tooltip: 'Go back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded, color: _textDark),
        ),
      ),
      body: SafeArea(
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
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Find the right tutor for you',
            style: GoogleFonts.poppins(
              color: _darkBlue,
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Search by name or subject and discover tutors for your studies.',
            style: GoogleFonts.poppins(
              color: _textMuted,
              fontSize: 12,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            onChanged: _searchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search tutor or subject...',
              hintStyle: GoogleFonts.poppins(color: _textMuted, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: _primaryBlue),
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
              fillColor: _background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE4EAF5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _primaryBlue, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Browse by subject',
            style: GoogleFonts.poppins(
              color: _textDark,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: _subjects.isEmpty
                ? const SizedBox.shrink()
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _subjects.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final subject = index == 0 ? null : _subjects[index - 1];
                      final selected = subject?.subjectId == _selectedSubjectId;
                      return ChoiceChip(
                        label: Text(subject?.subjectName ?? 'All'),
                        selected: selected,
                        showCheckmark: false,
                        onSelected: (_) => _selectSubject(subject?.subjectId),
                        labelStyle: GoogleFonts.poppins(
                          color: selected ? Colors.white : _textDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        backgroundColor: Colors.white,
                        selectedColor: _primaryBlue,
                        side: BorderSide(
                          color: selected
                              ? _primaryBlue
                              : const Color(0xFFE0E7F2),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                      );
                    },
                  ),
          ),
        ],
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
                onPressed: () => unawaited(_load(loadSubjects: _subjects.isEmpty)),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$_total tutors found',
              style: GoogleFonts.poppins(
                color: _textDark,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            children: _tutors.map(_buildTutorCard).toList(),
          ),
        ),
        if (pages > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
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
          ),
      ],
    );
  }

  Widget _buildTutorCard(Tutor tutor) {
    final initials = tutor.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EDF6)),
        boxShadow: [
          BoxShadow(
            color: _darkBlue.withValues(alpha: 0.035),
            blurRadius: 12,
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
                radius: 27,
                backgroundColor: const Color(0xFFE4ECFF),
                child: tutor.profilePhoto == null
                    ? Text(
                        initials,
                        style: GoogleFonts.poppins(
                          color: _darkBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : ClipOval(
                        child: Image.network(
                          tutor.profilePhoto!,
                          width: 54,
                          height: 54,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Text(
                            initials,
                            style: GoogleFonts.poppins(
                              color: _darkBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tutor.name,
                      style: GoogleFonts.poppins(
                        color: _textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tutor.averageRating == null
                          ? 'No reviews yet'
                          : '${tutor.averageRating!.toStringAsFixed(1)} '
                                '(${tutor.reviewCount} reviews)',
                      style: GoogleFonts.poppins(
                        color: _textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: tutor.subjects
                .map(
                  (subject) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF3FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      subject.subjectName,
                      style: GoogleFonts.poppins(
                        color: _darkBlue,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Text(
            tutor.experience ?? 'Experience not provided',
            style: GoogleFonts.poppins(color: _textMuted, fontSize: 11),
          ),
          const SizedBox(height: 7),
          Text(
            tutor.bio ?? 'Biography not provided.',
            style: GoogleFonts.poppins(
              color: _textDark,
              fontSize: 12,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            tutor.hourlyRate == null
                ? 'Hourly rate unavailable'
                : 'Hourly rate: ${tutor.hourlyRate!.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(color: _textMuted, fontSize: 11),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openProfile(tutor),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _darkBlue,
                    side: const BorderSide(color: Color(0xFFD9E3FF)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'View profile',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: tutor.subjects.isEmpty
                      ? null
                      : () => _chooseSubject(tutor),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryBlue,
                    side: const BorderSide(color: _primaryBlue),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Choose tutor',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
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
        const Icon(Icons.person_search_rounded, color: Color(0xFF9BAAC5), size: 54),
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
