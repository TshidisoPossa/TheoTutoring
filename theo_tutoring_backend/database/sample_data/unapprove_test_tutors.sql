-- Undoes approve_test_tutors.sql: puts palesa (TutorID 2) and Thato
-- (TutorID 3) back to a Pending application waiting for an admin.
USE theotutoring;

START TRANSACTION;

UPDATE TutorApplication
SET Status = 'Pending', Review_at = NULL, AdminFeedback = NULL
WHERE TutorID IN (2, 3);

UPDATE TutorProfile
SET VerificationStat = 'Pending'
WHERE TutorID IN (2, 3);

UPDATE `User` u
JOIN TutorProfile tp ON tp.UserID = u.UserId
SET u.AccountStatus = 'Pending'
WHERE tp.TutorID IN (2, 3);

COMMIT;
