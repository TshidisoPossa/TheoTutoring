import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFFF7F8FE);
  static const card = Colors.white;
  static const primary = Color(0xFF1A6FE8);
  static const chip = Color(0xFFDDE3FA);
  static const chipIdle = Color(0xFFEEF0FB);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF5B6275);
  static const star = Color(0xFFFFB347);
  static const starOff = Color(0xFFE3E6F0);
}

class ReviewApp extends StatelessWidget {
  const ReviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Leave A Review',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorSchemeSeed: AppColors.primary,
        // To match the mockup more closely, add `google_fonts` and use
        // GoogleFonts.plusJakartaSansTextTheme() here.
      ),
      home: const LeaveReviewScreen(),
    );
  }
}

class LeaveReviewScreen extends StatefulWidget {
  const LeaveReviewScreen({super.key});

  @override
  State<LeaveReviewScreen> createState() => _LeaveReviewScreenState();
}

class _LeaveReviewScreenState extends State<LeaveReviewScreen> {
  static const int maxChars = 500;

  int _rating = 5;
  final Set<String> _selected = {
    'Clear Explanations',
    'Punctual & Prepared',
    'Patient with Questions',
    'Great Practice Problems',
  };
  final _reviewController = TextEditingController();
  final _noteController = TextEditingController();
  bool _noteOpen = false;

  static const _ratingLabels = {
    1: 'Poor',
    2: 'Fair',
    3: 'Good',
    4: 'Great!',
    5: 'Outstanding!',
  };

  static const _badges = <String>[
    ('Clear Explanations'),
    ('Punctual & Prepared'),
    ('Patient with Questions'),
    ('Great Practice Problems'),
    ('Encouraging Atmosphere'),
    ('Helpful Whiteboard Notes'),
  ];

  @override
  void dispose() {
    _reviewController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Review submitted: $_rating★, ${_selected.length} highlights',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _TopBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  const _SessionCard(),
                  const SizedBox(height: 16),
                  _RatingCard(
                    rating: _rating,
                    label: _ratingLabels[_rating]!,
                    onChanged: (v) => setState(() => _rating = v),
                  ),
                  const SizedBox(height: 16),
                  _HighlightsCard(
                    badges: _badges,
                    selected: _selected,
                    onToggle: (name) => setState(() {
                      _selected.contains(name)
                          ? _selected.remove(name)
                          : _selected.add(name);
                    }),
                  ),
                  const SizedBox(height: 16),
                  _ReviewCard(
                    reviewController: _reviewController,
                    noteController: _noteController,
                    maxChars: maxChars,
                    noteOpen: _noteOpen,
                    onToggleNote: () => setState(() => _noteOpen = !_noteOpen),
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.send_outlined, size: 22),
                      label: const Text('Submit Review'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {},
                        child: const Text('Skip for now',
                            style: _linkStyle),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.circle,
                            size: 5, color: Color(0xFFC3C8D6)),
                      ),
                      TextButton(
                        onPressed: () {},
                        child: const Text('Need help with this session?',
                            style: _linkStyle),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _linkStyle = TextStyle(
  color: AppColors.muted,
  fontSize: 15,
  fontWeight: FontWeight.w400,
);

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F1A2A6C),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: AppColors.background,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.school, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Leave A Review',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.ink,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_outline,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.close, color: AppColors.ink, size: 28),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.chip,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 22, color: AppColors.ink),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.schedule, size: 20, color: AppColors.muted),
              const SizedBox(width: 4),
              const Text('60 mins',
                  style: TextStyle(fontSize: 16, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.chipIdle,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const CircleAvatar(
                      radius: 32,
                      backgroundColor: Color(0xFFC9D2F2),
                      
                      child: Icon(Icons.person,
                          size: 36, color: Colors.white),
                    ),// backgroundImage: AsserImage(...)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.verified,
                            size: 22, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 18),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dr. Elena Rostova',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Senior Math & Physics Mentor',
                        style:
                            TextStyle(fontSize: 16, color: AppColors.muted),
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.star, size: 18, color: AppColors.star),
                          SizedBox(width: 4),
                          Text('4.9',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.muted)),
                          SizedBox(width: 6),
                          Text('(142 reviews)',
                              style: TextStyle(
                                  fontSize: 16, color: AppColors.muted)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 20, color: AppColors.ink),
              SizedBox(width: 6),
              Text('Today, 3:00 PM - 5:00 PM',
                  style: TextStyle(fontSize: 16, color: AppColors.ink)),
              Spacer(),
              Text('..........',
                  style: TextStyle(fontSize: 16, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------- Star rating ----------
class _RatingCard extends StatelessWidget {
  final int rating;
  final String label;
  final ValueChanged<int> onChanged;

  const _RatingCard({
    required this.rating,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        children: [
          const Text(
            'How was your session?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your feedback helps tutors grow and guides fellow students.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, height: 1.3, color: AppColors.muted),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(5, (i) {
              final filled = i < rating;
              return GestureDetector(
                onTap: () => onChanged(i + 1),
                child: AnimatedScale(
                  scale: filled ? 1 : 0.92,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.star_rounded,
                    size: 58,
                    color: filled ? AppColors.star : AppColors.starOff,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.chipIdle,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _HighlightsCard extends StatelessWidget {
  final List<(String, String)> badges;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _HighlightsCard({
    required this.badges,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'What made this session great?',
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              SizedBox(width: 16),
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Multi-\nselect',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            "Tap highlight badges that applied to today's calculus lesson:",
            style: TextStyle(fontSize: 18, height: 1.3, color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 12,
            children: [
              for (final (emoji, name) in badges)
                _BadgeChip(
                  label: name,
                  selected: selected.contains(name),
                  onTap: () => onToggle(name),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BadgeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.chip : AppColors.chipIdle,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 20, color: AppColors.ink),
              const SizedBox(width: 8),
            ],
            Text(
              '$label',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.ink : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final TextEditingController reviewController;
  final TextEditingController noteController;
  final int maxChars;
  final bool noteOpen;
  final VoidCallback onToggleNote;
  final VoidCallback onChanged;

  const _ReviewCard({
    required this.reviewController,
    required this.noteController,
    required this.maxChars,
    required this.noteOpen,
    required this.onToggleNote,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Public Review for tutor',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Icon(Icons.public, size: 28, color: AppColors.muted),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            "This review will be visible on tutor's public tutor profile.",
            style: TextStyle(fontSize: 17, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: reviewController,
            maxLines: 5,
            minLines: 5,
            maxLength: maxChars,
            onChanged: (_) => onChanged(),
            style: const TextStyle(fontSize: 18, color: AppColors.ink),
            buildCounter: (context,
                    {required currentLength,
                    required isFocused,
                    required maxLength}) =>
                Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$currentLength / $maxLength',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ),
            decoration: InputDecoration(
              hintText: 'Share what stood out in the session…',
              hintStyle: const TextStyle(color: Color(0xFF9AA1B5)),
              filled: true,
              fillColor: AppColors.chipIdle,
              contentPadding: const EdgeInsets.all(16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onToggleNote,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.chipIdle,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline,
                      size: 24, color: AppColors.ink),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Private note for tutor or platform support',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: noteOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: AppColors.ink),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: noteOpen
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: noteController,
                      maxLines: 3,
                      style: const TextStyle(
                          fontSize: 17, color: AppColors.ink),
                      decoration: InputDecoration(
                        hintText: 'Only the tutor and support team can see this',
                        hintStyle:
                            const TextStyle(color: Color(0xFF9AA1B5)),
                        filled: true,
                        fillColor: AppColors.chipIdle,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}