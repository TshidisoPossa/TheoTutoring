import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:theo_tutoring_app/Pages/Student/student_profile.dart';
import 'package:theo_tutoring_app/Pages/Student/student_profile_api.dart';

const _lerato = StudentProfileData(
  name: 'Lerato Dube',
  email: 'lerato@example.com',
  photo: null,
  institution: 'University of Pretoria',
  subjectsOfInterest: ['Mathematics', 'Calculus 1'],
);

/// Applies a PATCH body to [profile], like the backend does.
StudentProfileData _applied(
  StudentProfileData profile,
  Map<String, Object?> changes,
) {
  String? text(String key, String? old) =>
      changes.containsKey(key) ? changes[key] as String? : old;
  List<String> list(String key, List<String> old) =>
      changes.containsKey(key) ? (changes[key] as List).cast<String>() : old;
  return StudentProfileData(
    name: text('name', profile.name),
    email: profile.email,
    photo: text('photo', profile.photo),
    institution: text('institution', profile.institution),
    subjectsOfInterest: list('subjectsOfInterest', profile.subjectsOfInterest),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Future<StudentProfileData> Function() loadProfile, {
  Future<StudentProfileSaved> Function(Map<String, Object?>)? saveProfile,
  Future<List<String>> Function()? loadSubjects,
  Future<String?> Function()? choosePhoto,
  VoidCallback? onChanged,
}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StudentProfileTab(
          name: 'Lerato',
          email: 'old@example.com',
          institution: null,
          photo: null,
          loadProfile: loadProfile,
          saveProfile: saveProfile,
          loadSubjects:
              loadSubjects ??
              () async => ['Chemistry', 'English', 'Mathematics', 'Physics'],
          choosePhoto: choosePhoto,
          onChanged: onChanged,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the details from GET /students/profile', (tester) async {
    await _pump(tester, () async => _lerato);

    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Lerato Dube'), findsOneWidget);
    expect(find.text('lerato@example.com'), findsOneWidget);
    expect(find.text('University of Pretoria'), findsOneWidget);
    expect(find.text('STUDENT'), findsOneWidget);
    expect(find.text('LD'), findsOneWidget); // initials, no photo
    expect(find.text('old@example.com'), findsNothing);

    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('Calculus 1'), findsOneWidget);
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Dark Mode'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
    // Settings items the student profile does not have
    expect(find.text('Change Password'), findsNothing);
    expect(find.text('Payment Methods'), findsNothing);
    // Sections removed from the design
    expect(find.text('Grade / Level'), findsNothing);
    expect(find.text('Learning Goals'), findsNothing);
    expect(find.text('Preferred Session Times'), findsNothing);
  });

  testWidgets('shows a placeholder when no subjects are chosen', (
    tester,
  ) async {
    await _pump(
      tester,
      () async => const StudentProfileData(
        name: 'Lerato Dube',
        email: 'lerato@example.com',
        photo: null,
        institution: null,
      ),
    );

    expect(find.text('No subjects chosen yet'), findsOneWidget);
  });

  testWidgets('keeps the dashboard details if the profile fails to load', (
    tester,
  ) async {
    await _pump(
      tester,
      () async => throw const StudentProfileException('Please sign in again.'),
    );

    expect(find.text('Lerato'), findsOneWidget);
    expect(find.text('old@example.com'), findsOneWidget);
    expect(find.text('Dark Mode'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);

    // Edit Profile needs the saved details first
    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Save Changes'), findsNothing);
    expect(
      find.text('Your profile could not be loaded. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('Edit Profile saves only what changed', (tester) async {
    Map<String, Object?>? sent;
    var changed = 0;
    await _pump(
      tester,
      () async => _lerato,
      saveProfile: (changes) async {
        sent = changes;
        return StudentProfileSaved(
          profile: _applied(_lerato, changes),
          message: 'Your profile has been saved.',
        );
      },
      onChanged: () => changed++,
    );

    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();

    // The edit view from the design
    expect(find.text('Edit Profile'), findsOneWidget); // now the heading
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Dark Mode'), findsNothing);
    expect(find.text('Grade / Level'), findsNothing);
    expect(find.text('Learning Goals'), findsNothing);
    expect(find.text('Preferred Session Times'), findsNothing);
    // Catalogue subjects plus the one typed at registration
    for (final subject in ['Chemistry', 'Physics', 'Calculus 1']) {
      expect(find.text(subject), findsOneWidget);
    }

    await tester.enterText(
      find.widgetWithText(TextField, 'Lerato Dube'),
      'Lerato Pillay',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'University of Pretoria'),
      'Hyde Park High School',
    );
    await tester.tap(find.text('Physics'));
    await tester.tap(find.text('Calculus 1')); // deselect
    await tester.pump();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(sent, {
      'name': 'Lerato Pillay',
      'institution': 'Hyde Park High School',
      'subjectsOfInterest': ['Mathematics', 'Physics'],
    });
    expect(changed, 1); // the dashboard refreshes the new name

    // Back to the profile, showing the saved details
    expect(find.text('Your profile has been saved.'), findsOneWidget);
    expect(find.text('Save Changes'), findsNothing);
    expect(find.text('Lerato Pillay'), findsOneWidget);
    expect(find.text('Hyde Park High School'), findsOneWidget);
    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('Calculus 1'), findsNothing);
  });

  testWidgets('Save Changes needs a subject and does not send', (
    tester,
  ) async {
    var saves = 0;
    await _pump(
      tester,
      () async => _lerato,
      saveProfile: (changes) async {
        saves++;
        return StudentProfileSaved(profile: _lerato, message: 'Saved');
      },
    );

    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mathematics'));
    await tester.tap(find.text('Calculus 1'));
    await tester.pump();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(saves, 0);
    expect(find.text('Choose at least one subject.'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget); // still editing
  });

  testWidgets('a failed save keeps the changes on screen', (tester) async {
    await _pump(
      tester,
      () async => _lerato,
      saveProfile: (_) async =>
          throw const StudentProfileException('Your name cannot be empty.'),
    );

    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Physics'));
    await tester.pump();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Your name cannot be empty.'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
  });

  testWidgets('the back arrow asks before throwing changes away', (
    tester,
  ) async {
    var saves = 0;
    await _pump(
      tester,
      () async => _lerato,
      saveProfile: (_) async {
        saves++;
        return StudentProfileSaved(profile: _lerato, message: 'Saved');
      },
    );

    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Physics'));
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(saves, 0);
    expect(find.text('Save Changes'), findsNothing);
    expect(find.text('Physics'), findsNothing); // not added
    expect(find.text('Calculus 1'), findsOneWidget);
  });

  testWidgets('a subject list that fails to load can be retried', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      () async => _lerato,
      loadSubjects: () async {
        calls++;
        if (calls == 1) throw const StudentProfileException('offline');
        return ['Chemistry'];
      },
    );

    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();
    // The student's own subjects stay choosable
    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('Chemistry'), findsNothing);

    await tester.tap(find.text('Could not load subjects. Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Chemistry'), findsOneWidget);
  });

  testWidgets('the camera badge saves a new photo straight away', (
    tester,
  ) async {
    Map<String, Object?>? sent;
    var changed = 0;
    const url = 'https://res.cloudinary.com/demo/image/upload/new.png';
    await _pump(
      tester,
      () async => _lerato,
      choosePhoto: () async => url,
      saveProfile: (changes) async {
        sent = changes;
        return StudentProfileSaved(
          profile: _applied(_lerato, changes),
          message: 'Profile photo updated.',
        );
      },
      onChanged: () => changed++,
    );

    await tester.tap(find.byIcon(Icons.camera_alt_rounded));
    await tester.pump();
    await tester.pump();

    expect(sent, {'photo': url});
    expect(changed, 1);
    expect(find.text('Profile photo updated.'), findsOneWidget);
    // The new photo is shown (tests cannot download it, so no pixels)
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image && w.image is NetworkImage &&
            (w.image as NetworkImage).url == url,
      ),
      findsOneWidget,
    );
  });
}
