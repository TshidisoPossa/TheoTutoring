


-- After this, run seed_subjects.sql to fill the Subjects table.

-- ── TutorProfile ────────────────────────────────────────────
-- Fix the misspelt column names the backend expects
ALTER TABLE TutorProfile
    RENAME COLUMN Experiance TO Experience,
    RENAME COLUMN IdDocum TO IdDocument;

-- Tutors do not set a rate (fixed by the admin), and the profile photo
-- lives in User.ProfilePhoto, so both columns go
ALTER TABLE TutorProfile
    MODIFY Certificate VARCHAR(500) NULL,
    MODIFY IdDocument VARCHAR(500) NULL,
    MODIFY VerificationStat ENUM('Pending', 'Approved', 'Rejected')
        NOT NULL DEFAULT 'Pending',
    MODIFY AveRate DECIMAL(3,2) NOT NULL DEFAULT 0,
    DROP COLUMN HourlyRate,
    DROP COLUMN ProfilePhotoUrl,
    ADD CONSTRAINT chk_tutor_average_rating CHECK (AveRate BETWEEN 0 AND 5);

-- ── Subjects ────────────────────────────────────────────────
-- Subject names must be unique (seed_subjects.sql relies on this)
ALTER TABLE Subjects
    ADD UNIQUE KEY subjectName (subjectName);

-- ── Qualification ───────────────────────────────────────────
ALTER TABLE Qualification
    MODIFY Degree VARCHAR(100) NOT NULL,
    MODIFY Institution VARCHAR(100) NOT NULL;

-- ── TutAvailability ─────────────────────────────────────────
ALTER TABLE TutAvailability
    MODIFY Day ENUM(
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday'
    ) NOT NULL,
    MODIFY StartTime TIME NOT NULL,
    MODIFY end_Time TIME NOT NULL,
    ADD CONSTRAINT chk_availability_times CHECK (StartTime < end_Time);

-- ── TutorApplication ─────────────────────────────────────────
-- Applications belong to a tutor (TutorID), not a student
ALTER TABLE TutorApplication
    DROP FOREIGN KEY tutorapplication_ibfk_1;

ALTER TABLE TutorApplication
    DROP COLUMN StudentID,
    MODIFY Status ENUM('Pending', 'Approved', 'Rejected')
        NOT NULL DEFAULT 'Pending',
    RENAME COLUMN review_at TO Review_at;
