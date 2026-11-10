import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../Student/student_bottom_nav.dart';
import '../Tutor/tutor_theme.dart';
import 'booking_api.dart';
import 'booking_flow_context.dart';
import 'booking_payment_details.dart';
import 'booking_top_bar.dart';

/// "Schedule Session": the student picks a date on a calendar that marks the
/// tutor's available days, then a time, and sends the booking request.
///
/// Available days and times come from GET /StudentlandingPage/availability,
/// which builds them from the tutor's weekly availability minus lessons that
/// are already booked or held.
class BookingSchedulePage extends StatefulWidget {
  const BookingSchedulePage({
    required this.flow,
    this.purchaseType = 'Single',
    this.lessonCount = 1,
    this.api,
    super.key,
  });
  final BookingFlowContext flow;
  final String purchaseType;
  final int lessonCount;
  final BookingFlowApi? api;

  @override
  State<BookingSchedulePage> createState() => _BookingSchedulePageState();
}

class _BookingSchedulePageState extends State<BookingSchedulePage> {
  static const Color _primaryBlue = Color(0xFF356AE6); // fills: buttons, days
  static const Color _errorRed = Color(0xFFD64545);

  // Light colours, or the dark ones while dark mode is on
  bool get _dk => context.tutorDark;
  Color get _background => _dk ? TutorDark.background : const Color(0xFFF7F9FE);
  Color get _surface => _dk ? TutorDark.card : Colors.white;
  Color get _textDark => _dk ? TutorDark.text : const Color(0xFF17233D);
  Color get _textMuted => _dk ? TutorDark.textMuted : const Color(0xFF7B8498);
  Color get _textFaint => _dk ? TutorDark.border : const Color(0xFFC3C8D4);
  Color get _hint => _dk ? TutorDark.textFaint : const Color(0xFFB4BACB);
  Color get _border => _dk ? TutorDark.border : const Color(0xFFE6E9F2);
  Color get _inputBorder => _dk ? TutorDark.border : const Color(0xFFD9DDE8);
  Color get _headerBackground =>
      _dk ? TutorDark.cardAlt : const Color(0xFFEEF1FB);
  Color get _blueTint => _dk ? TutorDark.blueTint : const Color(0xFFE0E7FB);
  Color get _accent => _dk ? TutorDark.blueText : _primaryBlue; // blue text

  late final DateTime _today = DateUtils.dateOnly(DateTime.now());
  late final DateTime _lastDate = _today.add(const Duration(days: 90));
  late DateTime _month = DateTime(_today.year, _today.month);
  DateTime? _date;

  late final BookingFlowApi _api = widget.api ?? HttpBookingFlowApi();
  late final bool _ownsApi = widget.api == null;
  final _noteController = TextEditingController();

  Map<String, List<AvailableBookingSlot>> _slotsByDate = const {};
  String? _hourlyRate;
  final Set<String> _selected = {};
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _submitError;
  String? _idempotencyKey;
  BookingPurchaseResult? _result;

