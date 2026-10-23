import 'package:flutter_test/flutter_test.dart';
import 'package:theo_tutoring_app/Pages/Admin/Services/settings_services.dart';

void main() {
  test(
    'password update reauthenticates before updating Firebase password',
    () async {
      final events = <String>[];

      await reauthenticateAndUpdatePassword(
        currentPassword: 'old-password',
        newPassword: 'new-password',
        reauthenticate: (password) async => events.add('reauth:$password'),
        updatePassword: (password) async => events.add('update:$password'),
      );

      expect(events, ['reauth:old-password', 'update:new-password']);
    },
  );

  test('failed reauthentication prevents the password update', () async {
    var updated = false;

    await expectLater(
      reauthenticateAndUpdatePassword(
        currentPassword: 'wrong-password',
        newPassword: 'new-password',
        reauthenticate: (_) async => throw StateError('recent login required'),
        updatePassword: (_) async => updated = true,
      ),
      throwsStateError,
    );

    expect(updated, isFalse);
  });
}
