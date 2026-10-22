-- Removes the sample data added by tutor_schedule_seed.sql.
-- It only touches TutorID 1 ("Test Tutor") and finds the sample bookings by
-- their Note, which always starts with 'Sample booking - '.
--
-- Note: it also removes Test Tutor's Mon-Sat 08:00-20:00 availability and the
-- Mathematics, Physics and Accounting subjects that the seed added.
USE theotutoring;

SET @tutor := 1;

START TRANSACTION;

-- Rows that point at the sample bookings go first (foreign keys)
DELETE FROM Reviews WHERE BookingID IN (
    SELECT Booking_id FROM Booking
    WHERE TutorID = @tutor AND Note LIKE 'Sample booking - %');
DELETE FROM Payment WHERE BookingId IN (
    SELECT Booking_id FROM Booking
    WHERE TutorID = @tutor AND Note LIKE 'Sample booking - %');
DELETE FROM BookingReschedule WHERE BookingID IN (
    SELECT Booking_id FROM Booking
    WHERE TutorID = @tutor AND Note LIKE 'Sample booking - %');
DELETE FROM BookingSlotHold WHERE BookingID IN (
    SELECT Booking_id FROM Booking
    WHERE TutorID = @tutor AND Note LIKE 'Sample booking - %');
DELETE FROM Refund WHERE BookingID IN (
    SELECT Booking_id FROM Booking
    WHERE TutorID = @tutor AND Note LIKE 'Sample booking - %');
DELETE FROM Payout WHERE BookingID IN (
    SELECT Booking_id FROM Booking
    WHERE TutorID = @tutor AND Note LIKE 'Sample booking - %');
DELETE FROM Messaging WHERE BookingID IN (
    SELECT Booking_id FROM Booking
    WHERE TutorID = @tutor AND Note LIKE 'Sample booking - %');

DELETE FROM Booking WHERE TutorID = @tutor AND Note LIKE 'Sample booking - %';

-- The availability and subjects the seed gave the tutor
DELETE FROM TutAvailability
WHERE TutorID = @tutor AND StartTime = '08:00:00' AND end_Time = '20:00:00';
DELETE FROM TutorSubjects
WHERE TutorID = @tutor AND SubjectID IN (
    SELECT subjectId FROM Subjects
    WHERE subjectName IN ('Mathematics', 'Physics', 'Accounting'));

-- Average rating from whatever reviews are left (0.00 when none)
UPDATE TutorProfile
SET AveRate = COALESCE(
    (SELECT ROUND(AVG(Rating), 2) FROM Reviews WHERE TutorId = @tutor), 0)
WHERE TutorID = @tutor;

COMMIT;
