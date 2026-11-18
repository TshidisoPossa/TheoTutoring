import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/account_suspension_page.dart';
import 'package:theo_tutoring_app/services/account_suspension_api.dart';

const _reason = 'Repeated no-shows for booked lessons.';
const _explanation =
    'I was in hospital that week and could not attend my lessons.';

Map<String, dynamic> _status({
  String accountStatus = 'Suspended',
  bool canAppeal = true,
  Map<String, dynamic>? suspension = const {
    'suspensionId': 4,
    'reason': _reason,
    'suspendedAt': '2026-11-10T08:30:00.000000Z',
    'status': 'Active',
    'liftedAt': null,
    'liftReason': null,
  },
  Map<String, dynamic>? appeal,
}) => {
  'role': 'student',
  'accountStatus': accountStatus,
  'suspension': suspension,
  'appeal': appeal,
  'canAppeal': canAppeal,
  'explanationMinLength': 20,
  'explanationMaxLength': 2000,
};

Map<String, dynamic> _appeal(String status, {String? note}) => {
  'appealId': 9,
  'explanation': _explanation,
  'submittedAt': '2026-11-11T09:00:00.000000Z',
  'status': status,
  'decisionNote': note,
  'decidedAt': status == 'Pending' ? null : '2026-11-12T10:00:00.000000Z',
};

/// Stand-in for GET /account/suspension and POST .../appeal.
class _Backend {
  _Backend(this.state);

  Map<String, dynamic> state;
  final requests = <http.Request>[];
  http.Response? getResponse;
  http.Response? postResponse;
  Completer<void>? holdGet;

  late final client = MockClient((request) async {
    requests.add(request);
    expect(request.headers['Authorization'], 'Bearer user-token');
    if (request.method == 'GET') {
      await holdGet?.future;
      return getResponse ?? http.Response(jsonEncode(state), 200);
    }
    if (postResponse != null) return postResponse!;
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final appeal = _appeal('Pending')
      ..['explanation'] = body['explanation'];
    state = _status(canAppeal: false, appeal: appeal);
    return http.Response(jsonEncode(appeal), 201);
  });

  AccountSuspensionApi api() =>
      AccountSuspensionApi(client: client, tokenProvider: () async => 'user-token');

  Iterable<http.Request> get posts => requests.where((r) => r.method == 'POST');
}

