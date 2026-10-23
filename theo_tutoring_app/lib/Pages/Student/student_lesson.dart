import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class AppColors {
  static const background = Color(0xFFF0F4FA);
  static const primary = Color(0xFF2A6BB2);
  static const textDark = Color(0xFF1E293B);
  static const textGrey = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
  static const cancelBg = Color(0xFFF1F5F9);
  static const confirmedBg = Color(0xFFDCFCE7);
  static const confirmedText = Color(0xFF16A34A);
  static const cancelledBg = Color(0xFFFEE2E2);
  static const cancelledText = Color(0xFFDC2626);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Schedule',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        // fontFamily: 'Inter', // add Inter to pubspec.yaml for an exact match
      ),
      home: const ScheduleScreen(),
    );
  }
}

class Lesson {
  final String tutorName;
  final String subject;
  final String duration;
  final String dateTime;
  final String status;
  final String? avatarUrl;
  final String? cancellationReason;

  const Lesson({
    required this.tutorName,
    required this.subject,
    required this.duration,
    required this.dateTime,
    required this.status,
    this.avatarUrl,
    this.cancellationReason,
  });
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  int _tabIndex = 0; // 0 = Upcoming, 1 = Cancelled
  int _navIndex = 1; // Lessons

  final List<Lesson> _upcoming = [
    Lesson(
      tutorName: 'Lerato M.',
      subject: 'Engineering',
      duration: '2 hrs',
      dateTime: 'Friday, Jan 17 • 11:30 AM',
      status: 'CONFIRMED',
      // avatarUrl: 'https://your-cdn.com/lerato.jpg',
    ),
  ];

  final List<Lesson> _cancelled = [];

  Future<void> _cancelLesson(Lesson lesson) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _CancellationReasonDialog(),
    );
    if (reason == null || !mounted) return;

    setState(() {
      _upcoming.remove(lesson);
      _cancelled.add(
        Lesson(
          tutorName: lesson.tutorName,
          subject: lesson.subject,
          duration: lesson.duration,
          dateTime: lesson.dateTime,
          status: 'CANCELLED',
          avatarUrl: lesson.avatarUrl,
          cancellationReason: reason,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final lessons = _tabIndex == 0 ? _upcoming : _cancelled;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildTabs(),
                  const SizedBox(height: 20),
                  if (lessons.isEmpty)
                    _buildEmptyState()
                  else
                    ...lessons.map(
                      (l) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: LessonCard(
                          lesson: l,
                          showActions: _tabIndex == 0,
                          onCancel: () => _cancelLesson(l),
                          onStart: () {},
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'My Schedule',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.menu, color: AppColors.textDark),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Row(
      children: [
        Expanded(child: _tabButton('Upcoming', 0)),
        const SizedBox(width: 12),
        Expanded(child: _tabButton('Cancelled', 1)),
      ],
    );
  }

  Widget _tabButton(String label, int index) {
    final selected = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textGrey,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Center(
        child: Text(
          'No lessons here yet',
          style: TextStyle(color: AppColors.textGrey, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: BottomNavigationBar(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 0,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textGrey,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined, size: 28),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined, size: 26),
            label: 'Lessons',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline, size: 26),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline, size: 28),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class LessonCard extends StatelessWidget {
  final Lesson lesson;
  final bool showActions;
  final VoidCallback onCancel;
  final VoidCallback onStart;

  const LessonCard({
    super.key,
    required this.lesson,
    required this.onCancel,
    required this.onStart,
    this.showActions = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Tutor row
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.cancelBg,
                backgroundImage: lesson.avatarUrl != null
                    ? NetworkImage(lesson.avatarUrl!)
                    : null,
                child: lesson.avatarUrl == null
                    ? const Icon(Icons.person, color: AppColors.textGrey)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson.tutorName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          lesson.subject,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '·',
                          style: TextStyle(color: AppColors.textGrey),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          lesson.duration,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _StatusBadge(label: lesson.status),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),

          // Date row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 20,
                  color: AppColors.textGrey,
                ),
                const SizedBox(width: 12),
                Text(
                  lesson.dateTime,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          if (lesson.cancellationReason != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Cancellation reason: ${lesson.cancellationReason}',
                style: const TextStyle(fontSize: 14, color: AppColors.textGrey),
              ),
            ),
          ],

          if (showActions) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Cancel',
                    background: AppColors.cancelBg,
                    foreground: AppColors.textGrey,
                    onTap: onCancel,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ActionButton(
                    label: 'Start session',
                    background: AppColors.primary,
                    foreground: Colors.white,
                    onTap: onStart,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  const _StatusBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final isCancelled = label == 'CANCELLED';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isCancelled ? AppColors.cancelledBg : AppColors.confirmedBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: isCancelled
              ? AppColors.cancelledText
              : AppColors.confirmedText,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

class _CancellationReasonDialog extends StatefulWidget {
  const _CancellationReasonDialog();

  @override
  State<_CancellationReasonDialog> createState() =>
      _CancellationReasonDialogState();
}

class _CancellationReasonDialogState extends State<_CancellationReasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel lesson?'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Why are you cancelling?',
            border: OutlineInputBorder(),
          ),
          validator: (value) => value == null || value.trim().length < 5
              ? 'Please enter at least 5 characters.'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep lesson'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Cancel lesson')),
      ],
    );
  }
}
