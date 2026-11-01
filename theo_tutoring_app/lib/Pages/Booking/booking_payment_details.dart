import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'booking_api.dart';
import 'booking_confirmation.dart';
import 'booking_flow_context.dart';

/// "Lesson Details": the order summary for a held booking and the card form
/// that pays for it.
///
/// The card details are only checked on this device. They are never sent to
/// the backend or stored; the backend records a card payment attempt.
class BookingPaymentDetailsPage extends StatefulWidget {
  const BookingPaymentDetailsPage({
    required this.flow,
    required this.purchase,
    required this.api,
    super.key,
  });

  final BookingFlowContext flow;
  final BookingPurchaseResult purchase;
  final BookingFlowApi api;

  @override
  State<BookingPaymentDetailsPage> createState() =>
      _BookingPaymentDetailsPageState();
}

class _BookingPaymentDetailsPageState extends State<BookingPaymentDetailsPage> {
  static const Color _primaryBlue = Color(0xFF356AE6);
  static const Color _background = Color(0xFFF7F9FE);
  static const Color _textDark = Color(0xFF17233D);
  static const Color _textMuted = Color(0xFF7B8498);
  static const Color _fieldBackground = Color(0xFFF2F4FB);
  static const Color _errorRed = Color(0xFFD64545);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _numberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();

  String? _idempotencyKey;
  bool _submitting = false;
  bool _paymentFailed = false;
  bool _purchaseUnavailable = false;
  String? _error;

  BookingPurchaseResult get _purchase => widget.purchase;

  int get _lessonCount =>
      _purchase.lessons.isEmpty ? 1 : _purchase.lessons.length;

  bool get _hasDiscount => (double.tryParse(_purchase.discountAmount) ?? 0) > 0;

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  String _newIdempotencyKey() {
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'payment-$suffix';
  }

