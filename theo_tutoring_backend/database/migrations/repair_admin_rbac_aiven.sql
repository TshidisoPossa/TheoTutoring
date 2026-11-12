-- Additive repair of migration 005_admin_rbac.sql (ledger version
-- 20261022_01_admin_rbac) for the shared Aiven MySQL database `theotutoring`,
-- where table names are case-sensitive (lower_case_table_names = 0) and
-- lowercase. 005_admin_rbac.sql remains the source of truth for the RBAC
-- definitions; this script only adds what is missing:
--   * the chk_admin_role_key check on admin.RoleKey (the column already exists
--     and is not recreated or altered),
--   * the append-only adminrolechangeaudit table,
--   * the trg_admin_role_audit_no_update / trg_admin_role_audit_no_delete
--     triggers,
--   * the 20261022_01_admin_rbac ledger row, written last and only after every
--     object above has been verified.
-- No table is dropped or recreated, and no existing row is inserted, updated
-- or deleted (admin roles stay exactly as they are; no one receives
-- super_admin).
--
-- How to run (a database administrator, not the application):
--   * Back up the database first.
--   * Use an account with ALTER, CREATE, CREATE ROUTINE, ALTER ROUTINE,
--     CREATE TEMPORARY TABLES, REFERENCES and TRIGGER on theotutoring (for
--     example avnadmin). The application user theotutoring_app_v2 is refused:
--     it must not need, and is not assumed to have, DDL privileges.
--   * Aiven runs with binary logging and avnadmin has no SUPER privilege, so
--     CREATE TRIGGER fails (error 1419) unless the service setting
--     log_bin_trust_function_creators is enabled. Changing it is a decision for
--     the service's administrator; this script does not change it.
--   * Run the whole file once, in one session, with the mysql command-line
--     client (it uses DELIMITER), connected to theotutoring, and WITHOUT
--     --force, so the first error stops the script:
--       mysql --default-character-set=utf8mb4 --ssl-mode=VERIFY_IDENTITY \
--         --ssl-ca=<path to your ca.pem> -h <host> -P <port> -u <admin user> \
--         -p theotutoring < repair_admin_rbac_aiven.sql
--
-- Helper procedures:
--   Every helper procedure this script creates carries the comment
--   'Helper of repair_admin_rbac_aiven.sql; safe to drop.' and its name starts
--   with repair_rbac_. Before dropping any leftover helper, the guard
--   procedure repair_rbac_aiven_guard checks information_schema.ROUTINES and
--   stops if a procedure with a helper name exists without that comment, so a
--   routine this script cannot identify as its own is never dropped.
--   If the guard itself already exists (left by a run that stopped at the
--   guard), CREATE PROCEDURE fails with "PROCEDURE repair_rbac_aiven_guard
--   already exists". Inspect it first:
--     SELECT ROUTINE_NAME, ROUTINE_COMMENT, CREATED, DEFINER
--     FROM information_schema.ROUTINES
--     WHERE ROUTINE_SCHEMA = 'theotutoring' AND ROUTINE_NAME LIKE 'repair\_rbac\_%';
--   and drop it by hand only if its comment is the one above.
--
-- Failure and retry:
--   MySQL DDL (ALTER TABLE, CREATE TABLE, CREATE TRIGGER) commits implicitly and
--   cannot be rolled back, so a failed run can leave some objects created and
--   others missing. The ledger row is only written after full verification, so
--   a failed run never records the migration. After any error, do not blindly
--   rerun: read the error, inspect the objects with the verification queries at
--   the end of this file, and fix the cause. A rerun skips objects that exist
--   and match the expected definition, and stops if an existing object differs.
--   Helper procedures left behind by a failed run are dropped by the next run,
--   once the guard has confirmed they belong to this script.
--
-- How existing objects are compared with 005_admin_rbac.sql:
--   * Audit columns: names, positions, types, nullability, defaults and EXTRA
--     are checked; generated and invisible columns are rejected. MySQL reports
--     COLUMN_DEFAULT as NULL both for no default and an explicit DEFAULT NULL.
--   * Foreign keys: each must have exactly one column mapping (a composite key
--     is rejected), with the exact source column, referenced table and column,
--     and RESTRICT / NO ACTION rules.
--   * Audit indexes: PRIMARY, the automatically created actor foreign-key
--     index, and the target index, which also supports the target foreign key.
--   * CHECK constraints: MySQL stores a CHECK as its own canonical printout of
--     the parsed expression (information_schema.CHECK_CONSTRAINTS.CHECK_CLAUSE),
--     not the original text, for example
--       (`RoleKey` in (_utf8mb4'super_admin',_utf8mb4'admin',...))
--     The check is split into its quoted literals, which must equal the
--     intended values exactly (byte for byte, in order), and the remaining
--     structure, in which only formatting is normalized: whitespace is
--     removed, keyword and identifier case is ignored (both are
--     case-insensitive in MySQL), and character-set introducers such as
--     _utf8mb4 are dropped. Parentheses, operators and column names are kept,
--     so a logically different expression does not match. The audit table
--     must have exactly one CHECK constraint.
--   * Triggers: each body must equal the body in 005_admin_rbac.sql exactly
--     (apart from leading and trailing whitespace), as BEFORE ... FOR EACH ROW
--     on adminrolechangeaudit, and the table may have no other triggers.
--   Limitation: these comparisons rely on how MySQL prints CHECK_CLAUSE and
--   stores ACTION_STATEMENT. If a server version formats them differently
--   (for example different parenthesization, or a trigger created with
--   different spacing or keyword case), verification stops with an error
--   rather than accepting the object. Compare SHOW CREATE TABLE / SHOW CREATE
--   TRIGGER with 005_admin_rbac.sql before changing anything.
--
-- Manual preflight (read-only) before running, if wanted:
--   SELECT DATABASE(), CURRENT_USER(), VERSION(), @@lower_case_table_names;
--   SELECT AdminID, UserId, RoleKey FROM admin ORDER BY AdminID;
--   SHOW CREATE TABLE admin;
--   SELECT Version, AppliedAt FROM schemamigrations ORDER BY Version;
--   SHOW TRIGGERS;
--
-- information_schema views (TABLES, COLUMNS, ...) are system views whose names
-- are not case-sensitive; every application table below is lowercase.

