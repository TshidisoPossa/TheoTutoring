import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/admin_subjects_service.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_subjects.dart';
import 'package:theo_tutoring_app/Pages/Admin/models/admin_subject_models.dart';

/// In-memory stand-in for the Subjects service. Its HTTP client fails the
/// test if any real request is attempted.
class _FakeSubjectsService extends AdminSubjectsService {
  _FakeSubjectsService([List<AdminSubject>? initial])
    : subjects = [...(initial ?? _defaultSubjects)],
      super(
        client: MockClient(
          (request) async => fail('Unexpected HTTP request: ${request.url}'),
        ),
        tokenProvider: () async => 'admin-token',
      );

  static const _defaultSubjects = [
    AdminSubject(subjectId: 1, subjectName: 'Mathematics'),
    AdminSubject(subjectId: 2, subjectName: 'Physics'),
    AdminSubject(subjectId: 3, subjectName: 'Chemistry'),
  ];

  final List<AdminSubject> subjects;
  int nextId = 4;

  int fetchCount = 0;
  final created = <String>[];
  final renamed = <(int, String)>[];
  final deleted = <int>[];

  /// When set, fetches wait for it, so loading states can be observed.
  Completer<void>? fetchGate;
  Object? fetchError;
  Object? createError;
  Object? renameError;
  Object? deleteError;

  @override
  Future<AdminSubjectsResult> fetchSubjects() async {
    fetchCount++;
    await fetchGate?.future;
    if (fetchError != null) throw fetchError!;
    return AdminSubjectsResult(subjects: List.of(subjects));
  }

  @override
  Future<AdminSubject> createSubject(String name) async {
    created.add(name);
    if (createError != null) throw createError!;
    final subject = AdminSubject(subjectId: nextId++, subjectName: name);
    subjects.add(subject);
    return subject;
  }

  @override
  Future<AdminSubject> renameSubject(int id, String name) async {
    renamed.add((id, name));
    if (renameError != null) throw renameError!;
    final index = subjects.indexWhere((s) => s.subjectId == id);
    return subjects[index] = AdminSubject(subjectId: id, subjectName: name);
  }

  @override
  Future<void> deleteSubject(int id) async {
    deleted.add(id);
    if (deleteError != null) throw deleteError!;
    subjects.removeWhere((s) => s.subjectId == id);
  }
}

Future<_FakeSubjectsService> _pump(
  WidgetTester tester, [
  _FakeSubjectsService? fake,
]) async {
  final service = fake ?? _FakeSubjectsService();
  addTearDown(service.dispose);
  // Below the shell's 900px sidebar breakpoint (its fixed-width header
  // overflows with the wide Ahem test font, which real fonts do not).
  tester.view.physicalSize = const Size(880, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: AdminSubjectsScreen(service: service)),
  );
  if (service.fetchGate == null) await tester.pumpAndSettle();
  return service;
}

final _dialogField = find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextFormField),
);

final _searchField = find.widgetWithText(TextField, 'Search subjects...');

Future<void> _openAddDialog(WidgetTester tester) async {
  await tester.tap(find.text('Add Subject'));
  await tester.pumpAndSettle();
}

Future<void> _openRenameDialog(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('Rename $name'));
  await tester.pumpAndSettle();
}

Future<void> _submitName(
  WidgetTester tester,
  String name,
  String confirmLabel,
) async {
  await tester.enterText(_dialogField, name);
  await tester.tap(find.widgetWithText(FilledButton, confirmLabel));
  await tester.pumpAndSettle();
}

