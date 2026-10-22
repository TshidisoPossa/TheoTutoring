-- TESTING ONLY, on a LOCAL database: approves two registered tutors the way
-- the admin page will (project documentation 10.3, "Approving a tutor"),
-- so students can find and book them before the admin page exists.
--
--   TutorID 2  palesa  (palesa45@gmail.com)
--   TutorID 3  Thato   (thato45@gmail.com)
--
-- Students only see a tutor when all three of these are set (lib/tutor_search.dart):
--   User.AccountStatus = 'Active'
--   TutorProfile.VerificationStat = 'Approved'
--   TutorApplication.Status = 'Approved'
-- Their Firebase accounts are not touched. Undo with unapprove_test_tutors.sql.
USE theotutoring;

START TRANSACTION;

UPDATE TutorApplication
SET Status = 'Approved',
    Review_at = NOW(),
    AdminFeedback = 'Approved for testing (no admin page yet).'
WHERE TutorID IN (2, 3);

UPDATE TutorProfile
SET VerificationStat = 'Approved'
WHERE TutorID IN (2, 3);

UPDATE `User` u
JOIN TutorProfile tp ON tp.UserID = u.UserId
SET u.AccountStatus = 'Active'
WHERE tp.TutorID IN (2, 3);

COMMIT;

SELECT tp.TutorID, u.Name, u.AccountStatus, tp.VerificationStat,
       ta.Status AS ApplicationStatus, ta.Review_at
FROM TutorProfile tp
JOIN `User` u ON u.UserId = tp.UserID
LEFT JOIN TutorApplication ta ON ta.TutorID = tp.TutorID
WHERE tp.TutorID IN (2, 3);
