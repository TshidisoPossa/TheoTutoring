// Checks that the tutor pages read the JSON the /TutorLandingpage routes
// send back. The sample bodies copy the shapes built in the backend
// (LandingPageScreen.dart, schedule_tutor.dart, booking_tutor.dart).

import 'package:flutter_test/flutter_test.dart';

import 'package:theo_tutoring_app/Pages/Tutor/tutor_booking_detail.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_dashboard.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_format.dart';
import 'package:theo_tutoring_app/Pages/Tutor/tutor_schedule.dart';

void main() {
  group('dashboard', () {
    test('reads an active tutor', () {
      final d = DashboardData.fromJson({
        'tutor': {'tutorId': 4, 'name': 'Thabo Mokoena', 'profilePhotoUrl': null},
        'accountStatus': 'Active',
        'activeStudents': 3,
        'upcomingToday': 1,
        'averageRating': 4.5,
        'todaysSchedule': [
          {
            'Booking_id': '12',
            'SubjectID': '3',
            'Subject': 'Calculus',
            'StartTime': '15:00:00',
            'EndTime': '16:00:00',
            'Note': 'Limits',
            'Link': 'https://zoom.us/j/123',
            'StudentName': 'Lerato Dube',
            'StudentPhoto': null,
            'MinutesUntilStart': '45',
          },
        ],
        'latestReviews': [],
      });
      expect(d.isPending, isFalse);
      expect(d.tutorInitials, 'TM');
      expect(d.activeStudents, 3);
      final s = d.todaySchedule.single;
      expect(s.bookingId, 12);
      expect(s.timeRange, '15:00 – 16:00');
      expect(s.subject, 'Calculus');
      expect(s.studentName, 'Lerato Dube');
      expect(s.platform, 'zoom');
      expect(s.startsIn, 'In 45 min');
    });

    test('reads a pending tutor', () {
      final d = DashboardData.fromJson({
        'tutor': {'tutorId': 4, 'name': 'Thabo', 'profilePhotoUrl': null},
        'accountStatus': 'Pending',
        'application': {'status': 'Pending', 'adminFeedback': null},
      });
      expect(d.isPending, isTrue);
      expect(d.application?['status'], 'Pending');
      expect(d.todaySchedule, isEmpty);
    });
  });

  test('schedule day and session cards', () {
    final day = ScheduleDay.fromJson({
      'date': '2026-10-24',
      'daysFromToday': 0,
      'count': 1,
      'sessions': [
        {
          'bookingId': 12,
          'status': 'Confirmed',
          'date': '2026-10-24',
          'daysFromToday': 0,
          'startTime': '15:00',
          'endTime': '16:30',
          'durationMinutes': 90,
          'subjectId': 3,
          'subject': 'Calculus',
          'note': null,
          'link': null,
          'startsInMinutes': 45,
          'requestedMinutesAgo': 600,
          'confirmedMinutesAgo': 25,
          'student': {'name': 'Lerato Dube', 'profilePhotoUrl': null},
        },
      ],
    });
    expect(day.label, 'Today, 24 Oct');
    final s = day.sessions.single;
    expect(s.studentName, 'Lerato Dube');
    expect(s.duration, '1.5 hrs');
    expect(s.statusAgo, 'Confirmed 25m ago');
    expect(s.platform, 'none');
  });

  test('booking details with a recurring series', () {
    final b = BookingDetail.fromJson({
      'tutor': {'tutorId': 4, 'name': 'Thabo Mokoena', 'profilePhotoUrl': null},
      'booking': {
        'bookingId': 12,
        'reference': 'REQ-12',
        'status': 'Confirmed',
        'subjectId': 3,
        'subject': 'Calculus',
        'date': '2026-10-27',
        'startTime': '16:00',
        'endTime': '17:00',
        'durationMinutes': 60,
        'note': 'Limits please',
        'link': null,
        'receivedMinutesAgo': 180,
        'hasStarted': false,
        'canPostpone': true,
      },
      'student': {
        'name': 'Lerato Dube',
        'profilePhotoUrl': null,
        'year': '2nd Year',
        'course': 'BSc Computer Science',
        'verified': true,
      },
      'recurring': {
        'frequency': 'Weekly',
        'weekday': 'Tuesday',
        'startTime': '16:00',
        'endTime': '17:00',
        'sessions': [
          {'bookingId': 12, 'date': '2026-10-27', 'status': 'Confirmed'},
          {'bookingId': 13, 'date': '2026-11-03', 'status': 'Confirmed'},
        ],
        'totalSessions': 2,
        'totalMinutes': 120,
      },
    });
    expect(b.requestId, 'REQ-12');
    expect(b.receivedAgo, '3h ago');
    expect(b.date, 'Tue, 27 Oct 2026');
    expect(b.durationLabel, '1 hr');
    expect(b.canPostpone, isTrue);
    expect(b.studentVerified, isTrue);
    expect(b.studentMajor, 'BSc Computer Science');
    expect(b.isRecurring, isTrue);
    expect(b.recurringPattern, 'Every Tuesday (Weekly)');
    expect(b.nextSessions, ['Tue, 27 Oct 2026', 'Tue, 3 Nov 2026']);
    expect(b.totalHours, '2 hrs');
  });

  test('one-off booking has no recurring card', () {
    final b = BookingDetail.fromJson({
      'booking': {'bookingId': 5, 'status': 'Pending', 'canPostpone': false},
      'student': {'name': 'Sipho'},
      'recurring': null,
    });
    expect(b.isRecurring, isFalse);
    expect(b.canPostpone, isFalse);
  });

  test('labels', () {
    expect(startsInLabel(0), 'Now');
    expect(startsInLabel(150), 'In 2.5 hrs');
    expect(timeAgo(3000), '2d ago');
    expect(dayHeading('2026-10-25', 1), 'Tomorrow, 25 Oct');
    expect(platformOf('https://meet.google.com/abc'), 'meet');
  });
}
