import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/tutor_availability.dart';
import 'package:theo_tutoring_app/services/google_meet_connect.dart';

// Registration Step 3: the Connect Google Meet card. Google's window and the
// backend are fakes, so no real token or room is used.

class _FakeUser extends Fake implements User {
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'firebase-token';
}

Future<void> _open(
  WidgetTester tester,
  Future<String> Function() requestMeetToken,
) {
  return tester.pumpWidget(
    MaterialApp(
      home: TutorAvailabilityPage(
        firebaseUser: _FakeUser(),
        requestMeetToken: requestMeetToken,
      ),
    ),
  );
}

ElevatedButton _completeButton(WidgetTester tester) => tester.widget(
  find.widgetWithText(ElevatedButton, 'Complete registration'),
);

Future<void> _tapConnect(WidgetTester tester) async {
  final connect = find.text('Connect Google Meet').last; // the button
  await tester.ensureVisible(connect);
  await tester.tap(connect);
  await tester.pumpAndSettle();
}

/// A backend that answers POST /auth/tutor/meet-link with [status] and
/// [body], recording what was sent.
MockClient _backend(
  int status,
  Map<String, dynamic> body, {
  List<http.Request>? sent,
}) => MockClient((request) async {
  sent?.add(request);
  return http.Response(jsonEncode(body), status);
});

void main() {
  testWidgets('Complete registration stays disabled until Meet is connected', (
    tester,
  ) async {
    await _open(tester, () async => 'google-token');
    expect(_completeButton(tester).onPressed, isNull);
  });

  testWidgets('closing Google\'s window shows a message and stays on Step 3', (
    tester,
  ) async {
    await _open(tester, () async => throw const MeetNotConnected());
    await _tapConnect(tester);

    expect(find.text("Google Meet wasn't connected. Please try again."),
        findsOneWidget);
    expect(find.text('Google Meet connected'), findsNothing);
    expect(_completeButton(tester).onPressed, isNull);
  });

  testWidgets('connecting sends the Google token and enables registration', (
    tester,
  ) async {
    final sent = <http.Request>[];
    await http.runWithClient(() async {
      await _open(tester, () async => 'google-token');
      await _tapConnect(tester);
    }, () => _backend(200, {'meetConnected': true}, sent: sent));

    expect(sent.single.url.path, '/auth/tutor/meet-link');
    expect(sent.single.headers['Authorization'], 'Bearer firebase-token');
    expect(jsonDecode(sent.single.body), {'accessToken': 'google-token'});
    expect(find.text('Google Meet connected'), findsOneWidget);
    expect(_completeButton(tester).onPressed, isNotNull);
  });

  testWidgets('a refused Google account shows the server message', (
    tester,
  ) async {
    const refused =
        "We couldn't create a Meet room with this account. "
        'Try another Google account.';
    await http.runWithClient(() async {
      await _open(tester, () async => 'google-token');
      await _tapConnect(tester);
    }, () => _backend(400, {'error': refused}));

    expect(find.text(refused), findsOneWidget);
    expect(_completeButton(tester).onPressed, isNull);
  });
}