USE theotutoring;

DELIMITER $$

-- Runs before anything is dropped. Stops if this is not theotutoring, or if a
-- procedure with one of this script's helper names exists without this
-- script's marker comment. No IF EXISTS drop precedes this CREATE, so an
-- existing guard is never dropped blindly either.
CREATE PROCEDURE repair_rbac_aiven_guard()
    COMMENT 'Helper of repair_admin_rbac_aiven.sql; safe to drop.'
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
      AND ROUTINE_NAME IN ('repair_rbac_preflight',
                           'repair_rbac_snapshot_admin',
                           'repair_rbac_check_expression',
                           'repair_rbac_check_role_check',
                           'repair_rbac_check_audit_table',
                           'repair_rbac_check_triggers',
                           'repair_rbac_apply',
                           'repair_rbac_verify',
                           'repair_rbac_record')
      AND NOT (ROUTINE_COMMENT <=> 'Helper of repair_admin_rbac_aiven.sql; safe to drop.')
    ORDER BY ROUTINE_NAME
    LIMIT 1;
    IF conflict IS NOT NULL THEN
        SET message = CONCAT('Procedure ', conflict,
                             ' exists and is not from this script; inspect it first.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = message;
    END IF;
END$$

DELIMITER ;

CALL repair_rbac_aiven_guard();

-- Only procedures confirmed by the guard to be this script's leftovers (or
-- absent) can be dropped here.
DROP PROCEDURE IF EXISTS repair_rbac_preflight;
DROP PROCEDURE IF EXISTS repair_rbac_snapshot_admin;
DROP PROCEDURE IF EXISTS repair_rbac_check_expression;
DROP PROCEDURE IF EXISTS repair_rbac_check_role_check;
DROP PROCEDURE IF EXISTS repair_rbac_check_audit_table;
DROP PROCEDURE IF EXISTS repair_rbac_check_triggers;
DROP PROCEDURE IF EXISTS repair_rbac_apply;
DROP PROCEDURE IF EXISTS repair_rbac_verify;
DROP PROCEDURE IF EXISTS repair_rbac_record;
DROP PROCEDURE repair_rbac_aiven_guard;

DELIMITER $$

