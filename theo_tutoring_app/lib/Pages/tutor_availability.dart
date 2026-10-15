import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/api.dart';

class TutorAvailabilityPage extends StatefulWidget {
  const TutorAvailabilityPage({super.key, required this.firebaseUser});

  final User firebaseUser;

  @override
  State<TutorAvailabilityPage> createState() => _TutorAvailabilityPageState();
}

class _TutorAvailabilityPageState extends State<TutorAvailabilityPage> {
  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  final _slots = <_AvailabilitySlot>[_AvailabilitySlot()];
  bool _isSubmitting = false;
  bool _showValidation = false;

  @override
  void dispose() {
    for (final slot in _slots) {
      slot.dispose();
    }
    super.dispose();
  }

  int? _minutes(TimeOfDay? time) =>
      time == null ? null : time.hour * 60 + time.minute;

  String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String? _validationError() {
    if (_slots.isEmpty) return 'Add at least one availability slot.';
    final ranges = <String, List<(int, int)>>{};
    for (final slot in _slots) {
      final start = _minutes(slot.start);
      final end = _minutes(slot.end);
      if (slot.day == null || start == null || end == null) {
        return 'Choose a day, start time, and end time for every slot.';
      }
      if (start >= end) return 'Each start time must be before its end time.';
      ranges.putIfAbsent(slot.day!, () => []).add((start, end));
    }

    for (final dayRanges in ranges.values) {
      dayRanges.sort((a, b) => a.$1.compareTo(b.$1));
      for (var index = 1; index < dayRanges.length; index++) {
        if (dayRanges[index].$1 < dayRanges[index - 1].$2) {
          return 'Availability slots on the same day cannot overlap.';
        }
      }
    }
    return null;
  }

  Future<void> _chooseTime(
    _AvailabilitySlot slot, {
    required bool isStart,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          (isStart ? slot.start : slot.end) ??
          const TimeOfDay(hour: 9, minute: 0),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        slot.start = picked;
      } else {
        slot.end = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final error = _validationError();
    setState(() => _showValidation = true);
    if (error != null) {
      _showMessage(error);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final token = await widget.firebaseUser.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw const _SubmissionFailure(
          'Could not verify your account. Sign in again.',
        );
      }
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/auth/tutor/availability'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'availability': [
                for (final slot in _slots)
                  {
                    'day': slot.day,
                    'startTime': _formatTime(slot.start!),
                    'endTime': _formatTime(slot.end!),
                  },
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));

      final body = _decodeBody(response);
      if (response.statusCode != 200 ||
          body['status'] != 'Pending' ||
          body['tutorId'] is! int) {
        throw _SubmissionFailure(_responseError(response, body));
      }

      var signedOut = true;
      try {
        await FirebaseAuth.instance.signOut();
      } on Exception {
        signedOut = false;
      }
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            signedOut
                ? 'Registration complete. Your application is under review.'
                : 'Registration is complete. Please sign out before leaving this device.',
          ),
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on _SubmissionFailure catch (error) {
      if (mounted) _showMessage(error.message);
    } on Exception {
      if (mounted) {
        _showMessage(
          'The server did not confirm completion. Your account is retained; '
          'retry this step to safely check the registration status.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // The status-based message below covers non-JSON errors.
    }
    return {};
  }

  String _responseError(http.Response response, Map<String, dynamic> body) {
    final message = body['error'];
    if (message is String && message.trim().isNotEmpty) return message;
    return 'The server rejected availability (HTTP ${response.statusCode}).';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final validationError = _showValidation ? _validationError() : null;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        title: const Text('TheoTutoring'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LinearProgressIndicator(value: 1),
                  const SizedBox(height: 8),
                  const Text('STEP 3 OF 3'),
                  const SizedBox(height: 12),
                  const Text(
                    'When are you available?',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Choose one or more weekly time slots. Times use a 24-hour clock.',
                  ),
                  const SizedBox(height: 20),
                  for (var index = 0; index < _slots.length; index++)
                    _buildSlot(index),
                  if (validationError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      validationError,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _isSubmitting || _slots.length >= 30
                          ? null
                          : () =>
                                setState(() => _slots.add(_AvailabilitySlot())),
                      icon: const Icon(Icons.add),
                      label: const Text('Add another time slot'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        disabledBackgroundColor: Colors.grey.shade300,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        _isSubmitting ? 'Submitting…' : 'Complete registration',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlot(int index) {
    final slot = _slots[index];
    final start = slot.start;
    final end = slot.end;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: slot.day,
                    decoration: const InputDecoration(labelText: 'Day'),
                    items: [
                      for (final day in _days)
                        DropdownMenuItem(value: day, child: Text(day)),
                    ],
                    onChanged: _isSubmitting
                        ? null
                        : (day) => setState(() => slot.day = day),
                  ),
                ),
                if (_slots.length > 1)
                  IconButton(
                    tooltip: 'Remove slot',
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(() {
                            _slots.removeAt(index).dispose();
                          }),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSubmitting
                        ? null
                        : () => _chooseTime(slot, isStart: true),
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      start == null ? 'Start time' : _formatTime(start),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSubmitting
                        ? null
                        : () => _chooseTime(slot, isStart: false),
                    icon: const Icon(Icons.schedule),
                    label: Text(end == null ? 'End time' : _formatTime(end)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailabilitySlot {
  String? day = 'Monday';
  TimeOfDay? start;
  TimeOfDay? end;

  void dispose() {}
}

class _SubmissionFailure implements Exception {
  const _SubmissionFailure(this.message);
  final String message;
}
