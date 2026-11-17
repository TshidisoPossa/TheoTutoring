import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Admin/admin_documents.dart';

// The Documents section of the admin tutor and student overviews.

Future<void> _pump(
  WidgetTester tester,
  List<AdminDocument> documents, {
  required Future<bool> Function(Uri uri) openUrl,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: AdminDocumentLinks(documents: documents, openUrl: openUrl),
    ),
  ),
);

void main() {
  testWidgets('View opens the uploaded file', (tester) async {
    final opened = <Uri>[];
    await _pump(
      tester,
      [
        (
          label: 'ID document',
          url: 'https://res.cloudinary.com/demo/image/upload/id.png',
        ),
      ],
      openUrl: (uri) async {
        opened.add(uri);
        return true;
      },
    );

    await tester.tap(find.text('View ID document'));
    await tester.pump();
    expect(opened.single.toString(),
        'https://res.cloudinary.com/demo/image/upload/id.png');
  });

  testWidgets('a missing or unsafe link is "not provided"', (tester) async {
    await _pump(
      tester,
      [
        (label: 'ID document', url: null),
        (label: 'Qualification certificate', url: 'http://insecure.test/c.png'),
      ],
      openUrl: (_) async => fail('nothing should open'),
    );
    expect(find.text('ID document: not provided'), findsOneWidget);
    expect(
      find.text('Qualification certificate: not provided'),
      findsOneWidget,
    );
    expect(find.textContaining('View'), findsNothing);
  });

  testWidgets('a file that cannot open says so', (tester) async {
    await _pump(
      tester,
      [
        (
          label: 'Proof of registration',
          url: 'https://res.cloudinary.com/demo/image/upload/proof.png',
        ),
      ],
      openUrl: (_) async => false,
    );
    await tester.tap(find.text('View Proof of registration'));
    await tester.pump();
    expect(find.text('Could not open this document.'), findsOneWidget);
  });
}
