import 'package:flutter/material.dart';

class BookingConfirmationPage extends StatelessWidget {
  final int numberOfLessons;
  final double totalPrice;
  final DateTime selectedDate;
  final String selectedTime;
  final String note;

  const BookingConfirmationPage({
    super.key,
    required this.numberOfLessons,
    required this.totalPrice,
    required this.selectedDate,
    required this.selectedTime,
    required this.note,
  });

  String _monthName(int month) {
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[month];
  }
  String _getEndTime(String startTime) {
    const timeMap = {
      '09:00 AM': '10:00 AM',
      '10:30 AM': '11:30 AM',
      '11:00 AM': '12:00 PM',
      '01:00 PM': '02:00 PM',
      '02:30 PM': '03:30 PM',
      '04:00 PM': '05:00 PM',
    };

    return timeMap[startTime] ?? '02:00 PM';
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),

      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF8FF),
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Theo',
          style: TextStyle(
            color: Color(0xFF191B23),
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const SizedBox(height: 20),

              // Success icon
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F7EC),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF287A3D),
                  size: 48,
                ),
              ),

              const SizedBox(height: 24),

              // Confirmation message
              const Text(
                'Session Booked!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF191B23),
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Your tutoring session is confirmed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B6F76),
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 32),

              // Booking details card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Booking Details',
                      style: TextStyle(
                        color: Color(0xFF191B23),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 20),

                    _detailRow(
                      icon: Icons.school_outlined,
                      title: 'Subject',
                      value: 'Advanced Calculus',
                    ),

                    const SizedBox(height: 18),

                    _detailRow(
                      icon: Icons.person_outline,
                      title: 'Tutor',
                      value: 'Theophilus Nkhabu',
                    ),

                    const SizedBox(height: 18),

                    _detailRow(
                      icon: Icons.calendar_today_outlined,
                      title: 'Date',
                      value: '${selectedDate.day} ${_monthName(selectedDate.month)} ${selectedDate.year}',
                    ),

                    const SizedBox(height: 18),

                    _detailRow(
                      icon: Icons.access_time,
                      title: 'Time',
                      value: '$selectedTime - ${_getEndTime(selectedTime)}',
                    ),

                    const SizedBox(height: 18),

                    _detailRow(
                      icon: Icons.location_on_outlined,
                      title: 'Location',
                      value: 'Google Meet',
                    ),

                    const SizedBox(height: 16),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.video_call_outlined,
                            color: Color(0xFF004AC6),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'meet.google.com/abc-xyz-123',
                              style: TextStyle(
                                color: Color(0xFF004AC6),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Receipt button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // PDF receipt functionality will be added later.
                  },
                  icon: const Icon(
                    Icons.download_outlined,
                  ),
                  label: const Text(
                    'Download PDF Receipt',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF004AC6),
                    side: const BorderSide(
                      color: Color(0xFF004AC6),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Calendar button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Calendar integration will be added later.
                  },
                  icon: const Icon(
                    Icons.calendar_month_outlined,
                  ),
                  label: const Text(
                    'Add to Calendar',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF191B23),
                    side: const BorderSide(
                      color: Color(0xFFD9DCE3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Dashboard button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.popUntil(
                      context,
                      (route) => route.isFirst,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004AC6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Go to Dashboard',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _detailRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF1FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF004AC6),
            size: 21,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF6B6F76),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF191B23),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}