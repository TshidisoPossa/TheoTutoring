USE theotutoring;

-- Additive follow-up: the reason a student gives when cancelling a lesson
-- (My Schedule > Cancel). Existing bookings keep NULL.
DROP PROCEDURE IF EXISTS apply_003_booking_cancellation_reason;
DELIMITER $$

CREATE PROCEDURE apply_003_booking_cancellation_reason()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'Booking'
          AND COLUMN_NAME = 'CancellationReason'
    ) THEN
        ALTER TABLE Booking
            ADD COLUMN CancellationReason TEXT NULL AFTER Note;
    END IF;
END$$

DELIMITER ;

CALL apply_003_booking_cancellation_reason();
DROP PROCEDURE IF EXISTS apply_003_booking_cancellation_reason;

INSERT IGNORE INTO SchemaMigrations (Version)
VALUES ('003_booking_cancellation_reason');
