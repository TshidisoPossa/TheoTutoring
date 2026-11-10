-- Demo tutors for a LOCAL database. Do not run it on a shared or live
-- database.
--
-- It runs on whichever database you select, e.g.
--   mysql -u theo_app -p theotutoring < database/seed_demo_tutors.sql
-- (or pick the schema in MySQL Workbench first). Subjects are matched by
-- name, so it works whatever subject IDs your database has.
--
-- Seeds six approved tutors whose Firebase accounts already exist. Firebase
-- handles their sign-in; no passwords or secrets are stored here.
--
-- A tutor appears in tutor search and can use the tutor dashboard when
-- (lib/tutor_search.dart, lib/tutor_account_status.dart):
--   User.Role = 'tutor' AND User.AccountStatus = 'Active'
--   TutorProfile.VerificationStat = 'Approved'
--   their latest TutorApplication.Status = 'Approved'
--
-- Safe to rerun: rows are matched on FirebaseUid and only missing rows are
-- inserted, so profiles, qualifications, subject links and applications are
-- never duplicated. Every insert, update and delete is limited to these six
-- UIDs. The only rows deleted are qualifications an earlier version of this
-- seed added that no longer match the tutor's subjects.
-- A tutor is skipped by every step when their email or Firebase UID belongs
-- to another account, or their existing account is a student or admin.
-- The session rate is platform-wide (PlatformSettings.TutoringRate) and is
-- not changed here.
-- Weekly availability (TutAvailability) covers Monday to Saturday. It is only
-- added on days a tutor has no hours yet, so hours a tutor sets in the app
-- are never overwritten.
DROP TEMPORARY TABLE IF EXISTS demo_tutor_seed;
DROP TEMPORARY TABLE IF EXISTS demo_tutor_qualification;
DROP TEMPORARY TABLE IF EXISTS demo_tutor_retired_qualification;
DROP TEMPORARY TABLE IF EXISTS demo_tutor_subject;
DROP TEMPORARY TABLE IF EXISTS demo_tutor_availability;

CREATE TEMPORARY TABLE demo_tutor_seed (
    FirebaseUid VARCHAR(128) NOT NULL PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    Email VARCHAR(150) NOT NULL,
    ProfilePhoto VARCHAR(500) NOT NULL,
    Bio TEXT NOT NULL,
    Experience VARCHAR(50) NOT NULL,
    SkipReason VARCHAR(100) NULL
);

-- SortOrder sets insert order; tutor search shows the newest qualification.
CREATE TEMPORARY TABLE demo_tutor_qualification (
    FirebaseUid VARCHAR(128) NOT NULL,
    SortOrder TINYINT NOT NULL,
    Degree VARCHAR(100) NOT NULL,
    Institution VARCHAR(100) NOT NULL,
    PRIMARY KEY (FirebaseUid, SortOrder)
);

-- Qualifications an earlier version of this seed inserted.
CREATE TEMPORARY TABLE demo_tutor_retired_qualification (
    FirebaseUid VARCHAR(128) NOT NULL,
    Degree VARCHAR(100) NOT NULL,
    Institution VARCHAR(100) NOT NULL,
    PRIMARY KEY (FirebaseUid, Degree, Institution)
);

CREATE TEMPORARY TABLE demo_tutor_subject (
    FirebaseUid VARCHAR(128) NOT NULL,
    SubjectName VARCHAR(100) NOT NULL,
    PRIMARY KEY (FirebaseUid, SubjectName)
);

-- Weekly hours, following the app's rules (routes/auth/tutor/availability.dart):
-- Monday to Saturday only, start before end, no overlaps on the same day.
CREATE TEMPORARY TABLE demo_tutor_availability (
    FirebaseUid VARCHAR(128) NOT NULL,
    Day ENUM('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
             'Saturday') NOT NULL,
    StartTime TIME NOT NULL,
    EndTime TIME NOT NULL,
    PRIMARY KEY (FirebaseUid, Day, StartTime)
);

