import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/api.dart';
import '../services/google_meet_connect.dart';
import 'verify_email_page.dart';

class TutorAvailabilityPage extends StatefulWidget {
  const TutorAvailabilityPage({
    super.key,
    required this.firebaseUser,
    this.requestMeetToken = requestMeetAccessToken,
  });

  final User firebaseUser;

  // Opens Google's window for the Meet token (replaced in widget tests)
  final Future<String> Function() requestMeetToken;

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

  // The weekly grid from the documentation (9.3 / 11.1): each period is a
  // fixed block of hours, in minutes after midnight. The tutor's Profile
  // page uses the same three periods.
  static const _periods = {
    'Morning': (start: 480, end: 720), // 08:00-12:00
    'Afternoon': (start: 720, end: 1020), // 12:00-17:00
    'Evening': (start: 1020, end: 1200), // 17:00-20:00
  };

  final _selected = <String, Set<String>>{}; // day -> ticked periods
  bool _isSubmitting = false;
  bool _showValidation = false;
  bool _meetConnected = false; // Complete registration waits for this
  bool _isConnectingMeet = false;

  bool _isTicked(String day, String period) =>
      _selected[day]?.contains(period) ?? false;

  void _toggle(String day, String period) {
    if (_isSubmitting) return;
    setState(() {
      final periods = _selected.putIfAbsent(day, () => {});
      if (!periods.remove(period)) periods.add(period);
    });
  }

  String _formatTime(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  String? _validationError() {
    if (_selected.values.every((periods) => periods.isEmpty)) {
      return 'Tap at least one time slot you are available.';
    }
    return null;
  }

  // The ticked cells as time ranges, one per run of touching periods
  // (Morning + Afternoon -> 08:00-17:00). This is the same shape the
  // Profile page saves, so both pages show the grid the same way.
  List<Map<String, String>> _slotsToSend() {
    final slots = <Map<String, String>>[];
    for (final day in _days) {
      int? start;
      int? end;
      for (final entry in _periods.entries) {
        if (!_isTicked(day, entry.key)) continue;
        if (end == entry.value.start) {
          end = entry.value.end; // touches the previous period: extend it
          continue;
        }
        if (start != null) {
          slots.add({
            'day': day,
            'startTime': _formatTime(start),
            'endTime': _formatTime(end!),
          });
        }
        start = entry.value.start;
        end = entry.value.end;
      }
      if (start != null) {
        slots.add({
          'day': day,
          'startTime': _formatTime(start),
          'endTime': _formatTime(end!),
        });
      }
    }
    return slots;
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
            body: jsonEncode({'availability': _slotsToSend()}),
          )
          .timeout(const Duration(seconds: 20));

      final body = _decodeBody(response);
      if (response.statusCode != 200 ||
          body['status'] != 'Pending' ||
          body['tutorId'] is! int) {
        throw _SubmissionFailure(_responseError(response, body));
      }

      if (!mounted) return;
      // The next page emails a 6-digit code and waits for it, then signs
      // out to the login page. Clears registration so Back cannot return.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => VerifyEmailPage(
            email: widget.firebaseUser.email ?? '',
            verifiedMessage:
                'Your email is verified and your application is with our '
                'team for review. Log in any time to check its status.',
          ),
        ),
        (_) => false,
      );
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

  // Connect Google Meet: Google's window gives a token, and the backend
  // creates the tutor's Meet room with it (POST /auth/tutor/meet-link).
  // Coming back to this page means connecting again, which replaces the room.
  Future<void> _connectMeet() async {
    if (_isConnectingMeet || _isSubmitting) return;
    setState(() => _isConnectingMeet = true);
    try {
      // Google's window first: after any other await the browser can block it
      final accessToken = await widget.requestMeetToken();
      final token = await widget.firebaseUser.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw const _SubmissionFailure(
          'Could not verify your account. Sign in again.',
        );
      }
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/auth/tutor/meet-link'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'accessToken': accessToken}),
          )
          .timeout(const Duration(seconds: 20));

      final body = _decodeBody(response);
      if (response.statusCode != 200 || body['meetConnected'] != true) {
        throw _SubmissionFailure(
          _responseError(response, body, fallback: _meetFailedMessage),
        );
      }
      if (mounted) setState(() => _meetConnected = true);
    } on MeetNotConnected {
      if (mounted) _showMessage(meetNotConnectedMessage);
    } on _SubmissionFailure catch (error) {
      if (mounted) _showMessage(error.message);
    } on Exception {
      if (mounted) _showMessage(_meetFailedMessage);
    } finally {
      if (mounted) setState(() => _isConnectingMeet = false);
    }
  }

  static const _meetFailedMessage =
      "We couldn't connect Google Meet. Please try again.";

  Map<String, dynamic> _decodeBody(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // The status-based message below covers non-JSON errors.
    }
    return {};
  }

  String _responseError(
    http.Response response,
    Map<String, dynamic> body, {
    String? fallback,
  }) {
    final message = body['error'];
    if (message is String && message.trim().isNotEmpty) return message;
    return fallback ??
        'The server rejected availability (HTTP ${response.statusCode}).';
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
                    'Tap the times you are usually available each week. '
                    'You can change this later on your Profile page.',
                  ),
                  const SizedBox(height: 20),
                  _buildGrid(),
                  const SizedBox(height: 12),
                  _buildLegend(),
                  if (validationError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      validationError,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _buildMeetCard(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting || !_meetConnected
                          ? null
                          : _submit,
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

  // Monday to Saturday across the top, Morning / Afternoon / Evening down
  // the side. Tapping a cell marks that period as available.
  Widget _buildGrid() {
    const blue = Colors.blue;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 78),
                for (final day in _days)
                  Expanded(
                    child: Center(
                      child: Text(
                        day.substring(0, 3),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final period in _periods.keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 78,
                      child: Text(
                        period,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    for (final day in _days)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: _isTicked(day, period),
                          label: '$day $period',
                          child: GestureDetector(
                            onTap: () => _toggle(day, period),
                            child: Container(
                              height: 36,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: _isTicked(day, period)
                                    ? blue
                                    : blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: _isTicked(day, period)
                                  ? const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Lessons happen in the tutor's own Google Meet room, created here.
  // Complete registration stays disabled until it is connected.
  Widget _buildMeetCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _meetConnected
                      ? Icons.check_circle
                      : Icons.videocam_outlined,
                  color: _meetConnected ? Colors.green : Colors.blue,
                ),
                const SizedBox(width: 8),
                Text(
                  _meetConnected
                      ? 'Google Meet connected'
                      : 'Connect Google Meet',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _meetConnected
                  ? 'Your lessons will take place in your own Google Meet '
                        'room.'
                  : 'Your lessons take place in your own Google Meet room. '
                        'Sign in with Google once and the app creates it. '
                        'You need this to complete registration.',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            if (!_meetConnected) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isConnectingMeet || _isSubmitting
                    ? null
                    : _connectMeet,
                icon: const Icon(Icons.videocam_outlined),
                label: Text(
                  _isConnectingMeet ? 'Connecting…' : 'Connect Google Meet',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // The hours behind each period
  Widget _buildLegend() {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final entry in _periods.entries)
          Text(
            '${entry.key}: ${_formatTime(entry.value.start)}–'
            '${_formatTime(entry.value.end)}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
      ],
    );
  }
}

class _SubmissionFailure implements Exception {
  const _SubmissionFailure(this.message);
  final String message;
}
