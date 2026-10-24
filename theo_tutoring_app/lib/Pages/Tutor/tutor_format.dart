// Turns the raw values the tutor routes send back (ISO dates, minute
// counts, session links) into the short labels the tutor pages show.

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

DateTime? _parse(String? iso) => iso == null ? null : DateTime.tryParse(iso);

/// "2026-10-24" -> "Sat, 24 Oct 2026"
String formatLongDate(String? iso) {
  final d = _parse(iso);
  if (d == null) return iso ?? '';
  return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// Day heading on the Schedule page: "Today, 24 Oct", "Tomorrow, 25 Oct",
/// "Yesterday, 23 Oct" or "Mon, 27 Oct".
String dayHeading(String? iso, int? daysFromToday) {
  final d = _parse(iso);
  if (d == null) return iso ?? '';
  final short = '${d.day} ${_months[d.month - 1]}';
  return switch (daysFromToday) {
    0 => 'Today, $short',
    1 => 'Tomorrow, $short',
    -1 => 'Yesterday, $short',
    _ => '${_weekdays[d.weekday - 1]}, $short',
  };
}

/// 25 -> "25m ago", 120 -> "2h ago", 3000 -> "2d ago"
String timeAgo(int minutes) {
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '${minutes}m ago';
  if (minutes < 60 * 24) return '${minutes ~/ 60}h ago';
  return '${minutes ~/ (60 * 24)}d ago';
}

/// "15:00" or "15:00:00" -> "3:00 PM", "00:30" -> "12:30 AM"
String clock12(String? time) {
  final parts = (time ?? '').split(':');
  final h = parts.isEmpty ? null : int.tryParse(parts[0]);
  final m = parts.length < 2 ? null : int.tryParse(parts[1]);
  if (h == null || m == null) return time ?? '';
  final hour = h % 12 == 0 ? 12 : h % 12;
  return '$hour:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

/// Where a session happens, from [platformOf]: "Zoom Meeting", "Google
/// Meet", "Microsoft Teams", "Online meeting" or "No meeting link yet".
String meetingLabel(String platform) => switch (platform) {
      'zoom' => 'Zoom Meeting',
      'meet' => 'Google Meet',
      'teams' => 'Microsoft Teams',
      'online' => 'Online meeting',
      _ => 'No meeting link yet',
    };

/// When a notification arrived: "Just now", "2 min ago", "3 hrs ago",
/// "Yesterday · 4:20 PM" or "Mon 20 Oct · 4:20 PM". [section] and
/// [minutesAgo] come from the backend; [createdAt] is its ISO time.
String notificationTime(String section, int minutesAgo, String? createdAt) {
  if (section == 'today') {
    if (minutesAgo < 1) return 'Just now';
    if (minutesAgo < 60) return '$minutesAgo min ago';
    final hours = minutesAgo ~/ 60;
    return '$hours ${hours == 1 ? 'hr' : 'hrs'} ago';
  }
  final d = _parse(createdAt)?.toLocal();
  if (d == null) return section == 'yesterday' ? 'Yesterday' : '';
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final clock =
      '$hour:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  if (section == 'yesterday') return 'Yesterday · $clock';
  return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} · $clock';
}

/// 45 -> "45 min", 60 -> "1 hr", 90 -> "1.5 hrs"
String durationLabel(int? minutes) {
  if (minutes == null || minutes <= 0) return '';
  if (minutes < 60) return '$minutes min';
  final hours = minutes / 60;
  return '${_hours(hours)} ${hours == 1 ? 'hr' : 'hrs'}';
}

/// Badge on a dashboard card: "Now", "In 45 min", "In 2.5 hrs"
String startsInLabel(int minutes) {
  if (minutes <= 0) return 'Now';
  if (minutes < 60) return 'In $minutes min';
  final hours = minutes / 60;
  return 'In ${_hours(hours)} ${hours == 1 ? 'hr' : 'hrs'}';
}

// 2.0 -> "2", 2.5 -> "2.5"
String _hours(double h) =>
    h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1);

/// "Thabo Mokoena" -> "TM"
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

/// Works out where the session takes place from its link:
/// 'zoom', 'meet', 'teams', 'online' (another link) or 'none' (no link yet).
String platformOf(String? link) {
  final l = (link ?? '').toLowerCase();
  if (l.isEmpty) return 'none';
  if (l.contains('zoom.')) return 'zoom';
  if (l.contains('meet.google.')) return 'meet';
  if (l.contains('teams.')) return 'teams';
  return 'online';
}
