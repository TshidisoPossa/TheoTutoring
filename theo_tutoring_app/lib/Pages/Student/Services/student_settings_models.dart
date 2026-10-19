// Models for the Student Settings page.
// Mirrors the JSON shapes the Java backend returns / accepts.

class StudentSettings {
  final String email;
  final String phone;
  final NotificationPreferences notifications;

  const StudentSettings({
    required this.email,
    required this.phone,
    required this.notifications,
  });

  factory StudentSettings.fromJson(Map<String, dynamic> json) {
    return StudentSettings(
      email: json['email'] as String,
      phone: json['phone'] as String,
      notifications: NotificationPreferences.fromJson(
        json['notifications'] as Map<String, dynamic>,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'phone': phone,
        'notifications': notifications.toJson(),
      };
}

class NotificationPreferences {
  final bool sessionReminders;
  final bool bookingConfirmations;
  final bool directMessages;

  const NotificationPreferences({
    required this.sessionReminders,
    required this.bookingConfirmations,
    required this.directMessages,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      sessionReminders: json['sessionReminders'] as bool? ?? true,
      bookingConfirmations: json['bookingConfirmations'] as bool? ?? true,
      directMessages: json['directMessages'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'sessionReminders': sessionReminders,
        'bookingConfirmations': bookingConfirmations,
        'directMessages': directMessages,
      };
}

class PaymentMethod {
  final String id;
  final String cardBrand;   // e.g. "Visa"
  final String lastFour;    // e.g. "4321"
  final String expiry;      // e.g. "08/27"

  const PaymentMethod({
    required this.id,
    required this.cardBrand,
    required this.lastFour,
    required this.expiry,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'] as String,
      cardBrand: json['cardBrand'] as String,
      lastFour: json['lastFour'] as String,
      expiry: json['expiry'] as String,
    );
  }
}