Future<void> _pump(
  WidgetTester tester,
  _Backend backend, {
  Future<void> Function()? onSignOut,
  Future<void> Function()? onReinstated,
}) async {
  tester.view.physicalSize = const Size(700, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: AccountSuspensionPage(
        api: backend.api(),
        onSignOut: onSignOut,
        onReinstated: onReinstated,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the suspension notice with its reason and the appeal form',
      (tester) async {
    final backend = _Backend(_status());
    await _pump(tester, backend, onSignOut: () async {});

    expect(find.text('Your account has been suspended'), findsOneWidget);
    expect(find.text(_reason), findsOneWidget);
    expect(find.textContaining('Suspended on'), findsOneWidget);
    expect(find.text('Appeal this suspension'), findsOneWidget);
    expect(find.byKey(const ValueKey('appeal-explanation')), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a spinner while loading', (tester) async {
    final backend = _Backend(_status())..holdGet = Completer<void>();
    tester.view.physicalSize = const Size(700, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: AccountSuspensionPage(api: backend.api())),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    backend.holdGet!.complete();
    await tester.pumpAndSettle();
    expect(find.text(_reason), findsOneWidget);
  });

  testWidgets('the explanation is validated before anything is sent', (
    tester,
  ) async {
    final backend = _Backend(_status());
    await _pump(tester, backend);

    await tester.tap(find.text('Send appeal'));
    await tester.pumpAndSettle();
    expect(find.text('Please write your explanation.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('appeal-explanation')),
      'Too short',
    );
    await tester.tap(find.text('Send appeal'));
    await tester.pumpAndSettle();
    expect(find.text('Please write at least 20 characters.'), findsOneWidget);
    expect(backend.posts, isEmpty);
  });

  testWidgets('sending an appeal shows it as under review', (tester) async {
    final backend = _Backend(_status());
    await _pump(tester, backend);

    await tester.enterText(
      find.byKey(const ValueKey('appeal-explanation')),
      '  $_explanation  ',
    );
    await tester.tap(find.text('Send appeal'));
    await tester.pumpAndSettle();

    // Only the explanation is sent; the user is known from the token
    expect(jsonDecode(backend.posts.single.body), {'explanation': _explanation});
    expect(backend.posts.single.url.path, '/account/suspension/appeal');
    expect(find.text('Your appeal was sent.'), findsOneWidget);
    expect(find.text('Appeal under review'), findsOneWidget);
    expect(find.text(_explanation), findsOneWidget);
    expect(find.text('Send appeal'), findsNothing);
  });

  testWidgets('a refused appeal shows the server message and the real state',
      (tester) async {
    final backend = _Backend(_status())
      ..postResponse = http.Response(
        jsonEncode({
          'error': 'You have already appealed this suspension.',
          'code': 'appeal_exists',
        }),
        409,
      );
    await _pump(tester, backend);
    // Meanwhile the appeal was sent from another device
    backend.state = _status(canAppeal: false, appeal: _appeal('Pending'));

    await tester.enterText(
      find.byKey(const ValueKey('appeal-explanation')),
      _explanation,
    );
    await tester.tap(find.text('Send appeal'));
    await tester.pumpAndSettle();
    expect(find.text('Appeal under review'), findsOneWidget);
  });

  testWidgets('a pending appeal is shown without the form', (tester) async {
    final backend = _Backend(
      _status(canAppeal: false, appeal: _appeal('Pending')),
    );
    await _pump(tester, backend);
    expect(find.text('Appeal under review'), findsOneWidget);
    expect(find.textContaining('Your appeal, sent'), findsOneWidget);
    expect(find.byKey(const ValueKey('appeal-explanation')), findsNothing);
  });

  testWidgets('a rejected appeal shows the decision and explanation', (
    tester,
  ) async {
    const note = 'The missed lessons were confirmed by three tutors.';
    final backend = _Backend(
      _status(canAppeal: false, appeal: _appeal('Rejected', note: note)),
    );
    await _pump(tester, backend, onReinstated: () async {});
    expect(find.text('Appeal rejected'), findsOneWidget);
    expect(find.text(note), findsOneWidget);
    expect(find.textContaining('final for this suspension'), findsOneWidget);
    expect(find.textContaining('Decided on'), findsOneWidget);
    // Still suspended: no way into the app
    expect(find.text('Continue to TheoTutoring'), findsNothing);
    expect(find.byKey(const ValueKey('appeal-explanation')), findsNothing);
  });

  testWidgets('an approved appeal lets the user continue into the app', (
    tester,
  ) async {
    var continued = false;
    final backend = _Backend(
      _status(
        accountStatus: 'Active',
        canAppeal: false,
        suspension: {
          'suspensionId': 4,
          'reason': _reason,
          'suspendedAt': '2026-11-10T08:30:00.000000Z',
          'status': 'Lifted',
          'liftReason': 'AppealApproved',
        },
        appeal: _appeal('Approved', note: 'Thanks for explaining.'),
      ),
    );
    await _pump(
      tester,
      backend,
      onReinstated: () async => continued = true,
    );
    expect(find.text('Your account is no longer suspended.'), findsOneWidget);
    expect(find.text('Appeal approved'), findsOneWidget);
    expect(find.text('Thanks for explaining.'), findsOneWidget);
    await tester.tap(find.text('Continue to TheoTutoring'));
    await tester.pumpAndSettle();
    expect(continued, isTrue);
  });

  testWidgets('a suspension with no record says to contact support', (
    tester,
  ) async {
    final backend = _Backend(_status(canAppeal: false, suspension: null));
    await _pump(tester, backend);
    expect(find.text('Your account has been suspended'), findsOneWidget);
    expect(find.textContaining('cannot be appealed here'), findsOneWidget);
    expect(find.byKey(const ValueKey('appeal-explanation')), findsNothing);
  });

  testWidgets('a load error can be retried; sign out works', (tester) async {
    var signedOut = false;
    final backend = _Backend(_status())
      ..getResponse = http.Response(
        jsonEncode({'error': 'Your account details could not be loaded.'}),
        500,
      );
    await _pump(tester, backend, onSignOut: () async => signedOut = true);
    expect(
      find.text('Your account details could not be loaded.'),
      findsWidgets,
    );
    backend.getResponse = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text(_reason), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
  });

  test('notification cards for suspensions and appeals link here', () {
    expect(accountNoticeLink('AccountSuspended'), 'View suspension and appeal');
    expect(accountNoticeLink('AppealApproved'), 'View appeal');
    expect(accountNoticeLink('AppealRejected'), 'View appeal');
    expect(accountNoticeLink('PaymentReceived'), isNull);
  });
}
