-- Runs against the database selected when connecting, for example:
--   mysql --default-character-set=utf8mb4 -u USER -p theotutoring < 005_admin_rbac.sql
DROP PROCEDURE IF EXISTS assert_rbac_target_database;
DELIMITER $$

CREATE PROCEDURE assert_rbac_target_database()
BEGIN
    IF DATABASE() IS NULL
       OR DATABASE() NOT IN ('theotutoring', 'theotutoring_test') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Select theotutoring or theotutoring_test first.';
    END IF;
    -- CREATE TRIGGER IF NOT EXISTS (below) needs MySQL 8.0.29 or later.
    IF CAST(SUBSTRING_INDEX(VERSION(), '.', 1) AS UNSIGNED) < 8
       OR (VERSION() LIKE '8.0.%'
           AND CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(VERSION(), '-', 1), '.', -1)
                    AS UNSIGNED) < 29) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'MySQL 8.0.29 or later is required.';
    END IF;
END$$

DELIMITER ;

CALL assert_rbac_target_database();

DROP PROCEDURE IF EXISTS assert_rbac_target_database;

-- Additive Admin RBAC foundation. Existing Admin rows receive the standard
-- role (preserves current feature access); no account receives super_admin.
CREATE TABLE IF NOT EXISTS SchemaMigrations (
    Version VARCHAR(128) PRIMARY KEY,
    AppliedAt DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;

DROP PROCEDURE IF EXISTS apply_20261022_01_admin_rbac;
DELIMITER $$

CREATE PROCEDURE apply_20261022_01_admin_rbac()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM SchemaMigrations
        WHERE Version = '20261022_01_admin_rbac'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'Admin'
              AND COLUMN_NAME = 'RoleKey'
        ) THEN
            ALTER TABLE Admin
                ADD COLUMN RoleKey VARCHAR(32) NOT NULL DEFAULT 'admin';
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
            WHERE CONSTRAINT_SCHEMA = DATABASE()
              AND TABLE_NAME = 'Admin'
              AND CONSTRAINT_NAME = 'chk_admin_role_key'
        ) THEN
            ALTER TABLE Admin
                ADD CONSTRAINT chk_admin_role_key CHECK (RoleKey IN (
                    'super_admin', 'admin', 'application_reviewer',
                    'finance_admin', 'support_admin', 'monitor_admin'
                ));
        END IF;

        CREATE TABLE IF NOT EXISTS AdminRoleChangeAudit (
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
                FOREIGN KEY (ActorAdminID) REFERENCES Admin(AdminID),
            CONSTRAINT fk_admin_role_audit_target
                FOREIGN KEY (TargetAdminID) REFERENCES Admin(AdminID),
            INDEX idx_admin_role_audit_target (TargetAdminID, ChangedAtUtc)
        ) ENGINE=InnoDB;

    END IF;
END$$

DELIMITER ;

CALL apply_20261022_01_admin_rbac();
DROP PROCEDURE IF EXISTS apply_20261022_01_admin_rbac;

-- Audit records are append-only even if another backend query is added later.
-- IF NOT EXISTS leaves existing triggers in place on reruns, so the audit
-- table is never without them.
DELIMITER $$
CREATE TRIGGER IF NOT EXISTS trg_admin_role_audit_no_update
BEFORE UPDATE ON AdminRoleChangeAudit FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Admin role audit rows are immutable'$$
CREATE TRIGGER IF NOT EXISTS trg_admin_role_audit_no_delete
BEFORE DELETE ON AdminRoleChangeAudit FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Admin role audit rows are immutable'$$
DELIMITER ;

INSERT IGNORE INTO SchemaMigrations (Version)
VALUES ('20261022_01_admin_rbac');
