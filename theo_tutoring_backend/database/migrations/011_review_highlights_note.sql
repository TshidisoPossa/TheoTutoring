USE theotutoring;

-- Additive follow-up: the redesigned Leave a Review page.
--
-- Highlights   the badges the student tapped under "What made this session
--              great?", comma-separated, e.g.
--              "Clear explanations,Patient with questions"
--              (the list is fixed in lib/student_reviews.dart)
-- PrivateNote  a note for the TheoTutoring team, up to 500 characters
--
-- Both are shown ONLY on the admin Reviews page: never on the tutor's public
-- profile, the tutor's bell or the student search. Both are NULL when the
-- student left them empty, and for reviews written before this migration.
DROP PROCEDURE IF EXISTS apply_011_review_highlights_note;
DELIMITER $$

CREATE PROCEDURE apply_011_review_highlights_note()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'reviews'
          AND COLUMN_NAME = 'Highlights'
    ) THEN
        ALTER TABLE reviews
            ADD COLUMN Highlights VARCHAR(255) NULL AFTER `comment`;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'reviews'
          AND COLUMN_NAME = 'PrivateNote'
    ) THEN
        ALTER TABLE reviews
            ADD COLUMN PrivateNote VARCHAR(500) NULL AFTER Highlights;
    END IF;
END$$

DELIMITER ;

CALL apply_011_review_highlights_note();
DROP PROCEDURE IF EXISTS apply_011_review_highlights_note;

INSERT IGNORE INTO schemamigrations (Version)
VALUES ('011_review_highlights_note');