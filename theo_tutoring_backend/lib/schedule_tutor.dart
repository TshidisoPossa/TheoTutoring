import 'package:mysql_client/mysql_client.dart';

// ---------------------------------------------------------------------------
// TUTOR SCHEDULE PAGE: BACKEND
// Tabs:  Upcoming (Confirmed sessions not finished yet)
//        New      (Pending booking requests from students)
//        Past     (Completed sessions, and Confirmed ones that have ended)
//        All      (every Confirmed or Completed session)
// Chips: All Dates / Today / Tomorrow / This Week
// Filter icon: one or more subjects.
// Booking statuses follow the project documentation, section 4.5.
// ---------------------------------------------------------------------------

/// The tab the tutor is looking at.
enum ScheduleTab { upcoming, newRequests, past, all }

/// The date chip under the tabs.
enum ScheduleDate { all, today, tomorrow, week }

/// What the app asked for, read from the query string.
class ScheduleQuery {
  /// Creates a query.
  const ScheduleQuery({
    this.tab = ScheduleTab.upcoming,
    this.date = ScheduleDate.all,
    this.subjectIds = const [],
  });

  /// Which tab.
  final ScheduleTab tab;

  /// Which date chip.
  final ScheduleDate date;

  /// Subjects picked in the filter (empty = every subject).
  final List<int> subjectIds;
}

const _tabNames = {
  'upcoming': ScheduleTab.upcoming,
  'new': ScheduleTab.newRequests,
  'past': ScheduleTab.past,
  'all': ScheduleTab.all,
};

const _dateNames = {
  'all': ScheduleDate.all,
  'today': ScheduleDate.today,
  'tomorrow': ScheduleDate.tomorrow,
  'week': ScheduleDate.week,
};

const _maxSubjectFilters = 20;

/// Reads ?tab=upcoming|new|past|all&date=all|today|tomorrow|week&subjectId=3,5
/// Missing values fall back to Upcoming / All Dates / every subject.
/// Throws a FormatException (turned into a 400) for anything else.
ScheduleQuery parseScheduleQuery(Map<String, String> params) {
  final tab = _tabNames[params['tab'] ?? 'upcoming'];
  if (tab == null) {
    throw const FormatException('tab must be upcoming, new, past or all.');
  }

  final date = _dateNames[params['date'] ?? 'all'];
  if (date == null) {
    throw const FormatException('date must be all, today, tomorrow or week.');
  }

  final ids = <int>{};
  final rawIds = params['subjectId']?.trim() ?? '';
  if (rawIds.isNotEmpty) {
    for (final part in rawIds.split(',')) {
      final id = int.tryParse(part.trim());
      if (id == null || id <= 0) {
        throw const FormatException(
          'subjectId must be whole numbers, e.g. subjectId=3,5',
        );
      }
      ids.add(id);
    }
  }
  if (ids.length > _maxSubjectFilters) {
    throw const FormatException(
      'You can filter by up to $_maxSubjectFilters subjects.',
    );
  }

  return ScheduleQuery(tab: tab, date: date, subjectIds: ids.toList());
}

// ── Fixed SQL pieces (no user text ever goes into the SQL) ──────────────────
const _notEnded =
    '(b.`Date` > CURDATE() OR (b.`Date` = CURDATE() AND b.EndTime > CURTIME()))';
const _ended =
    '(b.`Date` < CURDATE() OR (b.`Date` = CURDATE() AND b.EndTime <= CURTIME()))';
// a request is only "new" while its session has not started yet
const _notStarted =
    '(b.`Date` > CURDATE() OR (b.`Date` = CURDATE() AND b.StartTime > CURTIME()))';

const _tabCondition = {
  ScheduleTab.upcoming: "b.Status = 'Confirmed' AND $_notEnded",
  ScheduleTab.newRequests: "b.Status = 'Pending' AND $_notStarted",
  ScheduleTab.past:
      "(b.Status = 'Completed' OR (b.Status = 'Confirmed' AND $_ended))",
  ScheduleTab.all: "b.Status IN ('Confirmed', 'Completed')",
};

const _tabOrder = {
  ScheduleTab.upcoming: 'b.`Date` ASC, b.StartTime ASC', // soonest first
  ScheduleTab.newRequests: 'b.`Date` ASC, b.StartTime ASC', // soonest first
  ScheduleTab.past: 'b.`Date` DESC, b.StartTime DESC', // most recent first
  ScheduleTab.all: 'b.`Date` DESC, b.StartTime DESC', // most recent first
};

const _dateCondition = {
  ScheduleDate.all: '',
  ScheduleDate.today: ' AND b.`Date` = CURDATE()',
  ScheduleDate.tomorrow: ' AND b.`Date` = CURDATE() + INTERVAL 1 DAY',
  // mode 3 = weeks start on Monday
  ScheduleDate.week: ' AND YEARWEEK(b.`Date`, 3) = YEARWEEK(CURDATE(), 3)',
};

