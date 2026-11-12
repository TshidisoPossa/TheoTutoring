-- WITHDRAWN - DO NOT RUN. Replacement repair scripts are under review and
-- not yet in the repository. See database/migrations/README.md.
SELECT * FROM `withdrawn_migration_do_not_run`;
USE theotutoring;

-- Requires 004_report.sql, 004_user_reports.sql, Admin, and SchemaMigrations.
-- The map and each imported Report row are committed atomically per source row.
CREATE TABLE IF NOT EXISTS UserReportReportMap (
    LegacyReportID INT NOT NULL PRIMARY KEY,
    ReportID INT NOT NULL UNIQUE,
    MappedAt DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT fk_user_report_map_report
        FOREIGN KEY (ReportID) REFERENCES Report(ReportID)
) ENGINE=InnoDB;

DROP PROCEDURE IF EXISTS migrate_008_user_report_consolidation;
DELIMITER $$

CREATE PROCEDURE migrate_008_user_report_consolidation()
BEGIN
    DECLARE finished BOOLEAN DEFAULT FALSE;
    DECLARE in_transaction BOOLEAN DEFAULT FALSE;
    DECLARE legacy_id INT;
    DECLARE reporter_id INT;
    DECLARE reported_user_id INT;
    DECLARE booking_id INT;
    DECLARE report_reason LONGTEXT;
    DECLARE report_status VARCHAR(32);
    DECLARE created_at_utc DATETIME(6);
    DECLARE admin_id INT;
    DECLARE resolution_note TEXT;
    DECLARE resolved_at_utc DATETIME(6);
    DECLARE destination_id INT;
    DECLARE valid_column_count INT;

    DECLARE legacy_reports CURSOR FOR
        SELECT ur.ReportID, ur.ReporterUserID, ur.ReportedUserID, ur.BookingID,
               CONCAT(ur.Reason, ': ', ur.Description),
               CASE ur.ReportStatus
                   WHEN 'UnderReview' THEN 'Under review'
                   ELSE ur.ReportStatus
               END,
               ur.CreatedAtUtc, ur.ResolvedByAdminID, ur.ResolutionNote,
               ur.ResolvedAtUtc
        FROM UserReport ur
        LEFT JOIN UserReportReportMap mapping
          ON mapping.LegacyReportID = ur.ReportID
        WHERE mapping.LegacyReportID IS NULL
        ORDER BY ur.ReportID;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET finished = TRUE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF in_transaction THEN
            ROLLBACK;
        END IF;
        RESIGNAL;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'UserReport'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Report'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'SchemaMigrations'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Required report tables or SchemaMigrations are missing.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Report'
          AND COLUMN_NAME = 'ResolutionNote'
    ) THEN
        ALTER TABLE Report ADD COLUMN ResolutionNote TEXT NULL;
    END IF;
    SELECT COUNT(*) INTO valid_column_count
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Report'
      AND COLUMN_NAME = 'ResolutionNote'
      AND DATA_TYPE = 'text' AND IS_NULLABLE = 'YES';
    IF valid_column_count <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Report.ResolutionNote has an unexpected definition.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Report'
          AND COLUMN_NAME = 'ResolvedAtUtc'
    ) THEN
        ALTER TABLE Report ADD COLUMN ResolvedAtUtc DATETIME(6) NULL;
    END IF;
    SELECT COUNT(*) INTO valid_column_count
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Report'
      AND COLUMN_NAME = 'ResolvedAtUtc'
      AND DATA_TYPE = 'datetime' AND DATETIME_PRECISION = 6
      AND IS_NULLABLE = 'YES';
    IF valid_column_count <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Report.ResolvedAtUtc has an unexpected definition.';
    END IF;

    OPEN legacy_reports;
    import_loop: LOOP
        FETCH legacy_reports INTO legacy_id, reporter_id, reported_user_id,
            booking_id, report_reason, report_status, created_at_utc, admin_id,
            resolution_note, resolved_at_utc;
        IF finished THEN
            LEAVE import_loop;
        END IF;

        START TRANSACTION;
        SET in_transaction = TRUE;
        INSERT INTO Report
            (ReporterID, ReportedUserID, BookingID, AdminID, Reason, Status,
             Created_at, ResolutionNote, ResolvedAtUtc)
        VALUES
            (reporter_id, reported_user_id, booking_id, admin_id, report_reason,
             report_status, DATE_ADD(created_at_utc, INTERVAL 2 HOUR),
             resolution_note, resolved_at_utc);
        SET destination_id = LAST_INSERT_ID();
        INSERT INTO UserReportReportMap (LegacyReportID, ReportID)
        VALUES (legacy_id, destination_id);
        COMMIT;
        SET in_transaction = FALSE;
    END LOOP;
    CLOSE legacy_reports;

    INSERT IGNORE INTO SchemaMigrations (Version)
    VALUES ('008_user_report_consolidation');
END$$

DELIMITER ;

CALL migrate_008_user_report_consolidation();
DROP PROCEDURE IF EXISTS migrate_008_user_report_consolidation;