-- Experience uses the registration options: '0-1', '1-2', '3-5', '5+'.
-- Bios follow the registration limit of 20 to 300 characters.
INSERT INTO demo_tutor_seed
    (FirebaseUid, Name, Email, ProfilePhoto, Bio, Experience)
VALUES
    ('8qLmuE1jOwWUGKK04pIS5syqX7f2', 'Lerato Mokoena',
     'lerato.mokoena.tutor@example.com',
     'https://ui-avatars.com/api/?name=Lerato+Mokoena&size=256&background=1E88E5&color=FFFFFF&format=png',
     'Mathematics graduate who tutors calculus, algebra, statistics and physics. I show students how the maths behind probability and mechanics works, using clear worked examples and exam-style practice. Patient, structured sessions for all year levels.',
     '3-5'),
    ('tnBSg5ZqiARAfQIENZMQ9yK21cg2', 'Thabo Nkosi',
     'thabo.nkosi.tutor@example.com',
     'https://ui-avatars.com/api/?name=Thabo+Nkosi&size=256&background=1E88E5&color=FFFFFF&format=png',
     'Software engineer with over six years of tutoring Python, Java and object-oriented programming. I take students from core syntax to classes, inheritance and design patterns, breaking problems into clear steps and reviewing their code line by line.',
     '5+'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 'Ayesha Khan',
     'ayesha.khan.tutor@example.com',
     'https://ui-avatars.com/api/?name=Ayesha+Khan&size=256&background=1E88E5&color=FFFFFF&format=png',
     'Chartered accountant in training who tutors accounting, economics and finance. I explain financial statements, supply and demand, and the time value of money with practical South African examples, building confidence for tests and exams.',
     '3-5'),
    ('7BG1C5g0zWZDVcwJA81ZC101IVo2', 'Kabelo Dlamini',
     'kabelo.dlamini.tutor@example.com',
     'https://ui-avatars.com/api/?name=Kabelo+Dlamini&size=256&background=1E88E5&color=FFFFFF&format=png',
     'Data analyst who tutors database management systems, SQL and data science. I cover ER modelling, normalisation and complex queries, then show how clean data feeds analysis and visualisation in Python. Practical sessions built on real datasets.',
     '3-5'),
    ('i0jAsxyg3weKCoyrt6scBk2GEDB3', 'Naledi Molefe',
     'naledi.molefe.tutor@example.com',
     'https://ui-avatars.com/api/?name=Naledi+Molefe&size=256&background=1E88E5&color=FFFFFF&format=png',
     'Junior software developer and recent honours graduate. I tutor web development, mobile app development and software engineering, from HTML, CSS and JavaScript to Flutter apps, Git and agile teamwork. Friendly, hands-on sessions for all levels.',
     '1-2'),
    ('UhVclfz48tNFMIR4Ax73XPd6TqY2', 'Sipho Khumalo',
     'sipho.khumalo.tutor@example.com',
     'https://ui-avatars.com/api/?name=Sipho+Khumalo&size=256&background=1E88E5&color=FFFFFF&format=png',
     'Network engineer with over six years of tutoring computer networks, operating systems and cybersecurity. I explain the OSI model, subnetting, processes, memory management and security fundamentals through practical labs and real scenarios.',
     '5+');

INSERT INTO demo_tutor_qualification
    (FirebaseUid, SortOrder, Degree, Institution)
