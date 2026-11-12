-- Additive repair of migration 007_tutor_availability_override.sql (ledger
-- version 007_tutor_availability_override) for the shared Aiven MySQL
-- database `theotutoring`, where table names are case-sensitive
-- (lower_case_table_names = 0) and lowercase.
-- 007_tutor_availability_override.sql remains the source of truth for the
-- table definition; this script only adds what is missing:
--   * the tutavailabilityoverride table (one-off changes to a tutor's weekly
--     hours on a single date),
--   * the 007_tutor_availability_override ledger row, written last and only
--     after the table structure has been verified.
-- No table is dropped or recreated, and no existing row is inserted, updated
-- or deleted.
--
-- How to run (a database administrator, not the application):
--   * Back up the database first.
--   * Use an account with CREATE, REFERENCES, CREATE ROUTINE and ALTER ROUTINE
--     on theotutoring, and INSERT on schemamigrations (for example avnadmin).
--     The application user
--     theotutoring_app_v2 is refused: it must not need, and is not assumed to
--     have, DDL privileges.
--   * Run the whole file once, in one session, with the mysql command-line
--     client (it uses DELIMITER), connected to theotutoring, and WITHOUT
--     --force, so the first error stops the script:
--       mysql --default-character-set=utf8mb4 --ssl-mode=VERIFY_IDENTITY \
--         --ssl-ca=<path to your ca.pem> -h <host> -P <port> -u <admin user> \
--         -p theotutoring < repair_tutor_availability_override_aiven.sql
--
-- Helper procedures:
--   Every helper procedure this script creates carries the comment
--   'Helper of repair_tutor_availability_override_aiven.sql; safe to drop.'
--   and its name starts with repair_override_. Before dropping any leftover
--   helper, the guard procedure repair_override_aiven_guard checks
--   information_schema.ROUTINES and stops if a procedure with a helper name
--   exists without exactly that comment (an empty or NULL comment counts as
--   not matching), so a routine this script cannot identify as its own is
--   never dropped.
--   If the guard itself already exists (left by a run that stopped at the
--   guard), CREATE PROCEDURE fails with "PROCEDURE
--   repair_override_aiven_guard already exists". Inspect it first:
--     SELECT ROUTINE_NAME, ROUTINE_COMMENT, CREATED, DEFINER
--     FROM information_schema.ROUTINES
--     WHERE ROUTINE_SCHEMA = 'theotutoring'
--       AND ROUTINE_NAME LIKE 'repair\_override\_%';
--   and drop it by hand only if its comment is the one above.
--
-- Failure and retry:
--   MySQL DDL commits implicitly and cannot be rolled back. The ledger row is
--   only written after the table is verified, so a failed run never records
--   the migration. After any error, do not blindly rerun: read the error,
--   inspect the table with the verification queries at the end of this file,
--   and fix the cause. A rerun skips a table that exists and matches the
--   expected definition, and stops if it differs. Helper procedures left
--   behind by a failed run are dropped by the next run, once the guard has
--   confirmed they belong to this script.
--
-- Manual preflight (read-only) before running, if wanted:
--   SELECT DATABASE(), CURRENT_USER(), VERSION(), @@lower_case_table_names;
--   SHOW CREATE TABLE tutorprofile;
--   SELECT Version, AppliedAt FROM schemamigrations ORDER BY Version;
--   SHOW TABLES LIKE 'tutavailabilityoverride';
--
-- information_schema views (TABLES, COLUMNS, ...) are system views whose names
-- are not case-sensitive; every application table below is lowercase.
-- COLUMN_DEFAULT is NULL for both an omitted default and DEFAULT NULL; MySQL
-- metadata cannot distinguish their original syntax.
-- Older MySQL 8.0 versions may report signed INT as int(11).

USE theotutoring;

DELIMITER $$

-- Runs before anything is dropped. Stops if this is not theotutoring, or if a
-- procedure with one of this script's helper names exists without exactly
-- this script's marker comment. The NULL-safe comparison (<=>) treats a NULL
-- comment as not matching, so it can never let an unidentified procedure
-- through. No IF EXISTS drop precedes this CREATE, so an existing guard is
-- never dropped blindly either.
CREATE PROCEDURE repair_override_aiven_guard()
    COMMENT 'Helper of repair_tutor_availability_override_aiven.sql; safe to drop.'
