class ValidationResult {
  final bool isValid;
  final String? error;
  const ValidationResult({required this.isValid, this.error});
}

class Validator {

  // ── Name ──────────────────────────────────────────────
  static ValidationResult validateName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return const ValidationResult(
        isValid: false,
        error: 'Full name is required',
      );
    }
    if (name.trim().length < 2) {
      return const ValidationResult(
        isValid: false,
        error: 'Name must be at least 2 characters',
      );
    }
    if (name.trim().length > 100) {
      return const ValidationResult(
        isValid: false,
        error: 'Name must be less than 100 characters',
      );
    }
    return const ValidationResult(isValid: true);
  }

  // ── Email ─────────────────────────────────────────────
  static ValidationResult validateEmail(String? email) {
    if (email == null || email.trim().isEmpty) {
      return const ValidationResult(
        isValid: false,
        error: 'Email address is required',
      );
    }
    final emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$');
    if (!emailRegex.hasMatch(email.trim())) {
      return const ValidationResult(
        isValid: false,
        error: 'Please enter a valid email address',
      );
    }
    return const ValidationResult(isValid: true);
  }

  // ── Password ──────────────────────────────────────────
  static ValidationResult validatePassword(String? password) {
    if (password == null || password.isEmpty) {
      return const ValidationResult(
        isValid: false,
        error: 'Password is required',
      );
    }
    if (password.length < 8) {
      return const ValidationResult(
        isValid: false,
        error: 'Password must be at least 8 characters',
      );
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return const ValidationResult(
        isValid: false,
        error: 'Password must contain at least one uppercase letter',
      );
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      return const ValidationResult(
        isValid: false,
        error: 'Password must contain at least one number',
      );
    }
    return const ValidationResult(isValid: true);
  }

  // ── Phone ─────────────────────────────────────────────
  static ValidationResult validatePhone(String? phone) {
    if (phone == null || phone.trim().isEmpty) {
      return const ValidationResult(isValid: true); // optional field
    }
    final phoneRegex = RegExp(r'^\+?[\d\s\-]{8,15}$');
    if (!phoneRegex.hasMatch(phone.trim())) {
      return const ValidationResult(
        isValid: false,
        error: 'Please enter a valid phone number',
      );
    }
    return const ValidationResult(isValid: true);
  }

  // ── Bio ───────────────────────────────────────────────
  static ValidationResult validateBio(String? bio) {
    if (bio == null || bio.trim().isEmpty) {
      return const ValidationResult(
        isValid: false,
        error: 'Bio is required',
      );
    }
    if (bio.trim().length < 20) {
      return const ValidationResult(
        isValid: false,
        error: 'Bio must be at least 20 characters',
      );
    }
    if (bio.trim().length > 300) {
      return const ValidationResult(
        isValid: false,
        error: 'Bio must be less than 300 characters',
      );
    }
    return const ValidationResult(isValid: true);
  }

  // ── Hourly Rate ───────────────────────────────────────
  static ValidationResult validateHourlyRate(dynamic rate) {
    if (rate == null) {
      return const ValidationResult(
        isValid: false,
        error: 'Hourly rate is required',
      );
    }
    final rateNum = num.tryParse(rate.toString());
    if (rateNum == null || rateNum <= 0) {
      return const ValidationResult(
        isValid: false,
        error: 'Please enter a valid hourly rate',
      );
    }
    if (rateNum > 10000) {
      return const ValidationResult(
        isValid: false,
        error: 'Hourly rate seems too high — please check the amount',
      );
    }
    return const ValidationResult(isValid: true);
  }

  // ── Subjects ──────────────────────────────────────────
  static ValidationResult validateSubjects(List<dynamic>? subjects) {
    if (subjects == null || subjects.isEmpty) {
      return const ValidationResult(
        isValid: false,
        error: 'Please select at least one subject',
      );
    }
    if (subjects.length > 10) {
      return const ValidationResult(
        isValid: false,
        error: 'You can select a maximum of 10 subjects',
      );
    }
    return const ValidationResult(isValid: true);
  }

  // ── Availability ──────────────────────────────────────
  static ValidationResult validateAvailability(List<dynamic>? slots) {
    if (slots == null || slots.isEmpty) {
      return const ValidationResult(
        isValid: false,
        error: 'Please add at least one availability slot',
      );
    }

    final validDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final timeRegex = RegExp(r'^\d{2}:\d{2}$');

    for (final slot in slots) {
      final day = slot['day'] as String?;
      final start = slot['startTime'] as String?;
      final end = slot['endTime'] as String?;

      if (day == null || !validDays.contains(day)) {
        return ValidationResult(
          isValid: false,
          error: 'Invalid day: $day. Use Mon, Tue, Wed, Thu, Fri, Sat or Sun',
        );
      }
      if (start == null || !timeRegex.hasMatch(start)) {
        return const ValidationResult(
          isValid: false,
          error: 'Start time must be in HH:MM format (e.g. 09:00)',
        );
      }
      if (end == null || !timeRegex.hasMatch(end)) {
        return const ValidationResult(
          isValid: false,
          error: 'End time must be in HH:MM format (e.g. 17:00)',
        );
      }
      if (start.compareTo(end) >= 0) {
        return ValidationResult(
          isValid: false,
          error: 'Start time must be before end time for $day',
        );
      }
    }
    return const ValidationResult(isValid: true);
  }
}