-- Stops unless this is the expected database, account, server and starting
-- state. Changes nothing.
CREATE PROCEDURE repair_rbac_preflight()
    COMMENT 'Helper of repair_admin_rbac_aiven.sql; safe to drop.'
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
    -- CREATE TRIGGER IF NOT EXISTS (below) needs MySQL 8.0.29 or later;
    -- enforced CHECK constraints need 8.0.16 or later.
    IF CAST(SUBSTRING_INDEX(VERSION(), '.', 1) AS UNSIGNED) < 8
       OR (VERSION() LIKE '8.0.%'
           AND CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(VERSION(), '-', 1), '.', -1)
                    AS UNSIGNED) < 29) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'MySQL 8.0.29 or later is required.';
    END IF;

    -- admin: InnoDB, signed INT primary key AdminID, existing RoleKey column.
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'admin'
          AND ENGINE = 'InnoDB'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'InnoDB table admin not found.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'admin'
          AND COLUMN_NAME = 'AdminID'
          AND COLUMN_TYPE = 'int'
          AND COLUMN_KEY = 'PRI'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'admin.AdminID is not a signed INT primary key.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'admin'
          AND COLUMN_NAME = 'RoleKey'
          AND COLUMN_TYPE = 'varchar(32)'
          AND IS_NULLABLE = 'NO'
          AND COLUMN_DEFAULT = 'admin'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'admin.RoleKey is not VARCHAR(32) NOT NULL DEFAULT admin.';
    END IF;
    -- Every existing role must already be one of the six allowed values
    -- (compared exactly), or adding the check would fail. Roles are never
    -- changed here: fix them separately after review.
    IF EXISTS (
        SELECT 1 FROM admin
        WHERE CAST(RoleKey AS BINARY) NOT IN (
            'super_admin', 'admin', 'application_reviewer',
            'finance_admin', 'support_admin', 'monitor_admin'
        )
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'admin has a RoleKey outside the six allowed roles; review it first.';
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

    -- A differently-cased copy of the audit table must be inspected by hand.
    IF EXISTS (
        SELECT 1 FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND LOWER(TABLE_NAME) = 'adminrolechangeaudit'
          AND CAST(TABLE_NAME AS BINARY) <> 'adminrolechangeaudit'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A differently-cased AdminRoleChangeAudit table exists; inspect it first.';
    END IF;

    -- Constraint and trigger names are unique per database: none may belong
    -- to another table.
    IF EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND ((CONSTRAINT_NAME = 'chk_admin_role_key'
                AND CAST(TABLE_NAME AS BINARY) <> 'admin')
            OR (CONSTRAINT_NAME IN ('chk_admin_role_audit_role',
                                    'fk_admin_role_audit_actor',
                                    'fk_admin_role_audit_target')
                AND CAST(TABLE_NAME AS BINARY) <> 'adminrolechangeaudit'))
    ) OR EXISTS (
        SELECT 1 FROM information_schema.TRIGGERS
        WHERE TRIGGER_SCHEMA = DATABASE()
          AND TRIGGER_NAME IN ('trg_admin_role_audit_no_update',
                               'trg_admin_role_audit_no_delete')
          AND CAST(EVENT_OBJECT_TABLE AS BINARY) <> 'adminrolechangeaudit'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'An RBAC constraint or trigger name is used by another table.';
    END IF;

    -- Objects that already exist must match 005_admin_rbac.sql exactly;
    -- they are never altered here.
    IF EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CONSTRAINT_NAME = 'chk_admin_role_key'
    ) THEN
        CALL repair_rbac_check_role_check();
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
    ) THEN
        CALL repair_rbac_check_audit_table();
    END IF;
    CALL repair_rbac_check_triggers(FALSE);
END$$

-- Copies AdminID, UserId and RoleKey of every admin row into a session-only
-- temporary table, so the final verification can compare the rows exactly.
-- Temporary tables are private to this session, are not written to the
-- database, do not commit implicitly, and disappear when the session ends;
-- DROP TEMPORARY TABLE can only drop this session's temporary table.
CREATE PROCEDURE repair_rbac_snapshot_admin()
    COMMENT 'Helper of repair_admin_rbac_aiven.sql; safe to drop.'
BEGIN
    DROP TEMPORARY TABLE IF EXISTS repair_rbac_admin_snapshot;
    CREATE TEMPORARY TABLE repair_rbac_admin_snapshot (
        AdminID INT NOT NULL PRIMARY KEY,
        UserId INT NULL,
        RoleKey VARCHAR(32) NOT NULL
    );
    INSERT INTO repair_rbac_admin_snapshot (AdminID, UserId, RoleKey)
    SELECT AdminID, UserId, RoleKey FROM admin;
    SET @repair_rbac_snapshot_taken = 1;
END$$

-- Verifies that p_table has an enforced CHECK named p_constraint whose stored
-- expression equals the intended one:
--   * p_literals: every quoted literal in CHECK_CLAUSE, in order, joined with
--     commas, compared byte for byte;
--   * p_structure: CHECK_CLAUSE with each literal replaced by ?, character-set
--     introducers before a literal (e.g. _utf8mb4) removed, whitespace removed
--     and lowercased. Parentheses, backticks, operators and column names are
--     kept, so only formatting is normalized.
-- A literal containing an escaped quote is not split cleanly by the literal
-- pattern; the result then fails to match, so verification stops instead of
-- accepting it.
CREATE PROCEDURE repair_rbac_check_expression(
    IN p_table VARCHAR(64),
    IN p_constraint VARCHAR(64),
    IN p_structure VARCHAR(255),
    IN p_literals VARCHAR(1024)
)
    COMMENT 'Helper of repair_admin_rbac_aiven.sql; safe to drop.'
