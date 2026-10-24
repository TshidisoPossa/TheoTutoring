USE theotutoring;

-- Additive follow-up: the university or college the student attends
-- (StudentProfile.Institution in project documentation 11.1). Asked for on
-- the student registration form and shown to tutors on the booking details
-- page. NULL for students who registered before this column existed.
DROP PROCEDURE IF EXISTS apply_006_student_institution;
DELIMITER $$

CREATE PROCEDURE apply_006_student_institution()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'StudentProfile'
          AND COLUMN_NAME = 'Institution'
    ) THEN
        ALTER TABLE StudentProfile
            ADD COLUMN Institution VARCHAR(150) NULL AFTER StudentID;
    END IF;
END$$

DELIMITER ;

CALL apply_006_student_institution();
DROP PROCEDURE IF EXISTS apply_006_student_institution;

INSERT IGNORE INTO SchemaMigrations (Version)
VALUES ('006_student_institution');
