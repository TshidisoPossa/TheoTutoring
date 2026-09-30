import 'package:flutter/material.dart';

class StudentSettings extends StatefulWidget {
  const StudentSettings({super.key});

  @override
  State<StudentSettings> createState() => _StudentSettingsState();
}

class _StudentSettingsState extends State<StudentSettings> {
  bool sessionReminders = true;
  bool bookingConfirmations = true;
  bool directMessages = true;
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
              _inputBox('lerato.p@example.com'),
              const SizedBox(height: 12),
              const Text('Phone Number', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              _inputBox('+27 73 987 6543'),
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
              _toggleRow('Session Reminders', '24 hours before your session starts', sessionReminders, (val) => setState(() => sessionReminders = val)),
              const Divider(height: 24),
              _toggleRow('Booking Confirmations', 'When tutor accepts your request', bookingConfirmations, (val) => setState(() => bookingConfirmations = val)),
              const Divider(height: 24),
              _toggleRow('Direct Messages', 'New messages from your active tutors', directMessages, (val) => setState(() => directMessages = val)),
            ]),
            const SizedBox(height: 16),
            _sectionCard([
              const Text('Payment Methods', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 12),
              Row(
                children: const [
                  Icon(Icons.credit_card, size: 20, color: Colors.grey),
                  SizedBox(width: 8),
                  Text('Visa ends in *4321', style: TextStyle(fontSize: 14)),
                  Spacer(),
                  Text('Expires 08/27', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {},
                child: const Text(
                  '+ Add New Payment Method',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 14),
                ),
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
                style: