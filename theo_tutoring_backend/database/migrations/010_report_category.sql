USE theotutoring;

-- Additive follow-up: report (documentation 11.1) becomes the one table for
-- every user report, including the admin Refunds & issues screen (which
-- used a separate userreport table before).
--
-- Category = what the report is about: 'Payments & Payouts',
-- 'Student issues' or 'Other' from Report a Problem on the tutor Profile;
-- NULL for the students' lesson/tutor reports. Payments & Payouts and Other
-- are not about another user, so ReportedUserID may now be NULL
-- (chk_report_not_self still holds whenever it is set).
-- ResolutionNote / ResolvedAtUtc are written when an admin resolves a
-- report (AdminID = who resolved it).
DROP PROCEDURE IF EXISTS apply_010_report_category;
DELIMITER $$

CREATE PROCEDURE apply_010_report_category()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'report'
          AND COLUMN_NAME = 'Category'
    ) THEN
        ALTER TABLE report
            ADD COLUMN Category VARCHAR(40) NULL AFTER BookingID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'report'
          AND COLUMN_NAME = 'ResolutionNote'
    ) THEN
        ALTER TABLE report
            ADD COLUMN ResolutionNote TEXT NULL AFTER Status,
            ADD COLUMN ResolvedAtUtc DATETIME(6) NULL AFTER ResolutionNote;
    END IF;

    ALTER TABLE report MODIFY COLUMN ReportedUserID INT NULL;
END$$

DELIMITER ;

CALL apply_010_report_category();
DROP PROCEDURE IF EXISTS apply_010_report_category;

INSERT IGNORE INTO schemamigrations (Version)
VALUES ('010_report_category');