BEGIN
    DECLARE conflict VARCHAR(64) DEFAULT NULL;
    DECLARE message VARCHAR(128);
    IF DATABASE() IS NULL OR DATABASE() <> 'theotutoring' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Connect to the theotutoring database first.';
    END IF;
    SELECT ROUTINE_NAME INTO conflict
    FROM information_schema.ROUTINES
    WHERE ROUTINE_SCHEMA = DATABASE()
      AND ROUTINE_TYPE = 'PROCEDURE'
      AND ROUTINE_NAME IN ('repair_override_preflight',
                           'repair_override_check_table',
                           'repair_override_apply',
                           'repair_override_record')
      AND NOT (ROUTINE_COMMENT <=>
               'Helper of repair_tutor_availability_override_aiven.sql; safe to drop.')
    ORDER BY ROUTINE_NAME
    LIMIT 1;
    IF conflict IS NOT NULL THEN
        SET message = CONCAT('Procedure ', conflict,
                             ' exists and is not from this script; inspect it first.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = message;
    END IF;
END$$

DELIMITER ;

CALL repair_override_aiven_guard();

-- Only procedures confirmed by the guard to be this script's leftovers (or
-- absent) can be dropped here.
DROP PROCEDURE IF EXISTS repair_override_preflight;
DROP PROCEDURE IF EXISTS repair_override_check_table;
DROP PROCEDURE IF EXISTS repair_override_apply;
DROP PROCEDURE IF EXISTS repair_override_record;
DROP PROCEDURE repair_override_aiven_guard;

DELIMITER $$

-- Stops unless this is the expected database, account, server and starting
-- state. Changes nothing.
CREATE PROCEDURE repair_override_preflight()
    COMMENT 'Helper of repair_tutor_availability_override_aiven.sql; safe to drop.'
