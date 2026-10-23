USE theotutoring;

-- Additive follow-up: when the tutor was last using the app (UTC). The
-- student's Tutor Profile shows "Available Now" while it is recent.
-- NULL = signed out / never seen.
DROP PROCEDURE IF EXISTS apply_005_tutor_presence;
DELIMITER $$

CREATE PROCEDURE apply_005_tutor_presence()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'TutorProfile'
          AND COLUMN_NAME = 'LastActiveAtUtc'
    ) THEN
        ALTER TABLE TutorProfile
            ADD COLUMN LastActiveAtUtc DATETIME(6) NULL;
    END IF;
END$$

DELIMITER ;

CALL apply_005_tutor_presence();
DROP PROCEDURE IF EXISTS apply_005_tutor_presence;

INSERT IGNORE INTO SchemaMigrations (Version)
VALUES ('005_tutor_presence');
