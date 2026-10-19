// Models for the Tutor Settings page.
// Mirrors the JSON shapes the Java backend returns / accepts.

class TutorSettings {
  final String email;
  final String phone;
  final NotificationPreferences notifications;

  const TutorSettings({
    required this.email,
    required this.phone,
    required this.notifications,
  });

  factory TutorSettings.fromJson(Map<String, dynamic> json) {
    return TutorSettings(
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
  final bool newBookingAlerts;
  final bool directMessages;
  final bool newReviews;

  const NotificationPreferences({
    required this.sessionReminders,
    required this.newBookingAlerts,
    required this.directMessages,
    required this.newReviews,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      sessionReminders: json['sessionReminders'] as bool? ?? true,
      newBookingAlerts: json['newBookingAlerts'] as bool? ?? true,
      directMessages: json['directMessages'] as bool? ?? true,
      newReviews: json['newReviews'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'sessionReminders': sessionReminders,
        'newBookingAlerts': newBookingAlerts,
        'directMessages': directMessages,
        'newReviews': newReviews,
      };
}

class PayoutAccount {
  final String bankName;   // e.g. "FNB"
  final String lastFour;   // e.g. "5678"

  const PayoutAccount({
    required this.bankName,
    required this.lastFour,
  });

  factory PayoutAccount.fromJson(Map<String, dynamic> json) {
    return PayoutAccount(
      bankName: json['bankName'] as String,
      lastFour: json['lastFour'] as String,
    );
  }
}

class PayoutRecord {
  final String id;
  final double amount;
  final String currency;   // e.g. "ZAR"
  final String date;       // ISO 8601 date string
  final String status;     // e.g. "paid", "pending"

  const PayoutRecord({
    required this.id,
    required this.amount,
    required this.currency,
    required this.date,
    required this.status,
  });

  factory PayoutRecord.fromJson(Map<String, dynamic> json) {
    return PayoutRecord(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'ZAR',
      date: json['date'] as String,
      status: json['status'] as String,
    );
  }
}
