import 'package:flutter/material.dart';
import 'booking_schedule.dart';

class BookingSelectLessonPage extends StatefulWidget {
  const BookingSelectLessonPage({super.key});

  @override
  State<BookingSelectLessonPage> createState() =>
      _BookingSelectLessonPageState();
}

class _BookingSelectLessonPageState
    extends State<BookingSelectLessonPage> {
  int numberOfLessons = 1;

  static const double pricePerLesson = 120.00;

  double get totalPrice => numberOfLessons * pricePerLesson;

  void increaseLessons() {
    if (numberOfLessons < 10) {
      setState(() {
        numberOfLessons++;
      });
    }
  }

  void decreaseLessons() {
    if (numberOfLessons > 1) {
      setState(() {
        numberOfLessons--;
      });
    }
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
          'Lessons',
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tutor card
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
                      'Book with Theo',
                      style: TextStyle(
                        color: Color(0xFF191B23),
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Row(
                      children: const [
                        Icon(
                          Icons.star,
                          color: Color(0xFFFFB800),
                          size: 20,
                        ),
                        SizedBox(width: 5),
                        Text(
                          '4.9 (120 reviews)',
                          style: TextStyle(
                            color: Color(0xFF5F6368),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Number of lessons
              const Text(
                'Number of lessons',
                style: TextStyle(
                  color: Color(0xFF191B23),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 12),

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
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Minus button
                        _buildStepButton(
                          icon: Icons.remove,
                          onPressed: decreaseLessons,
                        ),

                        const SizedBox(width: 28),

                        Text(
                          '$numberOfLessons',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF191B23),
                          ),
                        ),

                        const SizedBox(width: 28),

                        // Plus button
                        _buildStepButton(
                          icon: Icons.add,
                          onPressed: increaseLessons,
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      'Recommended 4+ lessons for mastery',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF6B6F76),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Price summary
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
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Cost per lesson',
                          style: TextStyle(
                            color: Color(0xFF5F6368),
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'R${pricePerLesson.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Color(0xFF191B23),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    const Divider(),

                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            color: Color(0xFF191B23),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'R${totalPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Color(0xFF004AC6),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Continue button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                 onPressed: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => BookingSchedulePage(
        numberOfLessons: numberOfLessons,
        totalPrice: totalPrice,
      ),
    ),
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
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Proceed to Booking',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: const Color(0xFFEAF1FF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: const Color(0xFF004AC6),
            size: 22,
          ),
        ),
      ),
    );
  }
}