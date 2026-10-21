import 'package:flutter/material.dart';

import 'booking_flow_context.dart';
import 'booking_api.dart';

class BookingConfirmationPage extends StatelessWidget {
  const BookingConfirmationPage({
    required this.flow,
    this.result,
    this.payment,
    super.key,
  });

  final BookingFlowContext flow;
  final BookingPurchaseResult? result;
  final PaymentAttemptResult? payment;

  bool get _paymentConfirmed =>
      result != null && payment?.isSuccessful == true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF8FF),
        elevation: 0,
        title: const Text('Booking status'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${flow.tutor.name} · ${flow.subject.subjectName}'),
              const SizedBox(height: 16),
              if (!_paymentConfirmed) ...[
                if (result == null)
                  const Text('No booking has been submitted.')
                else
                  Text('Request #${result!.purchaseId} · ${result!.purchaseStatus}'),
                const SizedBox(height: 12),
                const Text(
                  'Payment has not been confirmed. Lessons are not confirmed.',
                ),
              ] else ...[
                Text('Booking #${result!.purchaseId} · Paid'),
                const SizedBox(height: 8),
                Text('Total: R${result!.totalAmount}'),
                const SizedBox(height: 12),
                Text('Payment confirmed · attempt #${payment!.paymentAttemptId}'),
                const SizedBox(height: 8),
                const Text('Your lessons are confirmed.'),
                const SizedBox(height: 8),
                for (final lesson in result!.lessons)
                  Text(
                    '${lesson['date']} · ${lesson['startTime']}–'
                    '${lesson['endTime']}',
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