  Future<void> _pay() async {
    if (_submitting || _purchaseUnavailable) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // An uncertain request is retried with the same key so it cannot be
    // charged twice; a definite failure starts a new attempt.
    final key = _idempotencyKey ??= _newIdempotencyKey();
    setState(() {
      _submitting = true;
      _paymentFailed = false;
      _error = null;
    });
    try {
      final receipt = await widget.api.createPaymentAttempt(
        purchaseId: _purchase.purchaseId,
        idempotencyKey: key,
        paymentMethod: 'CreditDebitCard',
        simulatedOutcome: 'success',
      );
      if (!mounted) return;
      if (receipt.isSuccessful) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => BookingConfirmationPage(
              flow: widget.flow,
              result: _purchase,
              payment: receipt,
            ),
          ),
        );
        return;
      }
      setState(() {
        _submitting = false;
        _paymentFailed = true;
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
            'Payment result could not be confirmed. Tap Pay again to retry '
            'while your lesson is still reserved.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: _textDark),
        ),
        titleSpacing: 0,
        title: Text(
          'Lesson Details',
          style: GoogleFonts.poppins(
            color: _textDark,
            fontSize: 19,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // The Pay button sits in the body, not the bottom bar, so it stays
      // above the keyboard while the card details are being typed.
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _buildForm()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              _buildOrderSummary(),
              const SizedBox(height: 20),
              _buildPaymentMethod(),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: _textMuted,
                    size: 13,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'PAYMENTS SECURELY PROCESSED',
                    style: GoogleFonts.poppins(
                      color: _textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Payment errors sit right above the Pay button so they are seen
  // without scrolling.
  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_paymentFailed)
                _buildMessage(
                  'Payment failed. No booking was confirmed. You can try '
                  'again while your lesson is still reserved.',
                ),
              if (_error != null) _buildMessage(_error!),
              if (_purchaseUnavailable)
                _buildMessage(
                  'This reservation can no longer be paid. Go back and '
                  'choose your lesson time again.',
                ),
              const SizedBox(height: 8),
              _buildPayButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPayButton() {
    return FilledButton.icon(
      onPressed: _submitting || _purchaseUnavailable ? null : _pay,
      style: FilledButton.styleFrom(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: _submitting
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.lock_outline_rounded, size: 18),
      label: Text(
        _submitting ? 'Processing…' : 'Pay R${_purchase.totalAmount} Now',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF23365D).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildOrderSummary() {
    final sessionLabel = _lessonCount == 1
        ? 'Session (1 hour)'
        : 'Sessions ($_lessonCount × 1 hour)';
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6ECFC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.event_note_rounded,
                  color: _primaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Order Summary',
                style: GoogleFonts.poppins(
                  color: _textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _summaryRow(sessionLabel, 'R${_purchase.subtotal}'),
          if (_hasDiscount) ...[
            const SizedBox(height: 10),
            _summaryRow(
              'Package discount (${_purchase.discountPercent}%)',
              '−R${_purchase.discountAmount}',
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: Color(0xFFE6E9F2)),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total Due',
                  style: GoogleFonts.poppins(
                    color: _textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                'R${_purchase.totalAmount}',
                style: GoogleFonts.poppins(
                  color: _primaryBlue,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(color: _textMuted, fontSize: 13),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: _textDark,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethod() {
    return _card(
      child: AbsorbPointer(
        absorbing: _submitting,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Payment Method',
                    style: GoogleFonts.poppins(
                      color: _textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _cardBrandBadge('VISA'),
                const SizedBox(width: 6),
                _cardBrandBadge('MC'),
              ],
            ),
            const SizedBox(height: 18),
            _fieldLabel('Name on Card'),
            _field(
              controller: _nameController,
              hint: 'Jane Doe',
              icon: Icons.person_outline_rounded,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.creditCardName],
              validator: (value) => (value ?? '').trim().length < 2
                  ? 'Enter the name on the card.'
                  : null,
            ),
            const SizedBox(height: 14),
            _fieldLabel('Card Number'),
            _field(
              controller: _numberController,
              hint: '0000 0000 0000 0000',
              icon: Icons.credit_card_rounded,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.creditCardNumber],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(19),
                _CardNumberFormatter(),
              ],
              validator: _validateCardNumber,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _fieldLabel('Expiry Date'),
                      _field(
                        controller: _expiryController,
                        hint: 'MM/YY',
                        icon: Icons.calendar_today_outlined,
                        keyboardType: TextInputType.number,
                        autofillHints: const [
                          AutofillHints.creditCardExpirationDate,
                        ],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                          _ExpiryDateFormatter(),
                        ],
                        validator: _validateExpiry,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _fieldLabel('CVV'),
                      _field(
                        controller: _cvvController,
                        hint: '123',
                        icon: Icons.lock_outline_rounded,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        autofillHints: const [
                          AutofillHints.creditCardSecurityCode,
                        ],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        validator: (value) =>
                            RegExp(r'^\d{3,4}$').hasMatch(value ?? '')
                            ? null
                            : 'Enter 3 or 4 digits.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardBrandBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _fieldBackground,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: _textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          color: _textDark,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    Iterable<String>? autofillHints,
    bool obscureText = false,
  }) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color),
    );
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      obscureText: obscureText,
      validator: validator,
      style: GoogleFonts.poppins(color: _textDark, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
          color: const Color(0xFFB4BACB),
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: _textMuted, size: 18),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        filled: true,
        fillColor: _fieldBackground,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        errorStyle: GoogleFonts.poppins(fontSize: 11),
        border: border(const Color(0xFFE6E9F2)),
        enabledBorder: border(const Color(0xFFE6E9F2)),
        focusedBorder: border(_primaryBlue),
        errorBorder: border(_errorRed),
        focusedErrorBorder: border(_errorRed),
      ),
    );
  }

  Widget _buildMessage(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(color: _errorRed, fontSize: 12.5),
      ),
    );
  }

  /// Accepts 13–19 digit numbers that pass the Luhn checksum.
  String? _validateCardNumber(String? value) {
    final digits = (value ?? '').replaceAll(' ', '');
    if (digits.length < 13 || digits.length > 19) {
      return 'Enter a valid card number.';
    }
    var sum = 0;
    for (var i = 0; i < digits.length; i++) {
      var digit = int.parse(digits[digits.length - 1 - i]);
      if (i.isOdd) {
        digit *= 2;
        if (digit > 9) digit -= 9;
      }
      sum += digit;
    }
    return sum % 10 == 0 ? null : 'Enter a valid card number.';
  }

  String? _validateExpiry(String? value) {
    final match = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(value ?? '');
    if (match == null) return 'Use MM/YY.';
    final month = int.parse(match.group(1)!);
    final year = 2000 + int.parse(match.group(2)!);
    if (month < 1 || month > 12) return 'Use MM/YY.';
    final now = DateTime.now();
    if (year < now.year || (year == now.year && month < now.month)) {
      return 'This card has expired.';
    }
    return null;
  }
}

/// Groups card number digits in fours: "4242424242424242" → "4242 4242 …".
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Inserts the slash in an expiry date: "1228" → "12/28".
class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll('/', '');
    final text = digits.length > 2
        ? '${digits.substring(0, 2)}/${digits.substring(2)}'
        : digits;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
