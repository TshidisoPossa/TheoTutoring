-- Sample data for trying the tutor Dashboard, Schedule and Booking details
-- pages on a LOCAL database. Do not run it on a shared or live database.
--
-- Everything belongs to TutorID 1 ("Test Tutor") and every booking's Note
-- starts with 'Sample booking - ', so tutor_schedule_remove.sql can delete
-- exactly these rows. Dates are relative to the day you run it, and running
-- it again replaces the earlier sample rows instead of adding more.
--
-- What it adds:
--   Upcoming tab : 1 session today, 1 in 4 days, and a weekly series of 3
--                  (tomorrow, +8 and +15 days) for the Recurring Booking card
--   New tab      : 2 Pending requests
--   Past tab     : 2 Completed sessions (both reviewed) and 1 that ended
--                  yesterday
--   Dashboard    : 3 active students, 1 session today, 2 reviews
--   Payments     : one Successful card payment per Confirmed / Completed
--                  session, at the platform rate
USE theotutoring;

SET @tutor      := 1;
SET @maths      := (SELECT subjectId FROM Subjects WHERE subjectName = 'Mathematics');
SET @physics    := (SELECT subjectId FROM Subjects WHERE subjectName = 'Physics');
SET @accounting := (SELECT subjectId FROM Subjects WHERE subjectName = 'Accounting');
SET @dumisani   := 12; -- StudentProfile.StudentID
SET @jafta      := 11;
SET @tshidiso   := 9;
SET @rate := COALESCE(
    (SELECT TutoringRate FROM PlatformSettings WHERE SettingsID = 1), 250.00);

-- "Today" session: two hours from now, kept inside 08:00-20:00
SET @soon := GREATEST(8, LEAST(HOUR(NOW()) + 2, 19));

START TRANSACTION;

-- ── Remove an earlier run (same steps as tutor_schedule_remove.sql) ─────────
DELETE FROM Reviews WHERE BookingID IN (
    SELECT Booking_id FROM Booking
    WHERE TutorID = @tutor AND Note LIKE 'Sample booking - %');
DELETE FROM Payment WHERE BookingId IN (
    SELECT Booking_id FROM Booking
    WHERE TutorID = @tutor AND Note LIKE 'Sample booking - %');
DELETE FROM Booking WHERE TutorID = @tutor AND Note LIKE 'Sample booking - %';

-- ── The tutor teaches these subjects and is free Mon-Sat 08:00-20:00 ───────
INSERT IGNORE INTO TutorSubjects (TutorID, SubjectID)
VALUES (@tutor, @maths), (@tutor, @physics), (@tutor, @accounting);

INSERT INTO TutAvailability (TutorID, Day, StartTime, end_Time)
SELECT @tutor, d.Day, '08:00:00', '20:00:00'
FROM (SELECT 'Monday' AS Day UNION ALL SELECT 'Tuesday'
      UNION ALL SELECT 'Wednesday' UNION ALL SELECT 'Thursday'
      UNION ALL SELECT 'Friday' UNION ALL SELECT 'Saturday') d
WHERE NOT EXISTS (SELECT 1 FROM TutAvailability WHERE TutorID = @tutor);

-- ── Upcoming (Confirmed = paid) ─────────────────────────────────────────────
-- Today, starting soon
INSERT INTO Booking (StudentID, TutorID, SubjectID, Subject, `Date`, StartTime,
                     EndTime, Note, Status, Link, Created_at)
VALUES (@dumisani, @tutor, @maths, 'Mathematics', CURDATE(),
        MAKETIME(@soon, 0, 0), MAKETIME(@soon + 1, 0, 0),
        'Sample booking - Limits and continuity before Friday''s test.',
        'Confirmed', 'https://zoom.us/j/1234567890', NOW() - INTERVAL 2 DAY);
SET @b_today := LAST_INSERT_ID();
INSERT INTO Payment (BookingId, PaymentMethod, PaymentStatus, Paid_At, Amount)
VALUES (@b_today, 'Card', 'Successful', NOW() - INTERVAL 25 MINUTE, @rate);

-- Weekly series: tomorrow, +8 and +15 days, same student, subject and time
INSERT INTO Booking (StudentID, TutorID, SubjectID, Subject, `Date`, StartTime,
                     EndTime, Note, Status, Link, Created_at)
VALUES (@jafta, @tutor, @physics, 'Physics', CURDATE() + INTERVAL 1 DAY,
        '10:00:00', '11:00:00',
        'Sample booking - Weekly help with mechanics: forces and motion.',
        'Confirmed', 'https://meet.google.com/abc-defg-hij',
        NOW() - INTERVAL 3 DAY);
SET @b_series1 := LAST_INSERT_ID();
INSERT INTO Booking (StudentID, TutorID, SubjectID, Subject, `Date`, StartTime,
                     EndTime, Note, Status, Link, Created_at)
VALUES (@jafta, @tutor, @physics, 'Physics', CURDATE() + INTERVAL 8 DAY,
        '10:00:00', '11:00:00',
        'Sample booking - Weekly help with mechanics: forces and motion.',
        'Confirmed', 'https://meet.google.com/abc-defg-hij',
        NOW() - INTERVAL 3 DAY);
SET @b_series2 := LAST_INSERT_ID();
INSERT INTO Booking (StudentID, TutorID, SubjectID, Subject, `Date`, StartTime,
                     EndTime, Note, Status, Link, Created_at)
