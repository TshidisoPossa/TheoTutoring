-- =========================================================
-- Run ONCE on a database created before the Booking.Status change.
-- New databases get the right ENUM from schema.sql.
--
-- Booking.Status becomes the documentation's statuses (section 4.5)
-- plus 'Postponed':
--   Pending, Accepted, Declined, Confirmed, Postponed, Cancelled, Completed
-- The old 'Rejected' value is renamed to 'Declined'.
-- =========================================================

USE theotutoring;

-- 1. Plain text first, so old values survive while they are renamed.
ALTER TABLE Booking MODIFY Status VARCHAR(20) NULL;

UPDATE Booking SET Status = 'Declined' WHERE Status = 'Rejected';
UPDATE Booking SET Status = 'Pending' WHERE Status IS NULL OR Status = '';

-- 2. Back to an ENUM with the new list.
ALTER TABLE Booking MODIFY Status ENUM(
    'Pending', 'Accepted', 'Declined', 'Confirmed',
    'Postponed', 'Cancelled', 'Completed'
) NOT NULL DEFAULT 'Pending';