void main() {
  group('validateSubjectName', () {
    test('accepts trimmed names of 1-100 characters', () {
      expect(validateSubjectName('Mathematics'), isNull);
      expect(validateSubjectName('A' * 100), isNull);
      expect(validateSubjectName('  ${'A' * 100}  '), isNull);
    });

    test('rejects empty, whitespace-only and over-long names', () {
      expect(validateSubjectName(null), 'Enter a subject name.');
      expect(validateSubjectName(''), 'Enter a subject name.');
      expect(validateSubjectName('   '), 'Enter a subject name.');
      expect(validateSubjectName('A' * 101), 'Use 100 characters or fewer.');
    });
  });

  group('loading and display', () {
    testWidgets('shows a spinner until the subjects arrive', (tester) async {
      final gate = Completer<void>();
      final service = await _pump(
        tester,
        _FakeSubjectsService()..fetchGate = gate,
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Mathematics'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(service.fetchCount, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Subject Management'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lists subject names, IDs and the total count', (tester) async {
      await _pump(tester);

      for (final (id, name) in [
        (1, 'Mathematics'),
        (2, 'Physics'),
        (3, 'Chemistry'),
      ]) {
        expect(find.text(name), findsOneWidget);
        expect(find.text('ID: $id'), findsOneWidget);
      }
      expect(find.text('TOTAL SUBJECTS'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('shows an empty state when there are no subjects', (
      tester,
    ) async {
      await _pump(tester, _FakeSubjectsService([]));

      expect(find.text('No subjects yet'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('filters by name and restores all subjects when cleared', (
      tester,
    ) async {
      final service = await _pump(tester);

      await tester.enterText(_searchField, 'PHY');
      await tester.pump();

      expect(find.text('Physics'), findsOneWidget);
      expect(find.text('Mathematics'), findsNothing);
      expect(find.text('Chemistry'), findsNothing);
      expect(find.text('Showing 1 of 3 subjects'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();

      for (final name in ['Mathematics', 'Physics', 'Chemistry']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('Showing 1 of 3 subjects'), findsNothing);
      // Search is local: no extra fetches.
      expect(service.fetchCount, 1);
    });

    testWidgets('shows a no-results state for an unmatched query', (
      tester,
    ) async {
      await _pump(tester);

      await tester.enterText(_searchField, 'Astronomy');
      await tester.pump();

      expect(find.text('No subjects match'), findsOneWidget);
      expect(find.text('Showing 0 of 3 subjects'), findsOneWidget);
      expect(find.text('No subjects yet'), findsNothing);
    });
  });

  group('adding', () {
    testWidgets('sends the trimmed name and reloads the list', (tester) async {
      final service = await _pump(tester);

      await _openAddDialog(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await _submitName(tester, '  Biology  ', 'Add subject');

      expect(service.created, ['Biology']);
      expect(service.fetchCount, 2);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Biology'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('"Biology" was added.'), findsOneWidget);
    });

    testWidgets('rejects empty and whitespace-only names', (tester) async {
      final service = await _pump(tester);
      await _openAddDialog(tester);

      for (final name in ['', '    ']) {
        await _submitName(tester, name, 'Add subject');
        expect(find.text('Enter a subject name.'), findsOneWidget);
      }

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(service.created, isEmpty);
    });

    testWidgets('rejects names longer than 100 characters', (tester) async {
      final service = await _pump(tester);
      await _openAddDialog(tester);

      await _submitName(tester, 'A' * 101, 'Add subject');

      expect(find.text('Use 100 characters or fewer.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(service.created, isEmpty);
    });

    testWidgets('shows the backend error when creation fails', (tester) async {
      final service = await _pump(
        tester,
        _FakeSubjectsService()
          ..createError = Exception('A subject with that name exists.'),
      );

      await _openAddDialog(tester);
      await _submitName(tester, 'Physics', 'Add subject');

      expect(service.created, ['Physics']);
      expect(find.text('A subject with that name exists.'), findsOneWidget);
      expect(service.fetchCount, 1);
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('renaming', () {
    testWidgets('sends the subject ID and trimmed name, then reloads', (
      tester,
    ) async {
      final service = await _pump(tester);

      await _openRenameDialog(tester, 'Physics');
      expect(
        tester.widget<TextFormField>(_dialogField).controller?.text,
        'Physics',
      );
      await _submitName(tester, '  Applied Physics ', 'Save name');

      expect(service.renamed, [(2, 'Applied Physics')]);
      expect(service.fetchCount, 2);
      expect(find.text('Applied Physics'), findsOneWidget);
      expect(find.text('Physics'), findsNothing);
      expect(
        find.text('"Physics" was renamed to "Applied Physics".'),
        findsOneWidget,
      );
    });

    testWidgets('an unchanged name sends no request', (tester) async {
      final service = await _pump(tester);

      await _openRenameDialog(tester, 'Physics');
      await _submitName(tester, ' Physics ', 'Save name');

      expect(find.byType(AlertDialog), findsNothing);
      expect(service.renamed, isEmpty);
      expect(service.fetchCount, 1);
    });

    testWidgets('rejects invalid names', (tester) async {
      final service = await _pump(tester);
      await _openRenameDialog(tester, 'Physics');

      await _submitName(tester, '   ', 'Save name');
      expect(find.text('Enter a subject name.'), findsOneWidget);

      await _submitName(tester, 'B' * 101, 'Save name');
      expect(find.text('Use 100 characters or fewer.'), findsOneWidget);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(service.renamed, isEmpty);
    });

    testWidgets('shows the backend error when renaming fails', (tester) async {
      final service = await _pump(
        tester,
        _FakeSubjectsService()
          ..renameError = Exception('A subject with that name exists.'),
      );

      await _openRenameDialog(tester, 'Physics');
      await _submitName(tester, 'Chemistry', 'Save name');

      expect(service.renamed, [(2, 'Chemistry')]);
      expect(find.text('A subject with that name exists.'), findsOneWidget);
      expect(service.fetchCount, 1);
      expect(find.text('Physics'), findsOneWidget);
    });
  });

  group('deleting', () {
    testWidgets('cancelling the confirmation deletes nothing', (tester) async {
      final service = await _pump(tester);

      await tester.tap(find.byTooltip('Delete Physics'));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Physics"?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(service.deleted, isEmpty);
      expect(service.fetchCount, 1);
      expect(find.text('Physics'), findsOneWidget);
    });

    testWidgets('confirming deletes by ID and reloads the list', (
      tester,
    ) async {
      final service = await _pump(tester);

      await tester.tap(find.byTooltip('Delete Physics'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete subject'));
      await tester.pumpAndSettle();

      expect(service.deleted, [2]);
      expect(service.fetchCount, 2);
      expect(find.text('Physics'), findsNothing);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('"Physics" was deleted.'), findsOneWidget);
    });

    testWidgets('shows the backend message for a subject in use', (
      tester,
    ) async {
      const inUse =
          'Subject is in use by tutors or bookings and cannot be deleted.';
      final service = await _pump(
        tester,
        _FakeSubjectsService()..deleteError = Exception(inUse),
      );

      await tester.tap(find.byTooltip('Delete Physics'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete subject'));
      await tester.pumpAndSettle();

      expect(service.deleted, [2]);
      expect(find.text(inUse), findsOneWidget);
      expect(service.fetchCount, 1);
      expect(find.text('Physics'), findsOneWidget);
    });
  });

  group('errors and retry', () {
    testWidgets('an initial load error offers Retry, which fetches again', (
      tester,
    ) async {
      final service = await _pump(
        tester,
        _FakeSubjectsService()
          ..fetchError = Exception('Subjects are temporarily unavailable.'),
      );

      expect(find.text('Could not load subjects.'), findsOneWidget);
      expect(
        find.text('Subjects are temporarily unavailable.'),
        findsOneWidget,
      );
      expect(find.text('Mathematics'), findsNothing);

      service.fetchError = null;
      await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(service.fetchCount, 2);
      expect(find.text('Could not load subjects.'), findsNothing);
      expect(find.text('Mathematics'), findsOneWidget);
    });

    testWidgets('a failed refresh keeps the list already shown', (
      tester,
    ) async {
      final service = await _pump(tester);

      service.fetchError = Exception('Subjects are temporarily unavailable.');
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      expect(service.fetchCount, 2);
      expect(
        find.text(
          'Could not refresh subjects: Subjects are temporarily unavailable.',
        ),
        findsOneWidget,
      );
      for (final name in ['Mathematics', 'Physics', 'Chemistry']) {
        expect(find.text(name), findsOneWidget);
      }
    });
  });
}