VALUES (@jafta, @tutor, @physics, 'Physics', CURDATE() + INTERVAL 15 DAY,
        '10:00:00', '11:00:00',
        'Sample booking - Weekly help with mechanics: forces and motion.',
        'Confirmed', 'https://meet.google.com/abc-defg-hij',
        NOW() - INTERVAL 3 DAY);
SET @b_series3 := LAST_INSERT_ID();
INSERT INTO Payment (BookingId, PaymentMethod, PaymentStatus, Paid_At, Amount)
VALUES (@b_series1, 'Card', 'Successful', NOW() - INTERVAL 1 DAY, @rate),
       (@b_series2, 'Card', 'Successful', NOW() - INTERVAL 1 DAY, @rate),
       (@b_series3, 'Card', 'Successful', NOW() - INTERVAL 1 DAY, @rate);

-- In 4 days, 90 minutes, no session link yet
INSERT INTO Booking (StudentID, TutorID, SubjectID, Subject, `Date`, StartTime,
                     EndTime, Note, Status, Link, Created_at)
VALUES (@tshidiso, @tutor, @accounting, 'Accounting', CURDATE() + INTERVAL 4 DAY,
        '14:00:00', '15:30:00',
        'Sample booking - Preparing financial statements for the exam.',
        'Confirmed', NULL, NOW() - INTERVAL 1 DAY);
SET @b_later := LAST_INSERT_ID();
INSERT INTO Payment (BookingId, PaymentMethod, PaymentStatus, Paid_At, Amount)
VALUES (@b_later, 'Card', 'Successful', NOW() - INTERVAL 5 HOUR, @rate);

-- ── New (Pending requests, not paid) ───────────────────────────────────────
INSERT INTO Booking (StudentID, TutorID, SubjectID, Subject, `Date`, StartTime,
                     EndTime, Note, Status, Link, Created_at)
VALUES (@dumisani, @tutor, @physics, 'Physics', CURDATE() + INTERVAL 2 DAY,
        '15:00:00', '16:00:00',
        'Sample booking - Can we go through circuits and Ohm''s law?',
        'Pending', NULL, NOW() - INTERVAL 2 HOUR),
       (@tshidiso, @tutor, @maths, 'Mathematics', CURDATE() + INTERVAL 5 DAY,
        '17:00:00', '18:00:00',
        'Sample booking - I need help with integration by parts.',
        'Pending', NULL, NOW() - INTERVAL 30 MINUTE);

-- ── Past ────────────────────────────────────────────────────────────────────
INSERT INTO Booking (StudentID, TutorID, SubjectID, Subject, `Date`, StartTime,
                     EndTime, Note, Status, Link, Created_at)
VALUES (@jafta, @tutor, @maths, 'Mathematics', CURDATE() - INTERVAL 3 DAY,
        '09:00:00', '10:00:00',
        'Sample booking - Derivatives revision.',
        'Completed', 'https://zoom.us/j/1234567890', NOW() - INTERVAL 7 DAY);
SET @b_done1 := LAST_INSERT_ID();
INSERT INTO Booking (StudentID, TutorID, SubjectID, Subject, `Date`, StartTime,
                     EndTime, Note, Status, Link, Created_at)
VALUES (@dumisani, @tutor, @accounting, 'Accounting', CURDATE() - INTERVAL 6 DAY,
        '13:00:00', '14:00:00',
        'Sample booking - Cash flow statements.',
        'Completed', NULL, NOW() - INTERVAL 10 DAY);
SET @b_done2 := LAST_INSERT_ID();
-- Confirmed but already over: shows on the Past tab too
INSERT INTO Booking (StudentID, TutorID, SubjectID, Subject, `Date`, StartTime,
                     EndTime, Note, Status, Link, Created_at)
VALUES (@tshidiso, @tutor, @physics, 'Physics', CURDATE() - INTERVAL 1 DAY,
        '11:00:00', '12:00:00',
        'Sample booking - Waves and sound.',
        'Confirmed', 'https://meet.google.com/abc-defg-hij',
        NOW() - INTERVAL 4 DAY);
SET @b_ended := LAST_INSERT_ID();
INSERT INTO Payment (BookingId, PaymentMethod, PaymentStatus, Paid_At, Amount)
VALUES (@b_done1, 'Card', 'Successful', NOW() - INTERVAL 6 DAY, @rate),
       (@b_done2, 'Card', 'Successful', NOW() - INTERVAL 9 DAY, @rate),
       (@b_ended, 'Card', 'Successful', NOW() - INTERVAL 3 DAY, @rate);

-- Reviews for the two completed sessions
INSERT INTO Reviews (studentId, TutorId, Rating, comment, Created_At, BookingID)
VALUES (@jafta, @tutor, 5,
        'Explained derivatives really clearly. My marks went up!',
        NOW() - INTERVAL 2 DAY, @b_done1),
       (@dumisani, @tutor, 4,
        'Very helpful session, I finally understand cash flow statements.',
        NOW() - INTERVAL 5 DAY, @b_done2);

UPDATE TutorProfile
SET AveRate = COALESCE(
    (SELECT ROUND(AVG(Rating), 2) FROM Reviews WHERE TutorId = @tutor), 0)
WHERE TutorID = @tutor;

COMMIT;

-- What was added
SELECT Booking_id, `Date`, StartTime, EndTime, Status, Subject
FROM Booking
WHERE TutorID = @tutor AND Note LIKE 'Sample booking - %'
ORDER BY `Date`, StartTime;
