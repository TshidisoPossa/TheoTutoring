import 'package:flutter/material.dart';

class TutorSettings extends StatefulWidget {
  const TutorSettings({super.key});

  @override
  State<TutorSettings> createState() => _TutorSettingsState();
}

class _TutorSettingsState extends State<TutorSettings> {
  bool sessionReminders = true;
  bool newBookingAlerts = true;
  bool directMessages = true;
  bool newReviews = false;
  bool darkMode = false;
  int _selectedIndex = 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.more_vert, color: Colors.black),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionCard([
              const Text('Account Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 12),
              const Text('Email Address', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              _inputBox('joseph.mungula@example.com'),
              const SizedBox(height: 12),
              const Text('Phone Number', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              _inputBox('+27 82 123 4567'),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('Change Password', style: TextStyle(fontSize: 14)),
                  Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ]),
            const SizedBox(height: 16),
            _sectionCard([
              const Text('Notification Preferences', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 12),
              _toggleRow('Session Reminders', 'Before upcoming tutoring session starts', sessionReminders, (val) => setState(() => sessionReminders = val)),
              const Divider(height: 24),
              _toggleRow('New Booking Alerts', 'When a student sends a session request', newBookingAlerts, (val) => setState(() => newBookingAlerts = val)),
              const Divider(height: 24),
              _toggleRow('Direct Messages', 'When you receive new messages from students', directMessages, (val) => setState(() => directMessages = val)),
              const Divider(height: 24),
              _toggleRow('New Reviews', 'Get notified when a student gives feedback', newReviews, (val) => setState(() => newReviews = val)),
            ]),
            const SizedBox(height: 16),
            _sectionCard([
              const Text('Payment Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('Payout Bank Account', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  Text('FNB (*5678)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('View Payout History', style: TextStyle(fontSize: 14)),
                  Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ]),
            const SizedBox(height: 16),
            _sectionCard([
              const Text('App Preferences', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('App Language', style: TextStyle(fontSize: 14)),
                  Row(children: [
                    Text('English', style: TextStyle(fontSize: 14, color: Colors.grey)),
                    Icon(Icons.chevron_right, color: Colors.grey),
                  ]),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Dark Mode', style: TextStyle(fontSize: 14)),
                  Switch(value: darkMode, onChanged: (val) => setState(() => darkMode = val), activeColor: const Color(0xFF1A73E8)),
                ],
              ),
            ]),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1A73E8),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.book_outlined), label: 'Lessons'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _sectionCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _inputBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: const TextStyle(fontSize: 14)),
    );
  }

  Widget _toggleRow(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ),
        Switch(value: value, onChanged: onChanged, activeColor: const Color(0xFF1A73E8)),
      ],
    );
  }
}