BEGIN
    DECLARE clause LONGTEXT DEFAULT NULL;
    DECLARE literal LONGTEXT DEFAULT NULL;
    DECLARE literals LONGTEXT DEFAULT NULL;
    DECLARE structure LONGTEXT DEFAULT NULL;
    DECLARE occurrence INT DEFAULT 1;
    DECLARE message VARCHAR(128);

    SELECT cc.CHECK_CLAUSE INTO clause
    FROM information_schema.CHECK_CONSTRAINTS cc
    JOIN information_schema.TABLE_CONSTRAINTS tc
      ON tc.CONSTRAINT_SCHEMA = cc.CONSTRAINT_SCHEMA
     AND tc.CONSTRAINT_NAME = cc.CONSTRAINT_NAME
    WHERE cc.CONSTRAINT_SCHEMA = DATABASE()
      AND cc.CONSTRAINT_NAME = p_constraint
      AND CAST(tc.TABLE_NAME AS BINARY) = CAST(p_table AS BINARY)
      AND tc.CONSTRAINT_TYPE = 'CHECK'
      AND tc.ENFORCED = 'YES';

    IF clause IS NOT NULL THEN
        literal_loop: LOOP
            IF occurrence > 64 THEN
                LEAVE literal_loop;
            END IF;
            SET literal = REGEXP_SUBSTR(clause, '''[^'']*''', 1, occurrence);
            IF literal IS NULL THEN
                LEAVE literal_loop;
            END IF;
            SET literals = IF(literals IS NULL, literal,
                              CONCAT(literals, ',', literal));
            SET occurrence = occurrence + 1;
        END LOOP;
        SET structure = LOWER(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(clause, '''[^'']*''', '?'),
                    '_[A-Za-z0-9]+[?]', '?'),
                '[[:space:]]+', ''));
    END IF;

    IF clause IS NULL
       OR literals IS NULL
       OR CAST(literals AS BINARY) <> CAST(p_literals AS BINARY)
       OR CAST(structure AS BINARY) <> CAST(p_structure AS BINARY) THEN
        SET message = CONCAT(p_constraint,
                             ' is missing, not enforced or differs from 005_admin_rbac.sql.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = message;
    END IF;
END$$

-- chk_admin_role_key: an enforced CHECK on admin equal to
-- RoleKey IN ('super_admin', 'admin', 'application_reviewer',
--             'finance_admin', 'support_admin', 'monitor_admin').
CREATE PROCEDURE repair_rbac_check_role_check()
    COMMENT 'Helper of repair_admin_rbac_aiven.sql; safe to drop.'
BEGIN
    CALL repair_rbac_check_expression(
        'admin',
        'chk_admin_role_key',
        '(`rolekey`in(?,?,?,?,?,?))',
        CONCAT('''super_admin'',''admin'',''application_reviewer'',',
               '''finance_admin'',''support_admin'',''monitor_admin'''));
END$$

-- adminrolechangeaudit: exactly the columns, keys, check and index of
-- 005_admin_rbac.sql.
CREATE PROCEDURE repair_rbac_check_audit_table()
    COMMENT 'Helper of repair_admin_rbac_aiven.sql; safe to drop.'
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
          AND ENGINE = 'InnoDB'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'InnoDB table adminrolechangeaudit not found.';
    END IF;

    IF (SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'adminrolechangeaudit') <> 7
       OR (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND CAST(TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
             AND COLUMN_KEY = 'PRI') <> 1
       OR (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND CAST(TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
             AND IS_NULLABLE = 'NO'
             AND COLUMN_DEFAULT IS NULL
             AND GENERATION_EXPRESSION = ''
             AND ((CAST(COLUMN_NAME AS BINARY) = 'AdminRoleChangeAuditID'
                   AND ORDINAL_POSITION = 1
                   AND COLUMN_TYPE = 'bigint unsigned'
                   AND COLUMN_KEY = 'PRI'
                   AND EXTRA = 'auto_increment')
               OR (EXTRA = '' AND (
                    (CAST(COLUMN_NAME AS BINARY) = 'ActorAdminID'
                     AND ORDINAL_POSITION = 2 AND COLUMN_TYPE = 'int')
                 OR (CAST(COLUMN_NAME AS BINARY) = 'TargetAdminID'
                     AND ORDINAL_POSITION = 3 AND COLUMN_TYPE = 'int')
                 OR (CAST(COLUMN_NAME AS BINARY) = 'PreviousRoleKey'
                     AND ORDINAL_POSITION = 4 AND COLUMN_TYPE = 'varchar(32)')
                 OR (CAST(COLUMN_NAME AS BINARY) = 'NewRoleKey'
                     AND ORDINAL_POSITION = 5 AND COLUMN_TYPE = 'varchar(32)')
                 OR (CAST(COLUMN_NAME AS BINARY) = 'Reason'
                     AND ORDINAL_POSITION = 6 AND COLUMN_TYPE = 'varchar(500)')
                 OR (CAST(COLUMN_NAME AS BINARY) = 'ChangedAtUtc'
                     AND ORDINAL_POSITION = 7 AND COLUMN_TYPE = 'datetime(6)'))))) <> 7
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'adminrolechangeaudit columns differ from 005_admin_rbac.sql.';
    END IF;

    -- Exactly two foreign keys on the table. Each has exactly one column
    -- mapping (a composite key has more than one KEY_COLUMN_USAGE row for
    -- the constraint and is rejected): ActorAdminID / TargetAdminID to
    -- admin(AdminID), with no cascading.
    IF (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
          AND CONSTRAINT_TYPE = 'FOREIGN KEY') <> 2
       OR (SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE
           WHERE CONSTRAINT_SCHEMA = DATABASE()
             AND TABLE_SCHEMA = DATABASE()
             AND CAST(TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
             AND CONSTRAINT_NAME = 'fk_admin_role_audit_actor') <> 1
       OR (SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE
           WHERE CONSTRAINT_SCHEMA = DATABASE()
             AND TABLE_SCHEMA = DATABASE()
             AND CAST(TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
             AND CONSTRAINT_NAME = 'fk_admin_role_audit_target') <> 1
       OR NOT EXISTS (
           SELECT 1
           FROM information_schema.KEY_COLUMN_USAGE k
           JOIN information_schema.REFERENTIAL_CONSTRAINTS r
             ON r.CONSTRAINT_SCHEMA = k.CONSTRAINT_SCHEMA
            AND r.CONSTRAINT_NAME = k.CONSTRAINT_NAME
           WHERE k.CONSTRAINT_SCHEMA = DATABASE()
             AND k.TABLE_SCHEMA = DATABASE()
             AND CAST(k.TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
             AND k.CONSTRAINT_NAME = 'fk_admin_role_audit_actor'
             AND k.COLUMN_NAME = 'ActorAdminID'
             AND k.ORDINAL_POSITION = 1
             AND k.POSITION_IN_UNIQUE_CONSTRAINT = 1
             AND k.REFERENCED_TABLE_SCHEMA = DATABASE()
             AND CAST(k.REFERENCED_TABLE_NAME AS BINARY) = 'admin'
             AND k.REFERENCED_COLUMN_NAME = 'AdminID'
             AND CAST(r.TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
             AND CAST(r.REFERENCED_TABLE_NAME AS BINARY) = 'admin'
             AND r.UPDATE_RULE IN ('RESTRICT', 'NO ACTION')
             AND r.DELETE_RULE IN ('RESTRICT', 'NO ACTION'))
       OR NOT EXISTS (
           SELECT 1
           FROM information_schema.KEY_COLUMN_USAGE k
           JOIN information_schema.REFERENTIAL_CONSTRAINTS r
             ON r.CONSTRAINT_SCHEMA = k.CONSTRAINT_SCHEMA
            AND r.CONSTRAINT_NAME = k.CONSTRAINT_NAME
           WHERE k.CONSTRAINT_SCHEMA = DATABASE()
             AND k.TABLE_SCHEMA = DATABASE()
             AND CAST(k.TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
             AND k.CONSTRAINT_NAME = 'fk_admin_role_audit_target'
             AND k.COLUMN_NAME = 'TargetAdminID'
             AND k.ORDINAL_POSITION = 1
             AND k.POSITION_IN_UNIQUE_CONSTRAINT = 1
             AND k.REFERENCED_TABLE_SCHEMA = DATABASE()
             AND CAST(k.REFERENCED_TABLE_NAME AS BINARY) = 'admin'
             AND k.REFERENCED_COLUMN_NAME = 'AdminID'
             AND CAST(r.TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
             AND CAST(r.REFERENCED_TABLE_NAME AS BINARY) = 'admin'
             AND r.UPDATE_RULE IN ('RESTRICT', 'NO ACTION')
             AND r.DELETE_RULE IN ('RESTRICT', 'NO ACTION'))
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'adminrolechangeaudit foreign keys differ from 005_admin_rbac.sql.';
    END IF;

    -- Four index-column rows: PRIMARY, the actor FK's automatic index, and
    -- the two-column target index (which also supports the target FK).
    IF (SELECT COUNT(*) FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'adminrolechangeaudit') <> 4
       OR (SELECT COUNT(*) FROM information_schema.STATISTICS
           WHERE TABLE_SCHEMA = DATABASE()
             AND CAST(TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
             AND INDEX_TYPE = 'BTREE'
             AND SUB_PART IS NULL
             AND EXPRESSION IS NULL
             AND COLLATION = 'A'
             AND IS_VISIBLE = 'YES'
             AND ((INDEX_NAME = 'PRIMARY' AND NON_UNIQUE = 0
                   AND SEQ_IN_INDEX = 1 AND COLUMN_NAME = 'AdminRoleChangeAuditID')
               OR (INDEX_NAME = 'fk_admin_role_audit_actor' AND NON_UNIQUE = 1
                   AND SEQ_IN_INDEX = 1 AND COLUMN_NAME = 'ActorAdminID')
               OR (INDEX_NAME = 'idx_admin_role_audit_target' AND NON_UNIQUE = 1
                   AND ((SEQ_IN_INDEX = 1 AND COLUMN_NAME = 'TargetAdminID')
                     OR (SEQ_IN_INDEX = 2 AND COLUMN_NAME = 'ChangedAtUtc'))))) <> 4
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'adminrolechangeaudit indexes differ from 005_admin_rbac.sql.';
    END IF;

    IF (SELECT COUNT(*) FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
          AND INDEX_NAME = 'idx_admin_role_audit_target') <> 2
       OR (SELECT COUNT(*) FROM information_schema.STATISTICS
           WHERE TABLE_SCHEMA = DATABASE()
             AND CAST(TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
             AND INDEX_NAME = 'idx_admin_role_audit_target'
             AND NON_UNIQUE = 1
             AND ((SEQ_IN_INDEX = 1 AND COLUMN_NAME = 'TargetAdminID')
               OR (SEQ_IN_INDEX = 2 AND COLUMN_NAME = 'ChangedAtUtc'))) <> 2
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'idx_admin_role_audit_target differs from 005_admin_rbac.sql.';
    END IF;

    -- chk_admin_role_audit_role: an enforced CHECK equal to
    -- PreviousRoleKey IN (six roles) AND NewRoleKey IN (six roles).
    IF (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'adminrolechangeaudit'
          AND CONSTRAINT_TYPE = 'CHECK') <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'adminrolechangeaudit CHECK constraints differ from 005_admin_rbac.sql.';
    END IF;
    CALL repair_rbac_check_expression(
        'adminrolechangeaudit',
        'chk_admin_role_audit_role',
        '((`previousrolekey`in(?,?,?,?,?,?))and(`newrolekey`in(?,?,?,?,?,?)))',
        CONCAT('''super_admin'',''admin'',''application_reviewer'',',
               '''finance_admin'',''support_admin'',''monitor_admin'',',
               '''super_admin'',''admin'',''application_reviewer'',',
               '''finance_admin'',''support_admin'',''monitor_admin'''));
END$$

-- The two append-only triggers. Any that exist must match 005_admin_rbac.sql
-- exactly; the audit table may have no other triggers; with require_both,
-- both must exist.
CREATE PROCEDURE repair_rbac_check_triggers(IN require_both BOOLEAN)
    COMMENT 'Helper of repair_admin_rbac_aiven.sql; safe to drop.'
BEGIN
    -- ACTION_STATEMENT is the trigger body as written. It must equal the
    -- 005_admin_rbac.sql body byte for byte, after removing only leading and
    -- trailing whitespace, so no additional logic is accepted.
    IF EXISTS (
        SELECT 1 FROM information_schema.TRIGGERS
        WHERE TRIGGER_SCHEMA = DATABASE()
          AND TRIGGER_NAME IN ('trg_admin_role_audit_no_update',
                               'trg_admin_role_audit_no_delete')
          AND NOT (
              EVENT_OBJECT_SCHEMA = DATABASE()
              AND CAST(EVENT_OBJECT_TABLE AS BINARY) = 'adminrolechangeaudit'
              AND ACTION_TIMING = 'BEFORE'
              AND ACTION_ORIENTATION = 'ROW'
              AND ACTION_CONDITION IS NULL
              AND ((TRIGGER_NAME = 'trg_admin_role_audit_no_update'
                    AND EVENT_MANIPULATION = 'UPDATE')
                OR (TRIGGER_NAME = 'trg_admin_role_audit_no_delete'
                    AND EVENT_MANIPULATION = 'DELETE'))
              AND CAST(REGEXP_REPLACE(ACTION_STATEMENT,
                                      '^[[:space:]]+|[[:space:]]+$', '')
                       AS BINARY)
                  = CAST('SIGNAL SQLSTATE ''45000'' SET MESSAGE_TEXT = ''Admin role audit rows are immutable'''
                         AS BINARY)
          )
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'An existing RBAC audit trigger differs from 005_admin_rbac.sql.';
    END IF;
    -- Any other trigger on the audit table (for example one that changes
    -- inserted rows) must be inspected by hand; it is never dropped here.
    IF EXISTS (
        SELECT 1 FROM information_schema.TRIGGERS
        WHERE TRIGGER_SCHEMA = DATABASE()
          AND EVENT_OBJECT_SCHEMA = DATABASE()
          AND CAST(EVENT_OBJECT_TABLE AS BINARY) = 'adminrolechangeaudit'
          AND TRIGGER_NAME NOT IN ('trg_admin_role_audit_no_update',
                                   'trg_admin_role_audit_no_delete')
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'adminrolechangeaudit has other triggers; inspect them first.';
    END IF;
    IF require_both AND (
        SELECT COUNT(*) FROM information_schema.TRIGGERS
        WHERE TRIGGER_SCHEMA = DATABASE()
          AND TRIGGER_NAME IN ('trg_admin_role_audit_no_update',
                               'trg_admin_role_audit_no_delete')
    ) <> 2 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Both RBAC audit triggers must exist.';
    END IF;
END$$

-- Adds the check and the audit table if missing, then verifies the table.
CREATE PROCEDURE repair_rbac_apply()
    COMMENT 'Helper of repair_admin_rbac_aiven.sql; safe to drop.'
BEGIN
    CALL repair_rbac_preflight();

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CAST(TABLE_NAME AS BINARY) = 'admin'
          AND CONSTRAINT_NAME = 'chk_admin_role_key'
    ) THEN
        -- Validates the existing rows; adds no column and changes no value.
        ALTER TABLE admin
            ADD CONSTRAINT chk_admin_role_key CHECK (RoleKey IN (
                'super_admin', 'admin', 'application_reviewer',
                'finance_admin', 'support_admin', 'monitor_admin'
            ));
    END IF;
    CALL repair_rbac_check_role_check();

    -- Same definition as 005_admin_rbac.sql, with lowercase table names.
    -- An existing table was already verified by the preflight.
    CREATE TABLE IF NOT EXISTS adminrolechangeaudit (
        AdminRoleChangeAuditID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        ActorAdminID INT NOT NULL,
        TargetAdminID INT NOT NULL,
        PreviousRoleKey VARCHAR(32) NOT NULL,
        NewRoleKey VARCHAR(32) NOT NULL,
        Reason VARCHAR(500) NOT NULL,
        ChangedAtUtc DATETIME(6) NOT NULL,

        CONSTRAINT chk_admin_role_audit_role CHECK (
            PreviousRoleKey IN (
                'super_admin', 'admin', 'application_reviewer',
                'finance_admin', 'support_admin', 'monitor_admin'
            ) AND NewRoleKey IN (
                'super_admin', 'admin', 'application_reviewer',
                'finance_admin', 'support_admin', 'monitor_admin'
            )
        ),
        CONSTRAINT fk_admin_role_audit_actor
            FOREIGN KEY (ActorAdminID) REFERENCES admin(AdminID),
        CONSTRAINT fk_admin_role_audit_target
            FOREIGN KEY (TargetAdminID) REFERENCES admin(AdminID),
        INDEX idx_admin_role_audit_target (TargetAdminID, ChangedAtUtc)
    ) ENGINE=InnoDB;
    CALL repair_rbac_check_audit_table();
END$$

-- Full verification of every RBAC object, and an exact comparison of the
-- admin rows with the snapshot taken before any change.
CREATE PROCEDURE repair_rbac_verify()
    COMMENT 'Helper of repair_admin_rbac_aiven.sql; safe to drop.'
BEGIN
    DECLARE snapshot_rows BIGINT;
    DECLARE admin_rows BIGINT;
    DECLARE unmatched_rows BIGINT;

    IF DATABASE() IS NULL OR DATABASE() <> 'theotutoring' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Connect to the theotutoring database first.';
    END IF;
    CALL repair_rbac_check_role_check();
    CALL repair_rbac_check_audit_table();
    CALL repair_rbac_check_triggers(TRUE);

    -- The snapshot exists only in the session that took it.
    IF @repair_rbac_snapshot_taken IS NULL OR @repair_rbac_snapshot_taken <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No admin snapshot in this session; run the whole file in one session.';
    END IF;
    -- Separate statements: MySQL cannot open one temporary table twice in a
    -- single statement.
    SELECT COUNT(*) INTO snapshot_rows FROM repair_rbac_admin_snapshot;
    SELECT COUNT(*) INTO admin_rows FROM admin;
    SELECT COUNT(*) INTO unmatched_rows
    FROM repair_rbac_admin_snapshot s
    LEFT JOIN admin a
      ON a.AdminID = s.AdminID
     AND a.UserId <=> s.UserId
     AND CAST(a.RoleKey AS BINARY) = CAST(s.RoleKey AS BINARY)
    WHERE a.AdminID IS NULL;
    -- AdminID is unique in both, so equal row counts plus an exact match for
    -- every snapshot row means AdminID, UserId and RoleKey are all unchanged.
    -- Other admin columns, if any, are not compared.
    IF snapshot_rows <> admin_rows OR unmatched_rows <> 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'admin AdminID, UserId or RoleKey values changed since the snapshot.';
    END IF;
END$$

-- Writes the ledger row last, and only after full verification.
CREATE PROCEDURE repair_rbac_record()
    COMMENT 'Helper of repair_admin_rbac_aiven.sql; safe to drop.'
BEGIN
    CALL repair_rbac_verify();
    IF NOT EXISTS (
        SELECT 1 FROM schemamigrations WHERE Version = '20261022_01_admin_rbac'
    ) THEN
        INSERT INTO schemamigrations (Version, AppliedAt)
        VALUES ('20261022_01_admin_rbac', CURRENT_TIMESTAMP(6));
    END IF;
END$$

DELIMITER ;

-- 1. Preflight (changes nothing), then snapshot the admin rows.
CALL repair_rbac_preflight();
CALL repair_rbac_snapshot_admin();

-- 2. chk_admin_role_key and adminrolechangeaudit, if missing.
CALL repair_rbac_apply();

-- 3. Append-only triggers, as in 005_admin_rbac.sql. IF NOT EXISTS keeps an
--    existing trigger (already verified by the preflight) in place, so the
--    audit table is never left without one on a rerun.
DELIMITER $$
CREATE TRIGGER IF NOT EXISTS trg_admin_role_audit_no_update
BEFORE UPDATE ON adminrolechangeaudit FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Admin role audit rows are immutable'$$
CREATE TRIGGER IF NOT EXISTS trg_admin_role_audit_no_delete
BEFORE DELETE ON adminrolechangeaudit FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Admin role audit rows are immutable'$$
DELIMITER ;

-- 4. Verify everything, then record the migration (last).
CALL repair_rbac_record();

-- Cleanup: these procedures were all created by this run.
DROP PROCEDURE IF EXISTS repair_rbac_record;
DROP PROCEDURE IF EXISTS repair_rbac_verify;
DROP PROCEDURE IF EXISTS repair_rbac_apply;
DROP PROCEDURE IF EXISTS repair_rbac_check_triggers;
DROP PROCEDURE IF EXISTS repair_rbac_check_audit_table;
DROP PROCEDURE IF EXISTS repair_rbac_check_role_check;
DROP PROCEDURE IF EXISTS repair_rbac_check_expression;
DROP PROCEDURE IF EXISTS repair_rbac_snapshot_admin;
DROP PROCEDURE IF EXISTS repair_rbac_preflight;
DROP TEMPORARY TABLE IF EXISTS repair_rbac_admin_snapshot;

-- 5. Post-execution verification (read-only; also safe to run on their own).
SELECT Version, AppliedAt FROM schemamigrations
WHERE Version = '20261022_01_admin_rbac';
SELECT AdminID, UserId, RoleKey FROM admin ORDER BY AdminID;
SELECT tc.TABLE_NAME, tc.CONSTRAINT_NAME, tc.CONSTRAINT_TYPE, tc.ENFORCED,
       cc.CHECK_CLAUSE
FROM information_schema.TABLE_CONSTRAINTS tc
LEFT JOIN information_schema.CHECK_CONSTRAINTS cc
  ON cc.CONSTRAINT_SCHEMA = tc.CONSTRAINT_SCHEMA
 AND cc.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
WHERE tc.CONSTRAINT_SCHEMA = DATABASE()
  AND tc.TABLE_NAME IN ('admin', 'adminrolechangeaudit')
ORDER BY tc.TABLE_NAME, tc.CONSTRAINT_NAME;
SHOW CREATE TABLE adminrolechangeaudit;
SELECT TRIGGER_NAME, EVENT_MANIPULATION, ACTION_TIMING, EVENT_OBJECT_TABLE,
       ACTION_STATEMENT, DEFINER
FROM information_schema.TRIGGERS
WHERE TRIGGER_SCHEMA = DATABASE()
  AND TRIGGER_NAME IN ('trg_admin_role_audit_no_update',
                       'trg_admin_role_audit_no_delete');
