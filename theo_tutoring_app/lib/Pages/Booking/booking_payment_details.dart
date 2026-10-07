import 'package:flutter/material.dart';
import 'booking_confirmation.dart';

class BookingPaymentDetailsPage extends StatefulWidget {
  final int numberOfLessons;
  final double totalPrice;
  final DateTime selectedDate;
  final String selectedTime;
  final String note;

  const BookingPaymentDetailsPage({
    super.key,
    required this.numberOfLessons,
    required this.totalPrice,
    required this.selectedDate,
    required this.selectedTime,
    required this.note,
  });

  @override
  State<BookingPaymentDetailsPage> createState() =>
      _BookingPaymentDetailsPageState();
}


class _BookingPaymentDetailsPageState
    extends State<BookingPaymentDetailsPage> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController cardNumberController =
      TextEditingController();
  final TextEditingController expiryController = TextEditingController();
  final TextEditingController cvvController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    cardNumberController.dispose();
    expiryController.dispose();
    cvvController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),

      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF8FF),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Color(0xFF191B23),
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Lesson Details',
          style: TextStyle(
            color: Color(0xFF191B23),
            fontSize: 22,
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
              // Order Summary
              const Text(
                'Order Summary',
                style: TextStyle(
                  color: Color(0xFF191B23),
                  fontSize: 20,
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
                    _summaryRow(
                      'Session',
                      '${widget.numberOfLessons} ${widget.numberOfLessons == 1 ? 'Lesson' : 'Lessons'}',
                    ),

                    const SizedBox(height: 14),

                    _summaryRow(
                      'Session Price',
                      'R${widget.totalPrice.toStringAsFixed(2)}',
                    ),

                    const SizedBox(height: 14),

                    _summaryRow(
                      'Processing Fee',
                      'R0.00',
                    ),

                    const SizedBox(height: 16),

                    const Divider(),

                    const SizedBox(height: 16),

                    _summaryRow(
                      'Total Due',
                      'R${widget.totalPrice.toStringAsFixed(2)}',
                      isTotal: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Payment method
              const Text(
                'Payment Method',
                style: TextStyle(
                  color: Color(0xFF191B23),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 12),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFE0E2E7),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.credit_card,
                        color: Color(0xFF004AC6),
                      ),
                    ),

                    const SizedBox(width: 14),

                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Credit / Debit Card',
                            style: TextStyle(
                              color: Color(0xFF191B23),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'VISA / Mastercard',
                            style: TextStyle(
                              color: Color(0xFF6B6F76),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Change',
                        style: TextStyle(
                          color: Color(0xFF004AC6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Card details
              const Text(
                'Card Details',
                style: TextStyle(
                  color: Color(0xFF191B23),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 16),

              // Name
              _buildTextField(
                controller: nameController,
                label: 'Name on Card',
                hint: 'Jane Doe',
                keyboardType: TextInputType.name,
              ),

              const SizedBox(height: 16),

              // Card number
              _buildTextField(
                controller: cardNumberController,
                label: 'Card Number',
                hint: '0000 0000 0000 0000',
                keyboardType: TextInputType.number,
                prefixIcon: Icons.credit_card,
              ),

              const SizedBox(height: 16),

              // Expiry + CVV
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: expiryController,
                      label: 'Expiry Date',
                      hint: 'MM/YY',
                      keyboardType: TextInputType.datetime,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: _buildTextField(
                      controller: cvvController,
                      label: 'CVV',
                      hint: '123',
                      keyboardType: TextInputType.number,
                      obscureText: true,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Security message
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF8F1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      color: Color(0xFF287A3D),
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'PAYMENTS SECURELY PROCESSED',
                        style: TextStyle(
                          color: Color(0xFF287A3D),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Pay button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => BookingConfirmationPage(
        numberOfLessons: widget.numberOfLessons,
        totalPrice: widget.totalPrice,
        selectedDate: widget.selectedDate,
        selectedTime: widget.selectedTime,
        note: widget.note,
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
                  child: Text(
  'Pay R${widget.totalPrice.toStringAsFixed(2)} Now',
  style: const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
  ),
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

  Widget _summaryRow(
    String title,
    String value, {
    bool isTotal = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: isTotal
                ? const Color(0xFF191B23)
                : const Color(0xFF6B6F76),
            fontSize: isTotal ? 17 : 14,
            fontWeight:
                isTotal ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isTotal
                ? const Color(0xFF004AC6)
                : const Color(0xFF191B23),
            fontSize: isTotal ? 20 : 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    IconData? prefixIcon,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null
            ? Icon(
                prefixIcon,
                color: const Color(0xFF6B6F76),
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(
          color: Color(0xFF5F6368),
        ),
        hintStyle: const TextStyle(
          color: Color(0xFF9A9DA5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFD9DCE3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFFD9DCE3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF004AC6),
            width: 2,
          ),
        ),
      ),
    );
  }
}