VALUES
    ('8qLmuE1jOwWUGKK04pIS5syqX7f2', 1, 'BSc Mathematics and Physics',
     'University of the Witwatersrand'),
    ('8qLmuE1jOwWUGKK04pIS5syqX7f2', 2, 'BSc Honours in Mathematical Statistics',
     'University of the Witwatersrand'),
    ('tnBSg5ZqiARAfQIENZMQ9yK21cg2', 1, 'BSc Computer Science',
     'University of Pretoria'),
    ('tnBSg5ZqiARAfQIENZMQ9yK21cg2', 2, 'BSc Honours in Computer Science',
     'University of Pretoria'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 1, 'BCom Accounting',
     'University of Cape Town'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 2, 'BCom Honours in Finance and Economics',
     'University of Cape Town'),
    ('7BG1C5g0zWZDVcwJA81ZC101IVo2', 1, 'BSc Information Technology',
     'North-West University'),
    ('7BG1C5g0zWZDVcwJA81ZC101IVo2', 2, 'BSc Honours in Data Science',
     'North-West University'),
    ('i0jAsxyg3weKCoyrt6scBk2GEDB3', 1, 'BSc Computer Science',
     'Stellenbosch University'),
    ('i0jAsxyg3weKCoyrt6scBk2GEDB3', 2, 'BSc Honours in Software Engineering',
     'Stellenbosch University'),
    ('UhVclfz48tNFMIR4Ax73XPd6TqY2', 1, 'Diploma in Information Technology',
     'Durban University of Technology'),
    ('UhVclfz48tNFMIR4Ax73XPd6TqY2', 2, 'Advanced Diploma in Network Security',
     'Durban University of Technology');

-- Rows here that also appear in demo_tutor_qualification are kept.
INSERT INTO demo_tutor_retired_qualification (FirebaseUid, Degree, Institution)
VALUES
    ('8qLmuE1jOwWUGKK04pIS5syqX7f2', 'BSc Computer Science',
     'University of the Witwatersrand'),
    ('8qLmuE1jOwWUGKK04pIS5syqX7f2', 'Postgraduate Diploma in Financial Management',
     'University of Johannesburg'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 'BSc Physics',
     'University of Cape Town'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 'MSc Physics',
     'University of Cape Town'),
    ('7BG1C5g0zWZDVcwJA81ZC101IVo2', 'Diploma in Information Technology',
     'Tshwane University of Technology'),
    ('7BG1C5g0zWZDVcwJA81ZC101IVo2', 'Advanced Diploma in Information Technology',
     'Tshwane University of Technology'),
    ('i0jAsxyg3weKCoyrt6scBk2GEDB3', 'BSc Honours in Computer Science',
     'Stellenbosch University'),
    ('UhVclfz48tNFMIR4Ax73XPd6TqY2', 'BSc Mathematical Sciences',
     'University of KwaZulu-Natal'),
    ('UhVclfz48tNFMIR4Ax73XPd6TqY2', 'MSc Computer Science',
     'University of KwaZulu-Natal');

-- Lerato: Mathematics, Statistics, Physics
-- Thabo:  Python Programming, Java Programming, Object-Oriented Programming
-- Ayesha: Accounting, Economics, Finance
-- Kabelo: Database Management Systems, SQL and Database Design, Data Science
-- Naledi: Web Development, Mobile App Development, Software Engineering
-- Sipho:  Computer Networks, Operating Systems, Cybersecurity
INSERT INTO demo_tutor_subject (FirebaseUid, SubjectName)
VALUES
    ('8qLmuE1jOwWUGKK04pIS5syqX7f2', 'Mathematics'),
    ('8qLmuE1jOwWUGKK04pIS5syqX7f2', 'Statistics'),
    ('8qLmuE1jOwWUGKK04pIS5syqX7f2', 'Physics'),
    ('tnBSg5ZqiARAfQIENZMQ9yK21cg2', 'Python Programming'),
    ('tnBSg5ZqiARAfQIENZMQ9yK21cg2', 'Java Programming'),
    ('tnBSg5ZqiARAfQIENZMQ9yK21cg2', 'Object-Oriented Programming'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 'Accounting'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 'Economics'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 'Finance'),
    ('7BG1C5g0zWZDVcwJA81ZC101IVo2', 'Database Management Systems'),
    ('7BG1C5g0zWZDVcwJA81ZC101IVo2', 'SQL and Database Design'),
    ('7BG1C5g0zWZDVcwJA81ZC101IVo2', 'Data Science'),
    ('i0jAsxyg3weKCoyrt6scBk2GEDB3', 'Web Development'),
    ('i0jAsxyg3weKCoyrt6scBk2GEDB3', 'Mobile App Development'),
    ('i0jAsxyg3weKCoyrt6scBk2GEDB3', 'Software Engineering'),
    ('UhVclfz48tNFMIR4Ax73XPd6TqY2', 'Computer Networks'),
    ('UhVclfz48tNFMIR4Ax73XPd6TqY2', 'Operating Systems'),
    ('UhVclfz48tNFMIR4Ax73XPd6TqY2', 'Cybersecurity');

