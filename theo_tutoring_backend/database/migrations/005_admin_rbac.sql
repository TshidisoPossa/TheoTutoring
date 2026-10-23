USE `theotutoring_test`;

DELIMITER $$

CREATE PROCEDURE assert_test_database()
BEGIN
    IF DATABASE() <> 'theotutoring_test' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Wrong database: expected theotutoring_test';
    END IF;
END$$

DELIMITER ;

CALL assert_test_database();

DROP PROCEDURE assert_test_database;

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
DROP TRIGGER IF EXISTS trg_admin_role_audit_no_update;
DROP TRIGGER IF EXISTS trg_admin_role_audit_no_delete;
DELIMITER $$
CREATE TRIGGER trg_admin_role_audit_no_update
BEFORE UPDATE ON AdminRoleChangeAudit FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Admin role audit rows are immutable'$$
CREATE TRIGGER trg_admin_role_audit_no_delete
BEFORE DELETE ON AdminRoleChangeAudit FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Admin role audit rows are immutable'$$
DELIMITER ;

INSERT IGNORE INTO SchemaMigrations (Version)
VALUES ('20261022_01_admin_rbac');