  bool get _isPackage => widget.lessonCount > 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_ownsApi) _api.close();
    _noteController.dispose();
    super.dispose();
  }

  String _dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  String _slotKey(AvailableBookingSlot slot) =>
      '${slot.date}|${slot.startTime}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final availability = await _api.availability(
        tutorId: widget.flow.selection.tutorId,
        subjectId: widget.flow.selection.subjectId,
        from: _dateKey(_today),
        through: _dateKey(_lastDate),
      );
      if (!mounted) return;
      final byDate = <String, List<AvailableBookingSlot>>{};
      for (final slot in availability.slots) {
        (byDate[slot.date] ??= []).add(slot);
      }
      for (final slots in byDate.values) {
        slots.sort((a, b) => a.startTime.compareTo(b.startTime));
      }
      // Open on the first day the tutor is free.
      final firstDate = (byDate.keys.toList()..sort()).firstOrNull;
      final first = firstDate == null ? null : DateTime.tryParse(firstDate);
      setState(() {
        _slotsByDate = byDate;
        _hourlyRate = availability.hourlyRate;
        _date = first;
        if (first != null) _month = DateTime(first.year, first.month);
        _loading = false;
      });
    } on BookingApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Available times could not be loaded.';
          _loading = false;
        });
      }
    }
  }

  void _toggle(AvailableBookingSlot slot) {
    // Once the request is sent the times are held for this student, so the
    // choice is locked until they pay or the hold runs out.
    if (_result != null || _submitting) return;
    final key = _slotKey(slot);
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else if (!_isPackage) {
        _selected
          ..clear()
          ..add(key);
      } else if (_selected.length < widget.lessonCount) {
        _selected.add(key);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Choose up to ${widget.lessonCount} lessons.'),
          ),
        );
        return;
      }
      _idempotencyKey = null;
      _submitError = null;
    });
  }

  Future<void> _submit() async {
    if (_selected.length != widget.lessonCount || _submitting) return;
    final slots = [
      for (final daySlots in _slotsByDate.values)
        for (final slot in daySlots)
          if (_selected.contains(_slotKey(slot))) slot,
    ]..sort((a, b) => _slotKey(a).compareTo(_slotKey(b)));
    if (slots.length != widget.lessonCount) {
      setState(() => _submitError = 'Choose available times for every lesson.');
      return;
    }
    _idempotencyKey ??= 'booking-${DateTime.now().microsecondsSinceEpoch}';
    final note = _noteController.text.trim();
    final request = <String, Object>{
      'tutorId': widget.flow.selection.tutorId,
      'subjectId': widget.flow.selection.subjectId,
      'purchaseType': widget.purchaseType,
      'schedulingMode': 'manual',
      'idempotencyKey': _idempotencyKey!,
      'lessons': [
        for (final s in slots)
          {'date': s.date, 'startTime': s.startTime, 'endTime': s.endTime},
      ],
      if (note.isNotEmpty) 'note': note,
    };
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final result = await _api.createPurchase(request);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _result = result;
      });
      await _openPayment(result);
    } on BookingApiException catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError =
              'Booking could not be confirmed. Retry using the same request.';
        });
      }
    }
  }

  Future<void> _openPayment(BookingPurchaseResult purchase) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookingPaymentDetailsPage(
          flow: widget.flow,
          purchase: purchase,
          api: _api,
        ),
      ),
    );
  }

  void _navTapped(int index) {
    if (index == 0) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    if (index == 1) return; // already on Lessons
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${StudentBottomNav.items[index].label} will be connected soon.',
            style: GoogleFonts.poppins(fontSize: 12),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _textDark,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: bookingTopBar(title: 'Lessons', flow: widget.flow),
      // The footer sits in the body, not the bottom bar, so it stays above
      // the keyboard while the note is being typed.
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTutorHeader(),
                        const SizedBox(height: 22),
                        _buildCalendarCard(),
                        if (!_loading && _error == null) ...[
                          const SizedBox(height: 26),
                          _buildTimes(),
                          const SizedBox(height: 26),
                          _buildNote(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
      bottomNavigationBar: StudentBottomNav(currentIndex: 1, onTap: _navTapped),
    );
  }

  // ── TUTOR HEADER ────────────────────────────────────────

  Widget _buildTutorHeader() {
    final tutor = widget.flow.tutor;
    final initials = tutor.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final fallback = Text(
      initials,
      style: GoogleFonts.poppins(
        color: _accent,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );
    final photo = tutor.profilePhoto;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 22),
      decoration: BoxDecoration(
        color: _headerBackground,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: _blueTint,
            child: photo == null || photo.isEmpty
                ? fallback
                : ClipOval(
                    child: Image.network(
                      photo,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Center(child: fallback),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              children: [
                Text(
                  tutor.name,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: _textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Schedule Session',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: _textDark, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  _isPackage
                      ? 'Choose ${widget.lessonCount} lessons'
                      : 'Book your next lesson',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: _textMuted, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── CALENDAR ────────────────────────────────────────────

  Widget _buildCalendarCard() {
    Widget child;
    if (_loading) {
      child = const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      child = Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Column(
          children: [
            Text(
              _error!,
              key: const ValueKey('availability-error'),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: _textDark, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    } else {
      child = _buildCalendar();
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF23365D).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildCalendar() {
    final firstMonth = DateTime(_today.year, _today.month);
    final lastMonth = DateTime(_lastDate.year, _lastDate.month);
    final canGoBack = _month.isAfter(firstMonth);
    final canGoForward = _month.isBefore(lastMonth);
    final leadingBlanks = DateTime(_month.year, _month.month).weekday % 7;
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _buildDay(DateTime(_month.year, _month.month, day)),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: canGoBack
                  ? () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1),
                    )
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
              color: _textDark,
              disabledColor: _textFaint,
            ),
            Expanded(
              child: Text(
                DateFormat('MMMM y').format(_month),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: _textDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: canGoForward
                  ? () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    )
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
              color: _textDark,
              disabledColor: _textFaint,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final label in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: _textDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < cells.length ~/ 7; row++)
          Row(
            children: [
              for (final cell in cells.sublist(row * 7, row * 7 + 7))
                Expanded(child: SizedBox(height: 50, child: cell)),
            ],
          ),
        if (_slotsByDate.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'No available times in the next 90 days.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: _textMuted, fontSize: 13),
            ),
          ),
      ],
    );
  }

  /// Available days are blue with a dot; the chosen day is a filled circle;
  /// days with no free time (or in the past) are faint and cannot be tapped.
  Widget _buildDay(DateTime day) {
    final key = _dateKey(day);
    final available = _slotsByDate.containsKey(key);
    final isSelectedDay = _date != null && DateUtils.isSameDay(day, _date);
    final hasChosenTime = _selected.any((slot) => slot.startsWith('$key|'));

    final Color? circle = isSelectedDay
        ? _primaryBlue
        : hasChosenTime
        ? _blueTint
        : null;
    final Color textColor = isSelectedDay
        ? Colors.white
        : available
        ? _accent
        : _textFaint;

    return Semantics(
      button: available,
      selected: isSelectedDay,
      label:
          DateFormat('EEEE d MMMM').format(day) +
          (available ? ', available' : ', unavailable'),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('day-$key'),
        customBorder: const CircleBorder(),
        onTap: available ? () => setState(() => _date = day) : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 38,
              width: 38,
              alignment: Alignment.center,
              decoration: circle == null
                  ? null
                  : BoxDecoration(color: circle, shape: BoxShape.circle),
              child: Text(
                '${day.day}',
                style: GoogleFonts.poppins(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: available ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              height: 5,
              width: 5,
              decoration: BoxDecoration(
                color: available && !isSelectedDay
                    ? _primaryBlue
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── TIMES ───────────────────────────────────────────────

  Widget _buildTimes() {
    final date = _date;
    final slots = date == null
        ? const <AvailableBookingSlot>[]
        : _slotsByDate[_dateKey(date)] ?? const <AvailableBookingSlot>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.access_time_rounded, size: 16, color: _textDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                date == null
                    ? 'Available Times'
                    : 'Available Times on ${DateFormat('MMM d').format(date)}',
                style: GoogleFonts.poppins(
                  color: _textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (slots.isEmpty)
          Text(
            'Choose a highlighted date to see the tutor\'s free times.',
            style: GoogleFonts.poppins(color: _textMuted, fontSize: 13),
          )
        else
          for (var row = 0; row < (slots.length + 2) ~/ 3; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  for (var col = 0; col < 3; col++) ...[
                    if (col > 0) const SizedBox(width: 10),
                    Expanded(
                      child: row * 3 + col < slots.length
                          ? _buildTimeChip(slots[row * 3 + col])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
        if (_isPackage)
          Text(
            '${_selected.length} of ${widget.lessonCount} lessons selected',
            style: GoogleFonts.poppins(
              color: _textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  Widget _buildTimeChip(AvailableBookingSlot slot) {
    final selected = _selected.contains(_slotKey(slot));
    return Material(
      color: selected ? _primaryBlue : _surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggle(slot),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? _primaryBlue : _border),
          ),
          child: Text(
            _formatTime(slot.startTime),
            style: GoogleFonts.poppins(
              color: selected ? Colors.white : _textDark,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  /// "13:00" → "01:00 PM"; falls back to the raw value if it is unexpected.
  String _formatTime(String time) {
    final parts = time.split(':');
    final hour = int.tryParse(parts.first);
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (hour == null || minute == null) return time;
    return DateFormat('hh:mm a').format(DateTime(2000, 1, 1, hour, minute));
  }

  // ── NOTE ────────────────────────────────────────────────

  Widget _buildNote() {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Add a note (Optional)',
          style: GoogleFonts.poppins(
            color: _textDark,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('booking-note'),
          controller: _noteController,
          readOnly: _result != null || _submitting,
          minLines: 3,
          maxLines: 3,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          // A changed note is a new request, so it needs a new key.
          onChanged: (_) => _idempotencyKey = null,
          style: GoogleFonts.poppins(color: _textDark, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'What would you like to focus on?',
            hintStyle: GoogleFonts.poppins(
              color: _hint,
              fontSize: 13,
            ),
            counterText: '',
            filled: true,
            fillColor: _surface,
            contentPadding: const EdgeInsets.all(14),
            border: border(_inputBorder),
            enabledBorder: border(_inputBorder),
            focusedBorder: border(_primaryBlue),
          ),
        ),
      ],
    );
  }

  // ── FOOTER ──────────────────────────────────────────────

  /// The platform rate × lessons, e.g. "R180.00"; null until it is known.
  String? get _priceText {
    final rate = _hourlyRate;
    if (rate == null) return null;
    final parts = rate.split('.');
    final rands = int.tryParse(parts.first);
    final cents = parts.length > 1
        ? int.tryParse(parts[1].padRight(2, '0').substring(0, 2))
        : 0;
    if (rands == null || cents == null) return null;
    final total = (rands * 100 + cents) * widget.lessonCount;
    return 'R${total ~/ 100}.${(total % 100).toString().padLeft(2, '0')}';
  }

  Widget _buildFooter() {
    final price = _priceText;
    final canSend =
        !_loading &&
        _error == null &&
        !_submitting &&
        _selected.length == widget.lessonCount;
    return Container(
      color: _background,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isPackage
                              ? '${widget.lessonCount} × 1 Hour Sessions'
                              : '1 Hour Session',
                          style: GoogleFonts.poppins(
                            color: _textMuted,
                            fontSize: 14,
                          ),
                        ),
                        if (_isPackage)
                          Text(
                            'Any package discount is shown at payment.',
                            style: GoogleFonts.poppins(
                              color: _textMuted,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (price != null)
                    Text(
                      price,
                      style: GoogleFonts.poppins(
                        color: _textDark,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              if (_submitError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _submitError!,
                    key: const ValueKey('purchase-error'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: _errorRed,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _result != null
                    ? () => _openPayment(_result!)
                    : canSend
                    ? _submit
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _primaryBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _primaryBlue.withValues(alpha: 0.4),
                  disabledForegroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _result != null
                                ? 'Continue to Payment'
                                : 'Send Booking Request',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