-- Every tutor works all six bookable days (Monday to Saturday), so students
-- can pick any day of the month. Sunday is not allowed by the app.
-- Lerato: weekday afternoons, Saturday morning
-- Thabo:  weekday evenings after work, Saturday late morning
-- Ayesha: Mon/Wed/Fri mornings, Tue/Thu mornings and afternoons, Saturday
-- Kabelo: weekday early evenings, Saturday morning
-- Naledi: weekday late afternoons, Saturday morning
-- Sipho:  weekday mornings, Saturday midday
INSERT INTO demo_tutor_availability (FirebaseUid, Day, StartTime, EndTime)
VALUES
    ('8qLmuE1jOwWUGKK04pIS5syqX7f2', 'Monday',    '14:00', '18:00'),
    ('8qLmuE1jOwWUGKK04pIS5syqX7f2', 'Tuesday',   '14:00', '18:00'),
    ('8qLmuE1jOwWUGKK04pIS5syqX7f2', 'Wednesday', '14:00', '18:00'),
    ('8qLmuE1jOwWUGKK04pIS5syqX7f2', 'Thursday',  '14:00', '18:00'),
    ('8qLmuE1jOwWUGKK04pIS5syqX7f2', 'Friday',    '14:00', '18:00'),
    ('8qLmuE1jOwWUGKK04pIS5syqX7f2', 'Saturday',  '09:00', '13:00'),
    ('tnBSg5ZqiARAfQIENZMQ9yK21cg2', 'Monday',    '17:00', '20:00'),
    ('tnBSg5ZqiARAfQIENZMQ9yK21cg2', 'Tuesday',   '17:00', '20:00'),
    ('tnBSg5ZqiARAfQIENZMQ9yK21cg2', 'Wednesday', '17:00', '20:00'),
    ('tnBSg5ZqiARAfQIENZMQ9yK21cg2', 'Thursday',  '17:00', '20:00'),
    ('tnBSg5ZqiARAfQIENZMQ9yK21cg2', 'Friday',    '17:00', '20:00'),
    ('tnBSg5ZqiARAfQIENZMQ9yK21cg2', 'Saturday',  '10:00', '14:00'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 'Monday',    '09:00', '13:00'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 'Tuesday',   '09:00', '12:00'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 'Tuesday',   '14:00', '17:00'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 'Wednesday', '09:00', '13:00'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 'Thursday',  '09:00', '12:00'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 'Thursday',  '14:00', '17:00'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 'Friday',    '09:00', '13:00'),
    ('ummBeaeGRtaerMb3zj7WzhCtyN13', 'Saturday',  '08:00', '12:00'),
    ('7BG1C5g0zWZDVcwJA81ZC101IVo2', 'Monday',    '17:00', '20:00'),
    ('7BG1C5g0zWZDVcwJA81ZC101IVo2', 'Tuesday',   '17:00', '20:00'),
    ('7BG1C5g0zWZDVcwJA81ZC101IVo2', 'Wednesday', '17:00', '20:00'),
    ('7BG1C5g0zWZDVcwJA81ZC101IVo2', 'Thursday',  '17:00', '20:00'),
    ('7BG1C5g0zWZDVcwJA81ZC101IVo2', 'Friday',    '17:00', '20:00'),
    ('7BG1C5g0zWZDVcwJA81ZC101IVo2', 'Saturday',  '09:00', '12:00'),
    ('i0jAsxyg3weKCoyrt6scBk2GEDB3', 'Monday',    '16:00', '19:00'),
    ('i0jAsxyg3weKCoyrt6scBk2GEDB3', 'Tuesday',   '16:00', '19:00'),
    ('i0jAsxyg3weKCoyrt6scBk2GEDB3', 'Wednesday', '16:00', '19:00'),
    ('i0jAsxyg3weKCoyrt6scBk2GEDB3', 'Thursday',  '16:00', '19:00'),
    ('i0jAsxyg3weKCoyrt6scBk2GEDB3', 'Friday',    '16:00', '19:00'),
    ('i0jAsxyg3weKCoyrt6scBk2GEDB3', 'Saturday',  '09:00', '13:00'),
    ('UhVclfz48tNFMIR4Ax73XPd6TqY2', 'Monday',    '08:00', '12:00'),
    ('UhVclfz48tNFMIR4Ax73XPd6TqY2', 'Tuesday',   '08:00', '12:00'),
    ('UhVclfz48tNFMIR4Ax73XPd6TqY2', 'Wednesday', '08:00', '12:00'),
    ('UhVclfz48tNFMIR4Ax73XPd6TqY2', 'Thursday',  '08:00', '12:00'),
    ('UhVclfz48tNFMIR4Ax73XPd6TqY2', 'Friday',    '08:00', '12:00'),
    ('UhVclfz48tNFMIR4Ax73XPd6TqY2', 'Saturday',  '10:00', '15:00');