/// The numbers on the tabs, e.g. Upcoming (5), New (3).
/// They count everything on each tab, ignoring the date chip and filter.
Future<Map<String, int>> getScheduleCounts(
  MySQLConnection conn,
  int tutorId,
) async {
  final result = await conn.execute(
    'SELECT '
    'COALESCE(SUM(${_tabCondition[ScheduleTab.upcoming]}), 0) AS Upcoming, '
    'COALESCE(SUM(${_tabCondition[ScheduleTab.newRequests]}), 0) AS NewCount, '
    'COALESCE(SUM(${_tabCondition[ScheduleTab.past]}), 0) AS Past, '
    'COALESCE(SUM(${_tabCondition[ScheduleTab.all]}), 0) AS AllCount '
    'FROM Booking b WHERE b.TutorID = :tid',
    {'tid': tutorId},
  );
  final c = result.rows.first.assoc();
  int n(String key) => int.tryParse(c[key] ?? '') ?? 0;
  return {
    'upcoming': n('Upcoming'),
    'new': n('NewCount'),
    'past': n('Past'),
    'all': n('AllCount'),
  };
}

/// The session cards for one tab, oldest/newest first depending on the tab.
Future<List<Map<String, dynamic>>> getScheduleSessions(
  MySQLConnection conn,
  int tutorId,
  ScheduleQuery query,
) async {
  final params = <String, dynamic>{'tid': tutorId};

  var subjectCondition = '';
  if (query.subjectIds.isNotEmpty) {
    final placeholders = <String>[];
    for (var i = 0; i < query.subjectIds.length; i++) {
      placeholders.add(':s$i');
      params['s$i'] = query.subjectIds[i];
    }
    subjectCondition = ' AND b.SubjectID IN (${placeholders.join(', ')})';
  }

  final result = await conn.execute(
    'SELECT b.Booking_id, b.Status, b.`Date`, b.StartTime, b.EndTime, '
    'b.Note, b.Link, b.SubjectID, sj.subjectName AS Subject, '
    'TIME_TO_SEC(TIMEDIFF(b.EndTime, b.StartTime)) DIV 60 AS DurationMinutes, '
    // 45 -> "Starts in 45m"
    'TIMESTAMPDIFF(MINUTE, NOW(), TIMESTAMP(b.`Date`, b.StartTime)) '
    'AS StartsInMinutes, '
    // 0 -> "Today", 1 -> "Tomorrow"
    'DATEDIFF(b.`Date`, CURDATE()) AS DaysFromToday, '
    // New tab: "Requested 2h ago"
    'TIMESTAMPDIFF(MINUTE, b.Created_at, NOW()) AS RequestedMinutesAgo, '
    // Upcoming tab: "Confirmed 25m ago" = when the student paid
    'TIMESTAMPDIFF(MINUTE, p.Paid_At, NOW()) AS ConfirmedMinutesAgo, '
    'u.Name AS StudentName, u.ProfilePhoto AS StudentPhoto '
    'FROM Booking b '
    'JOIN Subjects sj ON sj.subjectId = b.SubjectID ' // booking -> subject name
    'JOIN StudentProfile s ON s.StudentID = b.StudentID ' // -> student profile
    'JOIN `User` u ON u.UserId = s.UserID ' // student profile -> name + photo
    'LEFT JOIN Payment p ON p.BookingId = b.Booking_id '
    "AND p.PaymentStatus = 'Successful' " // the payment that confirmed it
    'WHERE b.TutorID = :tid AND ${_tabCondition[query.tab]}'
    '${_dateCondition[query.date]}$subjectCondition '
    'ORDER BY ${_tabOrder[query.tab]}',
    params,
  );

  return [for (final row in result.rows) _sessionCard(row.assoc())];
}

// One database row -> one session card.
// MySQL sends numbers back as text, so they are turned into ints here.
Map<String, dynamic> _sessionCard(Map<String, String?> r) {
  int? number(String? v) => v == null ? null : int.tryParse(v);
  String? clock(String? v) => v?.substring(0, 5); // "15:00:00" -> "15:00"

  return {
    'bookingId': number(r['Booking_id']),
    'status': r['Status'], // Confirmed / Pending / Completed
    'date': r['Date']?.substring(0, 10), // "2026-10-24"
    'daysFromToday': number(r['DaysFromToday']), // 0 = today
    'startTime': clock(r['StartTime']), // "15:00"
    'endTime': clock(r['EndTime']), // "16:00"
    'durationMinutes': number(r['DurationMinutes']), // 60 -> "(1 hr)"
    'subjectId': number(r['SubjectID']),
    'subject': r['Subject'], // "Calculus"
    'note': r['Note'], // the student's message (may be null)
    'link': r['Link'], // where the session takes place (may be null)
    'startsInMinutes': number(r['StartsInMinutes']),
    'requestedMinutesAgo': number(r['RequestedMinutesAgo']),
    'confirmedMinutesAgo': number(r['ConfirmedMinutesAgo']),
    'student': {
      'name': r['StudentName'],
      'profilePhotoUrl': r['StudentPhoto'], // null if none uploaded
    },
  };
}

/// Groups session cards under day headings ("Today, 30 Sep - 2 sessions"),
/// keeping the order they arrived in.
List<Map<String, dynamic>> groupSessionsByDay(
  List<Map<String, dynamic>> sessions,
) {
  final days = <Map<String, dynamic>>[];
  for (final session in sessions) {
    final date = session['date'];
    if (days.isEmpty || days.last['date'] != date) {
      days.add({
        'date': date, // "2026-09-30"
        'daysFromToday': session['daysFromToday'], // 0 -> "Today"
        'count': 0, // "2 sessions"
        'sessions': <Map<String, dynamic>>[],
      });
    }
    (days.last['sessions'] as List<Map<String, dynamic>>).add(session);
    days.last['count'] = (days.last['count'] as int) + 1;
  }
  return days;
}
