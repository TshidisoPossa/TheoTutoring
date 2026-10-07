import 'package:flutter/material.dart';
import 'booking_payment_details.dart';

class BookingPaymentMethodPage extends StatefulWidget {
  final int numberOfLessons;
  final double totalPrice;
  final DateTime selectedDate;
  final String selectedTime;
  final String note;

  const BookingPaymentMethodPage({
    super.key,
    required this.numberOfLessons,
    required this.totalPrice,
    required this.selectedDate,
    required this.selectedTime,
    required this.note,
  });

  @override
  State<BookingPaymentMethodPage> createState() =>
      _BookingPaymentMethodPageState();
}

class _BookingPaymentMethodPageState
    extends State<BookingPaymentMethodPage> {
  String selectedPaymentMethod = 'Credit / Debit Card';

  final List<Map<String, dynamic>> paymentMethods = [
    {
      'title': 'Credit / Debit Card',
      'subtitle': 'Visa, Mastercard',
      'icon': Icons.credit_card,
    },
    {
      'title': 'Instant EFT',
      'subtitle': 'Absa, Capitec, FNB, Nedbank, Standard Bank',
      'icon': Icons.account_balance,
    },
    {
      'title': 'SnapScan / Zapper',
      'subtitle': 'Scan to pay instantly',
      'icon': Icons.qr_code_2,
    },
    {
      'title': 'PayPal',
      'subtitle': 'Fast, safe online payments',
      'icon': Icons.account_balance_wallet,
    },
  ];

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
          'Home',
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
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF1FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.school_outlined,
                            color: Color(0xFF004AC6),
                          ),
                        ),

                        const SizedBox(width: 12),

                        const Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Advanced Calculus Tutor',
                                style: TextStyle(
                                  color: Color(0xFF191B23),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Theophilus Nkhabu',
                                style: TextStyle(
                                  color: Color(0xFF6B6F76),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    const Divider(),

                    const SizedBox(height: 16),

                    const Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Session',
                          style: TextStyle(
                            color: Color(0xFF6B6F76),
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '1 hour',
                          style: TextStyle(
                            color: Color(0xFF191B23),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                     Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Amount',
                          style: TextStyle(
                            color: Color(0xFF191B23),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                              'R${widget.totalPrice.toStringAsFixed(2)}',
                          style: TextStyle(
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

              const SizedBox(height: 28),

              const Text(
                'Payment Method',
                style: TextStyle(
                  color: Color(0xFF191B23),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 12),

              // Payment options
              ...paymentMethods.map((method) {
                final bool isSelected =
                    selectedPaymentMethod == method['title'];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedPaymentMethod = method['title'];
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF004AC6)
                              : const Color(0xFFE0E2E7),
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFEAF1FF)
                                  : const Color(0xFFF4F4F6),
                              borderRadius:
                                  BorderRadius.circular(12),
                            ),
                            child: Icon(
                              method['icon'],
                              color: isSelected
                                  ? const Color(0xFF004AC6)
                                  : const Color(0xFF5F6368),
                            ),
                          ),

                          const SizedBox(width: 14),

                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  method['title'],
                                  style: const TextStyle(
                                    color: Color(0xFF191B23),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  method['subtitle'],
                                  style: const TextStyle(
                                    color: Color(0xFF6B6F76),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Radio<String>(
                            value: method['title'],
                            groupValue: selectedPaymentMethod,
                            activeColor: const Color(0xFF004AC6),
                            onChanged: (value) {
                              setState(() {
                                selectedPaymentMethod = value!;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const SizedBox(height: 16),

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
                        'Your transaction is secure and encrypted.',
                        style: TextStyle(
                          color: Color(0xFF287A3D),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Proceed button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => BookingPaymentDetailsPage(
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
                  child: const Text(
                    'Proceed to Pay R120.00',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Back button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF191B23),
                    side: const BorderSide(
                      color: Color(0xFFD9DCE3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Back',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
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
}