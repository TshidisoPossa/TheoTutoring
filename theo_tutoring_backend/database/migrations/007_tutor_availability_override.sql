USE theotutoring;

-- Additive follow-up: one-off changes to a tutor's weekly hours on a single
-- date, set from the calendar on the tutor's Profile page. When a date has
-- any rows here, they replace that weekday's TutAvailability hours for that
-- date only:
--   * one row with StartTime/EndTime NULL = the tutor takes the day off;
--   * rows with times = the only hours the tutor is open that day.
-- A date with no rows keeps the usual weekly hours.
CREATE TABLE IF NOT EXISTS TutAvailabilityOverride (
    OverrideID INT AUTO_INCREMENT PRIMARY KEY,
    TutorID INT NOT NULL,
    `Date` DATE NOT NULL,
    StartTime TIME NULL,
    EndTime TIME NULL,

    CONSTRAINT chk_override_times CHECK (
        (StartTime IS NULL AND EndTime IS NULL) OR StartTime < EndTime
    ),

    CONSTRAINT fk_override_tutor
        FOREIGN KEY (TutorID) REFERENCES TutorProfile(TutorID),

    INDEX idx_override_tutor_date (TutorID, `Date`)
);

INSERT IGNORE INTO SchemaMigrations (Version)
VALUES ('007_tutor_availability_override');