-- ── Conflicts: every write below skips a tutor with a SkipReason ───────────
UPDATE demo_tutor_seed s
SET s.SkipReason = 'Email belongs to a different Firebase UID'
WHERE EXISTS (
    SELECT 1 FROM `User` u
    WHERE u.Email = s.Email AND u.FirebaseUid <> s.FirebaseUid
);

UPDATE demo_tutor_seed s
SET s.SkipReason = 'Firebase UID belongs to a different email'
WHERE s.SkipReason IS NULL
  AND EXISTS (
    SELECT 1 FROM `User` u
    WHERE u.FirebaseUid = s.FirebaseUid AND u.Email <> s.Email
);

-- Never convert a student or admin account into a tutor.
UPDATE demo_tutor_seed s
SET s.SkipReason = 'Existing account is a student or admin'
WHERE s.SkipReason IS NULL
  AND EXISTS (
    SELECT 1 FROM `User` u
    WHERE u.FirebaseUid = s.FirebaseUid
      AND (
        u.Role <> 'tutor'
        OR EXISTS (SELECT 1 FROM StudentProfile sp WHERE sp.UserID = u.UserId)
        OR EXISTS (SELECT 1 FROM Admin a WHERE a.UserId = u.UserId)
      )
);

-- Both pre-checks should return no rows.
SELECT s.Name, s.Email, s.SkipReason
FROM demo_tutor_seed s
WHERE s.SkipReason IS NOT NULL;

-- A subject name that is not in Subjects. That subject link is skipped.
SELECT ds.FirebaseUid, ds.SubjectName AS MissingSubject
FROM demo_tutor_subject ds
LEFT JOIN Subjects sj ON sj.subjectName = ds.SubjectName
WHERE sj.subjectId IS NULL;

START TRANSACTION;

-- ── 1. User ────────────────────────────────────────────────────────────────
INSERT INTO `User`
    (FirebaseUid, Name, PhoneNum, Email, Role, ProfilePhoto, AccountStatus)
SELECT s.FirebaseUid, s.Name, '', s.Email, 'tutor', s.ProfilePhoto, 'Active'
FROM demo_tutor_seed s
WHERE s.SkipReason IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM `User` u
    WHERE u.FirebaseUid = s.FirebaseUid OR u.Email = s.Email
);

UPDATE `User` u
JOIN demo_tutor_seed s
    ON s.FirebaseUid = u.FirebaseUid AND s.SkipReason IS NULL
SET u.Name = s.Name,
    u.ProfilePhoto = s.ProfilePhoto,
    u.AccountStatus = 'Active';