BEGIN
    IF DATABASE() IS NULL OR DATABASE() <> 'theotutoring' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Connect to the theotutoring database first.';
    END IF;
    IF SUBSTRING_INDEX(CURRENT_USER(), '@', 1) = 'theotutoring_app_v2' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Run as the database administrator, not the application user.';
    END IF;
    IF @@lower_case_table_names <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Expected lower_case_table_names = 0 (Aiven).';
    END IF;
    -- The CHECK constraint is only enforced from MySQL 8.0.16.
    IF CAST(SUBSTRING_INDEX(VERSION(), '.', 1) AS UNSIGNED) < 8
       OR (VERSION() LIKE '8.0.%'
           AND CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(VERSION(), '-', 1), '.', -1)
                    AS UNSIGNED) < 16) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'MySQL 8.0.16 or later is required.';
    END IF;

    -- tutorprofile: InnoDB, signed INT primary key TutorID.
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'tutorprofile'
          AND ENGINE = 'InnoDB'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'InnoDB table tutorprofile not found.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'tutorprofile'
          AND COLUMN_NAME = 'TutorID'
          AND COLUMN_TYPE IN ('int', 'int(11)')
          AND IS_NULLABLE = 'NO'
          AND COLUMN_KEY = 'PRI'
    ) OR (SELECT COUNT(*) FROM information_schema.COLUMNS
          WHERE TABLE_SCHEMA = DATABASE()
            AND CAST(TABLE_NAME AS BINARY) = 'tutorprofile'
            AND COLUMN_KEY = 'PRI') <> 1
      OR (SELECT COUNT(*) FROM information_schema.STATISTICS
          WHERE TABLE_SCHEMA = DATABASE()
            AND CAST(TABLE_NAME AS BINARY) = 'tutorprofile'
            AND INDEX_NAME = 'PRIMARY') <> 1
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'tutorprofile.TutorID is not the sole signed INT NOT NULL primary key.';
    END IF;

    -- schemamigrations: Version primary key and AppliedAt.
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'schemamigrations'
          AND COLUMN_NAME = 'Version'
          AND COLUMN_KEY = 'PRI'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'schemamigrations'
          AND COLUMN_NAME = 'AppliedAt'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'schemamigrations (Version primary key, AppliedAt) not found.';
    END IF;

    -- A differently-cased copy of the table must be inspected by hand.
    IF EXISTS (
        SELECT 1 FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND LOWER(TABLE_NAME) = 'tutavailabilityoverride'
          AND CAST(TABLE_NAME AS BINARY) <> 'tutavailabilityoverride'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A differently-cased TutAvailabilityOverride table exists; inspect it first.';
    END IF;

    -- Constraint names are unique per database: neither may belong to
    -- another table.
    IF EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CONSTRAINT_NAME IN ('chk_override_times', 'fk_override_tutor')
          AND CAST(TABLE_NAME AS BINARY) <> 'tutavailabilityoverride'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'chk_override_times or fk_override_tutor is used by another table.';
    END IF;

    -- An existing table must match 007 exactly; it is never altered here.
    IF EXISTS (
        SELECT 1 FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'tutavailabilityoverride'
    ) THEN
        CALL repair_override_check_table();
    END IF;
END$$

-- tutavailabilityoverride: exactly the columns, keys, check and index of
-- 007_tutor_availability_override.sql.
CREATE PROCEDURE repair_override_check_table()
    COMMENT 'Helper of repair_tutor_availability_override_aiven.sql; safe to drop.'
BEGIN
    DECLARE clause LONGTEXT DEFAULT NULL;
    DECLARE normalized_clause LONGTEXT DEFAULT NULL;
    DECLARE previous_clause LONGTEXT DEFAULT NULL;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'tutavailabilityoverride'
          AND ENGINE = 'InnoDB'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'InnoDB table tutavailabilityoverride not found.';
    END IF;

    IF (SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'tutavailabilityoverride') <> 5
       OR (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND CAST(TABLE_NAME AS BINARY) = 'tutavailabilityoverride'
             AND COLUMN_KEY = 'PRI') <> 1
       OR (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND CAST(TABLE_NAME AS BINARY) = 'tutavailabilityoverride'
             AND COLUMN_DEFAULT IS NULL
             AND GENERATION_EXPRESSION = ''
             AND ((CAST(COLUMN_NAME AS BINARY) = 'OverrideID'
                   AND ORDINAL_POSITION = 1 AND COLUMN_TYPE IN ('int', 'int(11)')
                   AND IS_NULLABLE = 'NO' AND COLUMN_KEY = 'PRI'
                   AND EXTRA = 'auto_increment')
               OR (EXTRA = '' AND (
                    (CAST(COLUMN_NAME AS BINARY) = 'TutorID'
                     AND ORDINAL_POSITION = 2 AND COLUMN_TYPE IN ('int', 'int(11)')
                     AND IS_NULLABLE = 'NO')
                 OR (CAST(COLUMN_NAME AS BINARY) = 'Date'
                     AND ORDINAL_POSITION = 3 AND COLUMN_TYPE = 'date'
                     AND IS_NULLABLE = 'NO')
                 OR (CAST(COLUMN_NAME AS BINARY) = 'StartTime'
                     AND ORDINAL_POSITION = 4 AND COLUMN_TYPE = 'time'
                     AND IS_NULLABLE = 'YES')
                 OR (CAST(COLUMN_NAME AS BINARY) = 'EndTime'
                     AND ORDINAL_POSITION = 5 AND COLUMN_TYPE = 'time'
                     AND IS_NULLABLE = 'YES'))))) <> 5
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'tutavailabilityoverride columns differ from 007.';
    END IF;

    -- Exactly one foreign key on the table, named fk_override_tutor, with
    -- exactly one column mapping: TutorID to tutorprofile(TutorID), no
    -- cascading. A composite key has more than one KEY_COLUMN_USAGE row for
    -- the constraint and is rejected.
    IF (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'tutavailabilityoverride'
          AND CONSTRAINT_TYPE = 'FOREIGN KEY') <> 1
       OR (SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE
           WHERE CONSTRAINT_SCHEMA = DATABASE()
             AND TABLE_SCHEMA = DATABASE()
             AND CAST(TABLE_NAME AS BINARY) = 'tutavailabilityoverride'
             AND CONSTRAINT_NAME = 'fk_override_tutor') <> 1
       OR NOT EXISTS (
           SELECT 1
           FROM information_schema.KEY_COLUMN_USAGE k
           JOIN information_schema.REFERENTIAL_CONSTRAINTS r
             ON r.CONSTRAINT_SCHEMA = k.CONSTRAINT_SCHEMA
            AND r.CONSTRAINT_NAME = k.CONSTRAINT_NAME
           WHERE k.CONSTRAINT_SCHEMA = DATABASE()
             AND k.TABLE_SCHEMA = DATABASE()
             AND CAST(k.TABLE_NAME AS BINARY) = 'tutavailabilityoverride'
             AND k.CONSTRAINT_NAME = 'fk_override_tutor'
             AND k.COLUMN_NAME = 'TutorID'
             AND k.ORDINAL_POSITION = 1
             AND k.POSITION_IN_UNIQUE_CONSTRAINT = 1
             AND k.REFERENCED_TABLE_SCHEMA = DATABASE()
             AND CAST(k.REFERENCED_TABLE_NAME AS BINARY) = 'tutorprofile'
             AND k.REFERENCED_COLUMN_NAME = 'TutorID'
             AND CAST(r.TABLE_NAME AS BINARY) = 'tutavailabilityoverride'
             AND CAST(r.REFERENCED_TABLE_NAME AS BINARY) = 'tutorprofile'
             AND r.UPDATE_RULE IN ('RESTRICT', 'NO ACTION')
             AND r.DELETE_RULE IN ('RESTRICT', 'NO ACTION'))
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'fk_override_tutor differs from 007.';
    END IF;

    -- The explicit (TutorID, Date) index also supports the foreign key.
    IF (SELECT COUNT(*) FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'tutavailabilityoverride') <> 3
       OR (SELECT COUNT(*) FROM information_schema.STATISTICS
           WHERE TABLE_SCHEMA = DATABASE()
             AND CAST(TABLE_NAME AS BINARY) = 'tutavailabilityoverride'
             AND INDEX_TYPE = 'BTREE'
             AND IS_VISIBLE = 'YES'
             AND SUB_PART IS NULL
             AND EXPRESSION IS NULL
             AND COLLATION = 'A'
             AND ((CAST(INDEX_NAME AS BINARY) = 'PRIMARY' AND NON_UNIQUE = 0
                   AND SEQ_IN_INDEX = 1 AND CAST(COLUMN_NAME AS BINARY) = 'OverrideID')
               OR (CAST(INDEX_NAME AS BINARY) = 'idx_override_tutor_date' AND NON_UNIQUE = 1
                   AND ((SEQ_IN_INDEX = 1 AND CAST(COLUMN_NAME AS BINARY) = 'TutorID')
                     OR (SEQ_IN_INDEX = 2 AND CAST(COLUMN_NAME AS BINARY) = 'Date'))))) <> 3
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'tutavailabilityoverride indexes differ from 007.';
    END IF;

    IF (SELECT COUNT(*) FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'tutavailabilityoverride'
          AND INDEX_NAME = 'idx_override_tutor_date') <> 2
       OR (SELECT COUNT(*) FROM information_schema.STATISTICS
           WHERE TABLE_SCHEMA = DATABASE()
             AND CAST(TABLE_NAME AS BINARY) = 'tutavailabilityoverride'
             AND INDEX_NAME = 'idx_override_tutor_date'
             AND NON_UNIQUE = 1
             AND ((SEQ_IN_INDEX = 1 AND COLUMN_NAME = 'TutorID')
               OR (SEQ_IN_INDEX = 2 AND COLUMN_NAME = 'Date'))) <> 2
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'idx_override_tutor_date differs from 007.';
    END IF;

    -- Remove whitespace, identifier quotes and redundant parentheses only
    -- around complete expected subexpressions, preserving logical grouping.
    IF (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'tutavailabilityoverride'
          AND CONSTRAINT_TYPE = 'CHECK') <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'tutavailabilityoverride CHECK constraints differ from 007.';
    END IF;
    SELECT cc.CHECK_CLAUSE INTO clause
    FROM information_schema.CHECK_CONSTRAINTS cc
    JOIN information_schema.TABLE_CONSTRAINTS tc
      ON tc.CONSTRAINT_SCHEMA = cc.CONSTRAINT_SCHEMA
     AND tc.CONSTRAINT_NAME = cc.CONSTRAINT_NAME
    WHERE cc.CONSTRAINT_SCHEMA = DATABASE()
      AND cc.CONSTRAINT_NAME = 'chk_override_times'
      AND CAST(tc.TABLE_NAME AS BINARY) = 'tutavailabilityoverride'
      AND tc.CONSTRAINT_TYPE = 'CHECK'
      AND tc.ENFORCED = 'YES';
    SET normalized_clause = LOWER(REGEXP_REPLACE(REPLACE(clause, '`', ''), '[[:space:]]+', ''));
    normalization: LOOP
        SET previous_clause = normalized_clause;
        SET normalized_clause = REPLACE(normalized_clause, '(starttimeisnull)', 'starttimeisnull');
        SET normalized_clause = REPLACE(normalized_clause, '(endtimeisnull)', 'endtimeisnull');
        SET normalized_clause = REPLACE(normalized_clause, '(starttime<endtime)', 'starttime<endtime');
        SET normalized_clause = REPLACE(normalized_clause,
            '(starttimeisnullandendtimeisnull)', 'starttimeisnullandendtimeisnull');
        SET normalized_clause = REPLACE(normalized_clause,
            '(starttimeisnullandendtimeisnullorstarttime<endtime)',
            'starttimeisnullandendtimeisnullorstarttime<endtime');
        IF normalized_clause <=> previous_clause THEN
            LEAVE normalization;
        END IF;
    END LOOP;
    IF clause IS NULL
       OR CAST(normalized_clause AS BINARY)
          <> 'starttimeisnullandendtimeisnullorstarttime<endtime' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'chk_override_times is missing, not enforced or differs from 007.';
    END IF;
END$$

-- Creates the table if missing, then verifies it.
CREATE PROCEDURE repair_override_apply()
    COMMENT 'Helper of repair_tutor_availability_override_aiven.sql; safe to drop.'
BEGIN
    CALL repair_override_preflight();

    -- Same definition as 007_tutor_availability_override.sql, with lowercase
    -- table names and InnoDB (the default engine) stated explicitly. An
    -- existing table was already verified by the preflight.
    CREATE TABLE IF NOT EXISTS tutavailabilityoverride (
        OverrideID INT AUTO_INCREMENT PRIMARY KEY,
        TutorID INT NOT NULL,
        `Date` DATE NOT NULL,
        StartTime TIME NULL,
        EndTime TIME NULL,

        CONSTRAINT chk_override_times CHECK (
            (StartTime IS NULL AND EndTime IS NULL) OR StartTime < EndTime
        ),

        CONSTRAINT fk_override_tutor
            FOREIGN KEY (TutorID) REFERENCES tutorprofile(TutorID),

        INDEX idx_override_tutor_date (TutorID, `Date`)
    ) ENGINE=InnoDB;
    CALL repair_override_check_table();
END$$

-- Writes the ledger row last, and only after the table is verified.
CREATE PROCEDURE repair_override_record()
    COMMENT 'Helper of repair_tutor_availability_override_aiven.sql; safe to drop.'
BEGIN
    CALL repair_override_preflight();
    CALL repair_override_check_table();
    IF NOT EXISTS (
        SELECT 1 FROM schemamigrations
        WHERE Version = '007_tutor_availability_override'
    ) THEN
        INSERT INTO schemamigrations (Version, AppliedAt)
        VALUES ('007_tutor_availability_override', CURRENT_TIMESTAMP(6));
    END IF;
END$$

DELIMITER ;

-- 1. Preflight (changes nothing).
CALL repair_override_preflight();

-- 2. tutavailabilityoverride, if missing.
CALL repair_override_apply();

-- 3. Verify, then record the migration (last).
CALL repair_override_record();

-- Cleanup: these procedures were all created by this run.
DROP PROCEDURE IF EXISTS repair_override_record;
DROP PROCEDURE IF EXISTS repair_override_apply;
DROP PROCEDURE IF EXISTS repair_override_check_table;
DROP PROCEDURE IF EXISTS repair_override_preflight;

-- 4. Post-execution verification (read-only; also safe to run on their own).
SELECT Version, AppliedAt FROM schemamigrations
WHERE Version = '007_tutor_availability_override';
SHOW CREATE TABLE tutavailabilityoverride;
SELECT tc.CONSTRAINT_NAME, tc.CONSTRAINT_TYPE, tc.ENFORCED, cc.CHECK_CLAUSE
FROM information_schema.TABLE_CONSTRAINTS tc
LEFT JOIN information_schema.CHECK_CONSTRAINTS cc
  ON cc.CONSTRAINT_SCHEMA = tc.CONSTRAINT_SCHEMA
 AND cc.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
WHERE tc.CONSTRAINT_SCHEMA = DATABASE()
  AND tc.TABLE_NAME = 'tutavailabilityoverride'
ORDER BY tc.CONSTRAINT_NAME;
SELECT COUNT(*) AS override_rows FROM tutavailabilityoverride;
