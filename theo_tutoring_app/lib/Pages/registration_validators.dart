// Field validators shared by the student and tutor registration forms so both
// sides apply the same rules and show the same messages.

final registrationEmailPattern = RegExp(
  r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$",
);
final registrationPhonePattern = RegExp(r'^\+?[\d\s-]{8,15}$');

String? validateRegistrationName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'Please enter your full name.';
  if (name.length < 2 || name.length > 100) {
    return 'Name must be between 2 and 100 characters.';
  }
  return null;
}

String? validateRegistrationEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Please enter your email address.';
  if (email.length > 150 || !registrationEmailPattern.hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? validateRegistrationPassword(String? value) {
  if (value == null || value.length < 8) {
    return 'Password must be at least 8 characters.';
  }
  return null;
}

String? validateRegistrationPasswordConfirmation(
  String? value,
  String password,
) {
  if (value == null || value.isEmpty) return 'Please confirm your password.';
  if (value != password) return 'Passwords do not match.';
  return null;
}

String? validateRegistrationPhone(String? value) {
  final phone = value?.trim() ?? '';
  if (phone.isEmpty) return 'Please enter your phone number.';
  if (!registrationPhonePattern.hasMatch(phone) ||
      RegExp(r'\d').allMatches(phone).length < 8) {
    return 'Enter a valid phone number with 8–15 digits.';
  }
  return null;
}