-- ── 2. TutorProfile ────────────────────────────────────────────────────────
INSERT INTO TutorProfile (UserID, Bio, Experience, VerificationStat)
SELECT u.UserId, s.Bio, s.Experience, 'Approved'
FROM demo_tutor_seed s
JOIN `User` u ON u.FirebaseUid = s.FirebaseUid
WHERE s.SkipReason IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM TutorProfile tp WHERE tp.UserID = u.UserId
);

UPDATE TutorProfile tp
JOIN `User` u ON u.UserId = tp.UserID
JOIN demo_tutor_seed s
    ON s.FirebaseUid = u.FirebaseUid AND s.SkipReason IS NULL
SET tp.Bio = s.Bio,
    tp.Experience = s.Experience,
    tp.VerificationStat = 'Approved';

-- ── 3. Qualification ───────────────────────────────────────────────────────
-- Remove only this seed's retired rows; qualifications a tutor added
-- themselves and the current ones are kept.
DELETE q
FROM Qualification q
JOIN TutorProfile tp ON tp.TutorID = q.TutorID
JOIN `User` u ON u.UserId = tp.UserID
JOIN demo_tutor_seed s
    ON s.FirebaseUid = u.FirebaseUid AND s.SkipReason IS NULL
JOIN demo_tutor_retired_qualification r
    ON r.FirebaseUid = s.FirebaseUid
   AND r.Degree = q.Degree
   AND r.Institution = q.Institution
WHERE NOT EXISTS (
    SELECT 1 FROM demo_tutor_qualification dq
    WHERE dq.FirebaseUid = s.FirebaseUid
      AND dq.Degree = q.Degree
      AND dq.Institution = q.Institution
);

INSERT INTO Qualification (TutorID, Degree, Institution)
SELECT tp.TutorID, dq.Degree, dq.Institution
FROM demo_tutor_qualification dq
JOIN demo_tutor_seed s
    ON s.FirebaseUid = dq.FirebaseUid AND s.SkipReason IS NULL
JOIN `User` u ON u.FirebaseUid = s.FirebaseUid
JOIN TutorProfile tp ON tp.UserID = u.UserId
WHERE NOT EXISTS (
    SELECT 1 FROM Qualification q
    WHERE q.TutorID = tp.TutorID
      AND q.Degree = dq.Degree
      AND q.Institution = dq.Institution
)
ORDER BY tp.TutorID, dq.SortOrder;

-- ── 4. TutorSubjects ───────────────────────────────────────────────────────
INSERT INTO TutorSubjects (TutorID, SubjectID)
SELECT tp.TutorID, sj.subjectId
FROM demo_tutor_subject ds
JOIN demo_tutor_seed s
    ON s.FirebaseUid = ds.FirebaseUid AND s.SkipReason IS NULL
JOIN Subjects sj ON sj.subjectName = ds.SubjectName
JOIN `User` u ON u.FirebaseUid = s.FirebaseUid
JOIN TutorProfile tp ON tp.UserID = u.UserId
WHERE NOT EXISTS (
    SELECT 1 FROM TutorSubjects ts
    WHERE ts.TutorID = tp.TutorID AND ts.SubjectID = sj.subjectId
);

-- ── 5. TutAvailability ─────────────────────────────────────────────────────
-- Only fills days the tutor has no hours on yet. A day that already has
-- hours (set by the tutor in the app, or by an earlier run) is left as it
-- is, so nothing overlaps and nothing is duplicated.
INSERT INTO TutAvailability (TutorID, Day, StartTime, end_Time)
SELECT tp.TutorID, da.Day, da.StartTime, da.EndTime
FROM demo_tutor_availability da
JOIN demo_tutor_seed s
    ON s.FirebaseUid = da.FirebaseUid AND s.SkipReason IS NULL
JOIN `User` u ON u.FirebaseUid = s.FirebaseUid
JOIN TutorProfile tp ON tp.UserID = u.UserId
WHERE NOT EXISTS (
    SELECT 1 FROM TutAvailability ta
    WHERE ta.TutorID = tp.TutorID AND ta.Day = da.Day
)
ORDER BY tp.TutorID, da.Day, da.StartTime;

