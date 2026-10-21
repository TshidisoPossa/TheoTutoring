import 'package:flutter/material.dart';

import 'booking_api.dart';
import 'booking_flow_context.dart';
import 'booking_payment_details.dart';

class BookingPaymentMethodPage extends StatefulWidget {
  const BookingPaymentMethodPage({
    required this.flow,
    required this.purchase,
    required this.api,
    super.key,
  });

  final BookingFlowContext flow;
  final BookingPurchaseResult purchase;
  final BookingFlowApi api;

  @override
  State<BookingPaymentMethodPage> createState() =>
      _BookingPaymentMethodPageState();
}

class _BookingPaymentMethodPageState extends State<BookingPaymentMethodPage> {
  String _method = 'CreditDebitCard';

  static const _methods = [
    ('CreditDebitCard', 'Credit / debit card', Icons.credit_card),
    ('PayPal', 'PayPal', Icons.account_balance_wallet),
    ('EFT', 'EFT', Icons.account_balance),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF8FF),
        elevation: 0,
        title: const Text('Payment method'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${widget.flow.tutor.name} · ${widget.flow.subject.subjectName}',
            ),
            const SizedBox(height: 16),
            Card(
              color: Colors.amber.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'DEMO PAYMENT ONLY\n'
                  'No real payment will be taken. Do not enter card details, '
                  'bank details, or payment credentials.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Amount: R${widget.purchase.totalAmount}'),
            Text('Reservation expires: ${widget.purchase.holdExpiresAt}'),
            const SizedBox(height: 12),
            RadioGroup<String>(
              groupValue: _method,
              onChanged: (value) {
                if (value != null) setState(() => _method = value);
              },
              child: Column(
                children: [
                  for (final (value, label, icon) in _methods)
                    Card(
                      color: Colors.white,
                      child: RadioListTile<String>(
                        value: value,
                        secondary: Icon(icon),
                        title: Text(label),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BookingPaymentDetailsPage(
                    flow: widget.flow,
                    purchase: widget.purchase,
                    api: widget.api,
                    paymentMethod: _method,
                  ),
                ),
              ),
              child: const Text('Continue to demo payment'),
            ),
          ],
        ),
      ),
    );
  }
}
