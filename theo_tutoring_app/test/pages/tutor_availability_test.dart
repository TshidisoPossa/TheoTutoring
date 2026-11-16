import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/tutor_availability.dart';

// Registration Step 3: weekly hours only. Google Meet is optional and is
// connected later from the Profile page, so this step has no Meet card and
// never waits for one. The backend is a fake.

class _FakeUser extends Fake implements User {
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'firebase-token';
}

Future<void> _open(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(home: TutorAvailabilityPage(firebaseUser: _FakeUser())),
  );
}

Finder get _completeFinder =>
    find.widgetWithText(ElevatedButton, 'Complete registration');

ElevatedButton _completeButton(WidgetTester tester) =>
    tester.widget(_completeFinder);

Future<void> _tapComplete(WidgetTester tester) async {
  await tester.ensureVisible(_completeFinder);
  await tester.tap(_completeFinder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Step 3 has no Connect Google Meet card', (tester) async {
    await _open(tester);

    expect(find.text('Connect Google Meet'), findsNothing);
    expect(find.text('Google Meet connected'), findsNothing);
  });

  testWidgets('Complete registration is enabled without Google Meet', (
    tester,
  ) async {
    await _open(tester);

    expect(_completeButton(tester).onPressed, isNotNull);
  });

  testWidgets('no ticked hours shows the message and sends nothing', (
    tester,
  ) async {
    final sent = <http.Request>[];
    await http.runWithClient(() async {
      await _open(tester);
      await _tapComplete(tester);
    }, () => MockClient((request) async {
      sent.add(request);
      return http.Response('{}', 200);
    }));

    expect(sent, isEmpty);
    expect(
      find.text('Tap at least one time slot you are available.'),
      findsWidgets,
    );
  });

  testWidgets('ticked hours are sent and a server error is shown', (
    tester,
  ) async {
    const refused = 'Please complete your teaching profile (Step 2) first.';
    final sent = <http.Request>[];
    await http.runWithClient(() async {
      await _open(tester);
      final monday = find.bySemanticsLabel('Monday Morning');
      await tester.ensureVisible(monday);
      await tester.tap(monday);
      await tester.pump();
      await _tapComplete(tester);
    }, () => MockClient((request) async {
      sent.add(request);
      return http.Response(jsonEncode({'error': refused}), 400);
    }));

    expect(sent.single.url.path, '/auth/tutor/availability');
    expect(sent.single.headers['Authorization'], 'Bearer firebase-token');
    expect(jsonDecode(sent.single.body), {
      'availability': [
        {'day': 'Monday', 'startTime': '08:00', 'endTime': '12:00'},
      ],
    });
    expect(find.text(refused), findsOneWidget);
  });
}