-- ── 6. TutorApplication ────────────────────────────────────────────────────
-- One application per tutor. If a tutor already has applications, the
-- latest one is approved instead of adding another.
INSERT INTO TutorApplication
    (TutorID, Status, AdminFeedback, SubmittedAt, Review_at)
SELECT tp.TutorID, 'Approved', 'Approved demo tutor.', NOW(), NOW()
FROM demo_tutor_seed s
JOIN `User` u ON u.FirebaseUid = s.FirebaseUid
JOIN TutorProfile tp ON tp.UserID = u.UserId
WHERE s.SkipReason IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM TutorApplication ta WHERE ta.TutorID = tp.TutorID
);

-- The latest-application lookup only covers the seeded, non-skipped tutors.
UPDATE TutorApplication ta
JOIN (
    SELECT la.TutorID, MAX(la.TutApplication) AS LatestApplication
    FROM TutorApplication la
    JOIN TutorProfile tp ON tp.TutorID = la.TutorID
    JOIN `User` u ON u.UserId = tp.UserID
    JOIN demo_tutor_seed s
        ON s.FirebaseUid = u.FirebaseUid AND s.SkipReason IS NULL
    GROUP BY la.TutorID
) latest
    ON latest.TutorID = ta.TutorID
   AND latest.LatestApplication = ta.TutApplication
SET ta.Status = 'Approved',
    ta.AdminFeedback = 'Approved demo tutor.',
    ta.Review_at = NOW()
WHERE ta.Status <> 'Approved';

COMMIT;

-- ── Result: one row per seeded tutor. Skipped tutors show SkipReason. ──────
SELECT s.Name, s.Email, s.SkipReason, tp.TutorID, u.Role, u.AccountStatus,
       tp.VerificationStat, tp.Experience,
       (SELECT ta.Status FROM TutorApplication ta
        WHERE ta.TutorID = tp.TutorID
        ORDER BY ta.TutApplication DESC LIMIT 1) AS LatestApplication,
       (SELECT COUNT(*) FROM TutorApplication ta
        WHERE ta.TutorID = tp.TutorID) AS Applications,
       (SELECT COUNT(*) FROM Qualification q
        WHERE q.TutorID = tp.TutorID) AS Qualifications,
       (SELECT GROUP_CONCAT(sj.subjectName ORDER BY sj.subjectName SEPARATOR ', ')
        FROM TutorSubjects ts JOIN Subjects sj ON sj.subjectId = ts.SubjectID
        WHERE ts.TutorID = tp.TutorID) AS Subjects,
       (SELECT GROUP_CONCAT(
            CONCAT(LEFT(av.Day, 3), ' ', TIME_FORMAT(av.StartTime, '%H:%i'),
                   '-', TIME_FORMAT(av.end_Time, '%H:%i'))
            ORDER BY av.Day, av.StartTime SEPARATOR ', ')
        FROM TutAvailability av
        WHERE av.TutorID = tp.TutorID) AS WeeklyHours,
       (SELECT ps.TutoringRate FROM PlatformSettings ps
        WHERE ps.SettingsID = 1) AS PlatformRate
FROM demo_tutor_seed s
LEFT JOIN `User` u
    ON u.FirebaseUid = s.FirebaseUid AND s.SkipReason IS NULL
LEFT JOIN TutorProfile tp ON tp.UserID = u.UserId
ORDER BY s.Name;

DROP TEMPORARY TABLE IF EXISTS demo_tutor_seed;
DROP TEMPORARY TABLE IF EXISTS demo_tutor_qualification;
DROP TEMPORARY TABLE IF EXISTS demo_tutor_retired_qualification;
DROP TEMPORARY TABLE IF EXISTS demo_tutor_subject;
DROP TEMPORARY TABLE IF EXISTS demo_tutor_availability;
