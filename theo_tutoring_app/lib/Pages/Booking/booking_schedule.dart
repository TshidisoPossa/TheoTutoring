import 'package:flutter/material.dart';

import 'booking_api.dart';
import 'booking_flow_context.dart';
import 'booking_payment_method.dart';

class BookingSchedulePage extends StatefulWidget {
  const BookingSchedulePage({required this.flow, this.purchaseType = 'Single', this.lessonCount = 1, this.api, super.key});
  final BookingFlowContext flow;
  final String purchaseType;
  final int lessonCount;
  final BookingFlowApi? api;

  @override
  State<BookingSchedulePage> createState() => _BookingSchedulePageState();
}

class _BookingSchedulePageState extends State<BookingSchedulePage> {
  late final DateTime _today = DateUtils.dateOnly(DateTime.now());
  late DateTime _date = _today;
  late final DateTime _lastDate = _today.add(const Duration(days: 90));
  late final BookingFlowApi _api = widget.api ?? HttpBookingFlowApi();
  late final bool _ownsApi = widget.api == null;
  List<AvailableBookingSlot> _slots = const [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _submitError;
  String? _idempotencyKey;
  BookingPurchaseResult? _result;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { if (_ownsApi) _api.close(); super.dispose(); }

  String _dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final slots = await _api.availability(
        tutorId: widget.flow.selection.tutorId,
        subjectId: widget.flow.selection.subjectId,
        from: _dateKey(_today), through: _dateKey(_lastDate),
      );
      if (!mounted) return;
      setState(() { _slots = slots; _loading = false; });
    } on BookingApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Available times could not be loaded.'; _loading = false; });
    }
  }

  void _toggle(AvailableBookingSlot slot) {
    final key = '${slot.date}|${slot.startTime}';
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else if (_selected.length < widget.lessonCount) {
        _selected.add(key);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Choose up to ${widget.lessonCount} lesson${widget.lessonCount == 1 ? '' : 's'}.')));
        return;
      }
      _idempotencyKey = null;
      _submitError = null;
    });
  }

  Future<void> _submit() async {
    if (_selected.length != widget.lessonCount || _submitting) return;
    final slots = _slots.where((s) => _selected.contains('${s.date}|${s.startTime}')).toList()
      ..sort((a, b) => '${a.date} ${a.startTime}'.compareTo('${b.date} ${b.startTime}'));
    if (slots.length != widget.lessonCount) {
      setState(() => _submitError = 'Choose available times for every lesson.');
      return;
    }
    _idempotencyKey ??= 'booking-${DateTime.now().microsecondsSinceEpoch}';
    final request = <String, Object>{
      'tutorId': widget.flow.selection.tutorId,
      'subjectId': widget.flow.selection.subjectId,
      'purchaseType': widget.purchaseType,
      'schedulingMode': 'manual',
      'idempotencyKey': _idempotencyKey!,
      'lessons': [for (final s in slots) {'date': s.date, 'startTime': s.startTime, 'endTime': s.endTime}],
    };
    setState(() { _submitting = true; _submitError = null; });
    try {
      final result = await _api.createPurchase(request);
      if (!mounted) return;
      setState(() { _submitting = false; _result = result; });
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => BookingPaymentMethodPage(
          flow: widget.flow,
          purchase: result,
          api: _api,
        ),
      ));
    } on BookingApiException catch (e) {
      if (mounted) setState(() { _submitting = false; _submitError = e.message; });
    } catch (_) {
      if (mounted) setState(() { _submitting = false; _submitError = 'Booking could not be confirmed. Retry using the same request.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final todaysSlots = _slots.where((s) => s.date == _dateKey(_date)).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),
      appBar: AppBar(title: const Text('Schedule lesson')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${widget.flow.tutor.name} · ${widget.flow.subject.subjectName}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(widget.purchaseType == 'Single' ? 'Choose 1 available 60-minute lesson.' : 'Choose ${widget.lessonCount} available 60-minute lessons.'),
        CalendarDatePicker(
          initialDate: _date, firstDate: _today, lastDate: _lastDate,
          onDateChanged: (d) => setState(() => _date = d),
        ),
        if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (_error != null) ...[
          Text(_error!, key: const ValueKey('availability-error')),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
        if (!_loading && _error == null && todaysSlots.isEmpty) const Padding(
          padding: EdgeInsets.all(16), child: Text('No available times on this date. Choose another date.'),
        ),
        for (final slot in todaysSlots)
          Card(child: CheckboxListTile(
            value: _selected.contains('${slot.date}|${slot.startTime}'),
            title: Text('${slot.startTime}–${slot.endTime}'),
            subtitle: Text(slot.date),
            onChanged: _submitting ? null : (_) => _toggle(slot),
          )),
        if (_selected.isNotEmpty) Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('${_selected.length} of ${widget.lessonCount} selected'),
        ),
        if (_submitError != null) Text(_submitError!, key: const ValueKey('purchase-error'), style: const TextStyle(color: Colors.red)),
        if (_result != null) const Text('Request submitted. Payment has not occurred; lessons are not confirmed.'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: !_loading && _error == null && !_submitting && _selected.length == widget.lessonCount && _result == null ? _submit : null,
          child: _submitting ? const CircularProgressIndicator() : const Text('Submit booking request'),
        ),
      ])),
    );
  }
}
