USE theotutoring;

-- Additive follow-up: each tutor's reusable Google Meet room, set when they
-- connect Google (registration Step 3 or the Profile page).
-- NULL = not connected yet.
DROP PROCEDURE IF EXISTS apply_008_tutor_meet_link;
DELIMITER $$

CREATE PROCEDURE apply_008_tutor_meet_link()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'TutorProfile'
          AND COLUMN_NAME = 'MeetLink'
    ) THEN
        ALTER TABLE TutorProfile
            ADD COLUMN MeetLink VARCHAR(500) NULL;
    END IF;
END$$

DELIMITER ;

CALL apply_008_tutor_meet_link();
DROP PROCEDURE IF EXISTS apply_008_tutor_meet_link;

-- lib/booking_tutor.dart already saves Accepted and Postponed, but no
-- earlier migration added them. Fails (and changes nothing) if a booking
-- has a status outside this list or NULL; check first with
-- SELECT Status, COUNT(*) FROM Booking GROUP BY Status;
ALTER TABLE Booking MODIFY COLUMN Status ENUM(
    'Pending', 'Accepted', 'Postponed', 'Confirmed',
    'Completed', 'Cancelled', 'Rejected'
) NOT NULL DEFAULT 'Pending';

INSERT IGNORE INTO SchemaMigrations (Version)
VALUES ('008_tutor_meet_link');
