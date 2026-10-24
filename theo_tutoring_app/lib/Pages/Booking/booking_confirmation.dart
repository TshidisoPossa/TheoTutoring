import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../Student/student_bottom_nav.dart';
import 'booking_flow_context.dart';
import 'booking_api.dart';
import 'booking_top_bar.dart';

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

  static const Color _primaryBlue = Color(0xFF356AE6);
  static const Color _background = Color(0xFFF7F9FE);
  static const Color _textDark = Color(0xFF17233D);
  static const Color _textMuted = Color(0xFF7B8498);
  static const Color _tileBackground = Color(0xFFF2F4FB);

  bool get _paymentConfirmed => result != null && payment?.isSuccessful == true;

  static String _initials(String? name) => (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();

  /// Returns to the student dashboard, which is the root of the student stack.
  void _goHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.poppins(fontSize: 12)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _textDark,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _navTapped(BuildContext context, int index) {
    if (index == 0) {
      _goHome(context);
      return;
    }
    _showMessage(
      context,
      '${StudentBottomNav.items[index].label} will be connected soon.',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Once a booking exists, going "back" would land on the spent payment
    // flow, so every back action returns to the dashboard instead.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goHome(context);
      },
      child: Scaffold(
        backgroundColor: _background,
        appBar: bookingTopBar(title: 'Home', flow: flow),
        body: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStatusHeader(),
                      const SizedBox(height: 28),
                      _buildSummaryCard(),
                      const SizedBox(height: 24),
                      if (_paymentConfirmed)
                        FilledButton.icon(
                          onPressed: () => _showMessage(
                            context,
                            'Receipt download will be available soon.',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: Text(
                            'Download Receipt',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      if (_paymentConfirmed) const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => _goHome(context),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFE6E9F7),
                          foregroundColor: _textDark,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Back to Home',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: StudentBottomNav(
          currentIndex: 0,
          onTap: (index) => _navTapped(context, index),
        ),
      ),
    );
  }

  Widget _buildStatusHeader() {
    final confirmed = _paymentConfirmed;
    final accent = confirmed
        ? const Color(0xFF3E9B6B)
        : const Color(0xFFC77A12);
    return Column(
      children: [
        Container(
          height: 96,
          width: 96,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            child: Icon(
              confirmed ? Icons.check_rounded : Icons.priority_high_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          confirmed ? 'Booking Request Sent!' : 'Payment Not Confirmed',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: _textDark,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          confirmed
              ? 'Your request has been sent to the tutor and the payment is '
                    'being processed.'
              : 'Payment has not been confirmed. Lessons are not confirmed.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: _textMuted,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    final result = this.result;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                color: _primaryBlue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Booking Summary',
                  style: GoogleFonts.poppins(
                    color: _textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildTutorAvatar(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      flow.tutor.name,
                      style: GoogleFonts.poppins(
                        color: _textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      flow.subject.subjectName,
                      style: GoogleFonts.poppins(
                        color: _textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (result == null)
            _tile(
              icon: Icons.info_outline_rounded,
              child: _tileText('No booking has been submitted.'),
            )
          else ...[
            for (final lesson in result.lessons) ...[
              _tile(
                icon: Icons.calendar_today_outlined,
                child: _tileText(_formatLesson(lesson)),
              ),
              const SizedBox(height: 10),
            ],
            _tile(
              icon: Icons.payments_outlined,
              child: Row(
                children: [
                  Expanded(child: _tileText('Total Due', muted: true)),
                  Text(
                    'R${result.totalAmount}',
                    style: GoogleFonts.poppins(
                      color: _textDark,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTutorAvatar() {
    final photo = flow.tutor.profilePhoto;
    final fallback = Text(
      _initials(flow.tutor.name),
      style: GoogleFonts.poppins(
        color: _primaryBlue,
        fontWeight: FontWeight.w600,
      ),
    );
    return CircleAvatar(
      radius: 26,
      backgroundColor: const Color(0xFFE6ECFC),
      child: photo == null || photo.isEmpty
          ? fallback
          : ClipOval(
              child: Image.network(
                photo,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }

  Widget _tile({required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _tileBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: _textDark, size: 18),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _tileText(String text, {bool muted = false}) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        color: muted ? _textMuted : _textDark,
        fontSize: 13,
      ),
    );
  }

  /// Formats a lesson as e.g. "Oct 24, 2026 • 2:00 PM", falling back to the
  /// raw API values if they are not in the expected date/time format.
  String _formatLesson(Map<String, dynamic> lesson) {
    final date = '${lesson['date']}';
    final start = '${lesson['startTime']}';
    final parsed = DateTime.tryParse('${date}T$start');
    if (parsed == null) return '$date • $start';
    return '${DateFormat('MMM d, y').format(parsed)} • '
        '${DateFormat('h:mm a').format(parsed)}';
  }
}
