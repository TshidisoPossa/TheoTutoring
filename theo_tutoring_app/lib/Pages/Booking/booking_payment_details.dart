import 'dart:math';

import 'package:flutter/material.dart';

import 'booking_api.dart';
import 'booking_confirmation.dart';
import 'booking_flow_context.dart';

class BookingPaymentDetailsPage extends StatefulWidget {
  const BookingPaymentDetailsPage({
    required this.flow,
    required this.purchase,
    required this.api,
    required this.paymentMethod,
    super.key,
  });

  final BookingFlowContext flow;
  final BookingPurchaseResult purchase;
  final BookingFlowApi api;
  final String paymentMethod;

  @override
  State<BookingPaymentDetailsPage> createState() =>
      _BookingPaymentDetailsPageState();
}

class _BookingPaymentDetailsPageState extends State<BookingPaymentDetailsPage> {
  String? _outcome;
  String? _idempotencyKey;
  PaymentAttemptResult? _receipt;
  bool _submitting = false;
  bool _purchaseUnavailable = false;
  String? _error;

  String _newIdempotencyKey() {
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'demo-payment-$suffix';
  }

  void _selectOutcome(String value) {
    setState(() {
      _outcome = value;
      _idempotencyKey = null;
      _receipt = null;
      _purchaseUnavailable = false;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final outcome = _outcome;
    if (outcome == null || _submitting || _purchaseUnavailable) return;

    final key = _idempotencyKey ??= _newIdempotencyKey();
    setState(() {
      _submitting = true;
      _error = null;
      _receipt = null;
    });
    try {
      final receipt = await widget.api.createPaymentAttempt(
        purchaseId: widget.purchase.purchaseId,
        idempotencyKey: key,
        paymentMethod: widget.paymentMethod,
        simulatedOutcome: outcome,
      );
      if (!mounted) return;
      if (receipt.isSuccessful) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => BookingConfirmationPage(
              flow: widget.flow,
              result: widget.purchase,
              payment: receipt,
            ),
          ),
        );
        return;
      }
      setState(() {
        _submitting = false;
        _receipt = receipt;
        _idempotencyKey = null;
      });
    } on BookingApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message;
        _purchaseUnavailable = const {
          'hold_expired',
          'incomplete_hold_set',
          'purchase_not_payable',
          'purchase_already_settled',
        }.contains(error.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error =
            'Payment result could not be confirmed. Retry the same demo '
            'request while the reservation is active.';
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
        title: const Text('Demo payment'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${widget.flow.tutor.name} · ${widget.flow.subject.subjectName}',
            ),
            const SizedBox(height: 12),
            Text('Payment method: ${_methodLabel(widget.paymentMethod)}'),
            Text('Amount: R${widget.purchase.totalAmount}'),
            Text('Reservation expires: ${widget.purchase.holdExpiresAt}'),
            const SizedBox(height: 16),
            Card(
              color: Colors.amber.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'DEMO PAYMENT ONLY\n'
                  'No real payment will be taken. Never enter card numbers, '
                  'bank details, or payment credentials.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Choose a simulated outcome:'),
            AbsorbPointer(
              absorbing: _submitting,
              child: RadioGroup<String>(
                groupValue: _outcome,
                onChanged: (value) {
                  if (!_submitting && value != null) _selectOutcome(value);
                },
                child: const Column(
                  children: [
                    RadioListTile<String>(
                      value: 'success',
                      title: Text('Simulate successful payment'),
                    ),
                    RadioListTile<String>(
                      value: 'failure',
                      title: Text('Simulate failed payment'),
                    ),
                  ],
                ),
              ),
            ),
            if (_receipt?.paymentStatus == 'Failed')
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Demo payment failed. No booking was confirmed. '
                  'You may retry while the reservation is active.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_purchaseUnavailable)
              const Text('This reservation can no longer be paid.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _outcome == null || _submitting || _purchaseUnavailable
                  ? null
                  : _submit,
              child: _submitting
                  ? const CircularProgressIndicator()
                  : Text(
                      _receipt?.paymentStatus == 'Failed'
                          ? 'Retry demo payment'
                          : _error == null
                          ? 'Submit demo payment'
                          : 'Retry payment request',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _methodLabel(String method) => switch (method) {
    'CreditDebitCard' => 'Credit / debit card',
    'PayPal' => 'PayPal',
    'EFT' => 'EFT',
    _ => method,
  };
}
