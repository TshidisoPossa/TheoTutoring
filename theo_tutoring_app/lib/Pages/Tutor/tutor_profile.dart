import 'package:flutter/material.dart';

class TutorProfileScreen extends StatefulWidget {
  const TutorProfileScreen({super.key});

  @override
  State<TutorProfileScreen> createState() => _TutorProfileScreenState();
}

class _TutorProfileScreenState extends State<TutorProfileScreen> {
  bool _editMode = false;

  final List<String> _subjects = ['Maths', 'Science', 'Accounting', 'Statistics'];
  final List<String> _curriculum = ['CAPS', 'IEB', 'University'];
  final List<String> _selectedSubjects = ['Maths', 'Science', 'Statistics'];
  final List<String> _selectedCurriculum = ['CAPS', 'IEB'];

  final List<String> _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final List<String> _slots = ['Morning', 'Afternoon', 'Evening'];

  // true = available for that slot
  final List<List<bool>> _availability = [
    [true, true, true, true, false, false, false],   // Morning
    [false, true, true, false, true, true, false],   // Afternoon
    [true, true, false, false, true, false, false],  // Evening
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Top bar
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
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
                CircleAvatar(
                  radius: 36,
                  backgroundColor: const Color(0xFFD0E4FF),
                  child: const Icon(Icons.person, size: 36, color: Color(0xFF1457D9)),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Joseph Mungula',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      text: const TextSpan(
                        text: 'Hourly Rate:  ',
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                        children: [
                          TextSpan(
                            text: 'R250 / hr',
                            style: TextStyle(
                              color: Color(0xFF1457D9),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // About Me
            _sectionCard(
              title: 'About Me',
              child: const Text(
                'Passionate educator with 5+ years of experience in Mathematics and Engineering. I believe in making complex concepts simple and accessible. My approach combines practical examples with theoretical foundations to help students truly understand the material.',
                style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.5),
              ),
            ),
            const SizedBox(height: 16),

            // Subjects & Curriculum
            _sectionCard(
              title: 'Subjects & Curriculum',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SUBJECTS', style: TextStyle(color: Colors.black38, fontSize: 11, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _subjects.map((s) {
                      final selected = _selectedSubjects.contains(s);
                      return _chip(s, selected);
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('CURRICULUM', style: TextStyle(color: Colors.black38, fontSize: 11, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _curriculum.map((c) {
                      final selected = _selectedCurriculum.contains(c);
                      return _chip(c, selected, outlined: !selected);
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Qualifications
            _sectionCard(
              title: 'Qualifications',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.school_outlined, color: Color(0xFF1457D9), size: 20),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('BSc Engineering',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
                          Text('University of Pretoria',
                              style: TextStyle(color: Colors.black45, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {},
                    child: const Row(
                      children: [
                        Icon(Icons.add, color: Color(0xFF1457D9), size: 18),
                        SizedBox(width: 4),
                        Text('Add Qualification',
                            style: TextStyle(color: Color(0xFF1457D9), fontSize: 13, fontWeight: FontWeight.w500)),
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
                    onChanged: (val) => setState(() => _editMode = val),
                    activeColor: const Color(0xFF1457D9),
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
                              child: Text(d,
                                  style: const TextStyle(
                                      color: Colors.black45, fontSize: 11, fontWeight: FontWeight.w500)),
                            ),
                          )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Rows
                  ..._slots.asMap().entries.map((slotEntry) {
                    final slotIndex = slotEntry.key;
                    final slotName = slotEntry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 70,
                            child: Text(slotName,
                                style: const TextStyle(color: Colors.black54, fontSize: 12)),
                          ),
                          ..._availability[slotIndex].asMap().entries.map((dayEntry) {
                            final dayIndex = dayEntry.key;
                            final isAvailable = dayEntry.value;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _availability[slotIndex][dayIndex] = !_availability[slotIndex][dayIndex];
                                }),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: isAvailable
                                        ? const Color(0xFF1457D9)
                                        : const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1457D9),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Save Changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _chip(String label, bool selected, {bool outlined = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF1457D9) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? const Color(0xFF1457D9) : Colors.grey[300]!,
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
      selectedItemColor: const Color(0xFF1457D9),
      unselectedItemColor: Colors.black38,
      type: BottomNavigationBarType.fixed,
      selectedFontSize: 11,
      unselectedFontSize: 11,
      onTap: (index) {},
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.menu_book_outlined), label: 'Lessons'),
        BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
    );
  }
}