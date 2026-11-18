-- Runs against the database selected when connecting, for example:
--   mysql --default-character-set=utf8mb4 -u USER -p theotutoring_test < 013_payout_payment_tracking.sql
--
-- Table names are case-sensitive on the server (lower_case_table_names = 0):
-- every table is named exactly as it physically exists (bookingpurchase,
-- payout, admin, platformsettings, schemamigrations), and the new table is
-- lowercase too, matching the backend's queries.
--
-- Additive: tutor payout tracking (lib/admin_payouts.dart,
-- lib/payout_finance.dart). Nothing is dropped, renamed or narrowed, and no
-- existing payout, refund or payment value is changed.
--
-- 1. bookingpurchase.CommissionPercentage / CommissionSource
--    The platform commission rate captured when the student buys, so a later
--    change to platformsettings.CommissionPercentage never changes what an
--    existing purchase's lessons pay the tutor.
--      'Purchase'   captured by the backend at purchase time.
--      'Backfilled' set by this migration, ONLY where the evidence below
--                   shows the current rate was already in force.
--      'Manual'     recorded by an administrator for a purchase this
--                   migration could not resolve (see the README).
--      NULL         unresolved: no rate is invented. The Payouts page lists
--                   these lessons (missing_commission_rate) and payout
--                   generation skips them.
--
--    Evidence-based backfill. No purchase-time rate was ever stored, and the
--    settings row keeps no history: only its current CommissionPercentage
--    and UpdatedAt, which changes whenever the row changes (ON UPDATE
--    CURRENT_TIMESTAMP; the backend also sets it explicitly). So the current
--    rate is known to have applied to a purchase only if the purchase was
--    created AFTER UpdatedAt. Such purchases (with one second of margin) are
--    backfilled and marked 'Backfilled'; every earlier purchase stays NULL.
--
--    Time zones: UpdatedAt is a server-local DATETIME; CreatedAtUtc is UTC.
--    The conversion uses, in order:
--      a) @theo_013_settings_utc_offset, if the operator sets it before
--         running this file, as a fixed offset such as '+00:00' or '+02:00'
--         (named zones are not accepted: they need time-zone tables and do
--         not convert dates outside the TIMESTAMP range). An invalid value
--         means "unknown" and nothing is backfilled.
--      b) otherwise the session time zone, but only when it equals the
--         server's global time zone (the backend never changes its session
--         zone, so that is the zone UpdatedAt was written in).
--    If neither applies, or the conversion gives NULL or 0, nothing is
--    backfilled. Residual assumption, stated not hidden: the server's global
--    time zone has not changed since UpdatedAt was written.
--
-- 2. payout.PaidByAdminID / PaymentReference
--    Who marked the payout as paid and the optional external payment
--    reference (up to 100 characters). payout.AdminID stays the approver.
--
-- 3. payoutadminaction
--    Audit trail: one row per Generated / Approved / Paid step, written in
--    the same transaction as the step, with the admin, the net amount and
--    (for Paid) the reference. uq_payout_action_once makes a repeated step
--    impossible even outside the application. Rows are never updated or
--    deleted.
--
-- Safe to run again. Every column, constraint, index and the table is checked
-- individually in information_schema: a missing one is added, a correct one
-- is left alone, and one that exists with an unexpected definition stops the
-- migration with an error (SQLSTATE 45000) naming it, instead of being
-- silently skipped. (DDL is atomic per statement, so a failed run can leave
-- some objects added; re-running finishes the rest.) The backfill only
-- touches rows whose rate is still NULL, so captured ('Purchase'), manual
-- ('Manual') and earlier backfilled values are never overwritten. The ledger
-- row uses INSERT IGNORE.
--
-- The backfill UPDATE filters on the primary key so it also runs with
-- MySQL Workbench's safe-update mode switched on.

DROP PROCEDURE IF EXISTS apply_013_payout_payment_tracking;
DELIMITER $$

CREATE PROCEDURE apply_013_payout_payment_tracking()
BEGIN
    DECLARE v_type TEXT DEFAULT NULL;
    DECLARE v_nullable VARCHAR(3) DEFAULT NULL;
    DECLARE v_rate DECIMAL(5,2) DEFAULT NULL;
    DECLARE v_updated DATETIME DEFAULT NULL;
    DECLARE v_unix BIGINT DEFAULT NULL;
    DECLARE v_offset VARCHAR(16) DEFAULT NULL;
    DECLARE v_offset_minutes INT DEFAULT NULL;
    DECLARE v_boundary DATETIME(6) DEFAULT NULL;

    -- ---------------------------------------------------- bookingpurchase
    SET v_type = (
        SELECT COLUMN_TYPE FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bookingpurchase'
          AND COLUMN_NAME = 'CommissionPercentage');
    SET v_nullable = (
        SELECT IS_NULLABLE FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bookingpurchase'
          AND COLUMN_NAME = 'CommissionPercentage');
    IF v_type IS NULL THEN
        ALTER TABLE bookingpurchase
            ADD COLUMN CommissionPercentage DECIMAL(5,2) NULL
                AFTER TotalAmount;
    ELSEIF v_type <> 'decimal(5,2)' OR v_nullable <> 'YES' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
            '013: bookingpurchase.CommissionPercentage exists but is not a nullable DECIMAL(5,2); fix it before re-running.';
    END IF;

    SET v_type = (
        SELECT COLUMN_TYPE FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bookingpurchase'
          AND COLUMN_NAME = 'CommissionSource');
    SET v_nullable = (
        SELECT IS_NULLABLE FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bookingpurchase'
          AND COLUMN_NAME = 'CommissionSource');
    IF v_type IS NULL THEN
        ALTER TABLE bookingpurchase
            ADD COLUMN CommissionSource
                ENUM('Purchase', 'Backfilled', 'Manual') NULL
                AFTER CommissionPercentage;
    ELSEIF v_type = 'enum(''Purchase'',''Backfilled'')' AND v_nullable = 'YES' THEN
        -- An earlier draft of this migration: widen it, keeping every value.
        ALTER TABLE bookingpurchase
            MODIFY COLUMN CommissionSource
                ENUM('Purchase', 'Backfilled', 'Manual') NULL;
    ELSEIF v_type <> 'enum(''Purchase'',''Backfilled'',''Manual'')'
        OR v_nullable <> 'YES' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
            '013: bookingpurchase.CommissionSource exists with an unexpected definition; fix it before re-running.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CONSTRAINT_NAME = 'chk_purchase_commission_rate'
    ) THEN
        ALTER TABLE bookingpurchase
            ADD CONSTRAINT chk_purchase_commission_rate CHECK (
                CommissionPercentage IS NULL
                OR CommissionPercentage BETWEEN 0 AND 100
            );
    ELSEIF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CONSTRAINT_NAME = 'chk_purchase_commission_rate'
          AND TABLE_NAME = 'bookingpurchase' AND CONSTRAINT_TYPE = 'CHECK'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
            '013: constraint chk_purchase_commission_rate exists but is not a CHECK on bookingpurchase.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CONSTRAINT_NAME = 'chk_purchase_commission_source'
    ) THEN
        ALTER TABLE bookingpurchase
            ADD CONSTRAINT chk_purchase_commission_source CHECK (
                (CommissionPercentage IS NULL AND CommissionSource IS NULL)
                OR (CommissionPercentage IS NOT NULL
                    AND CommissionSource IS NOT NULL)
            );
    ELSEIF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CONSTRAINT_NAME = 'chk_purchase_commission_source'
          AND TABLE_NAME = 'bookingpurchase' AND CONSTRAINT_TYPE = 'CHECK'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
            '013: constraint chk_purchase_commission_source exists but is not a CHECK on bookingpurchase.';
    END IF;

    -- ---------------------------------------------------- payout
    SET v_type = (
        SELECT COLUMN_TYPE FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'payout'
          AND COLUMN_NAME = 'PaidByAdminID');
    SET v_nullable = (
        SELECT IS_NULLABLE FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'payout'
          AND COLUMN_NAME = 'PaidByAdminID');
    IF v_type IS NULL THEN
        ALTER TABLE payout ADD COLUMN PaidByAdminID INT NULL AFTER PaidAt;
    ELSEIF v_type <> 'int' OR v_nullable <> 'YES' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
            '013: payout.PaidByAdminID exists but is not a nullable INT; fix it before re-running.';
    END IF;

    SET v_type = (
        SELECT COLUMN_TYPE FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'payout'
          AND COLUMN_NAME = 'PaymentReference');
    SET v_nullable = (
        SELECT IS_NULLABLE FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'payout'
          AND COLUMN_NAME = 'PaymentReference');
    IF v_type IS NULL THEN
        ALTER TABLE payout
            ADD COLUMN PaymentReference VARCHAR(100) NULL AFTER PaidByAdminID;
    ELSEIF v_type <> 'varchar(100)' OR v_nullable <> 'YES' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
            '013: payout.PaymentReference exists but is not a nullable VARCHAR(100); fix it before re-running.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CONSTRAINT_NAME = 'fk_payout_paid_by'
    ) THEN
        ALTER TABLE payout
            ADD CONSTRAINT fk_payout_paid_by
                FOREIGN KEY (PaidByAdminID) REFERENCES `admin`(AdminID);
    ELSEIF NOT EXISTS (
        SELECT 1 FROM information_schema.KEY_COLUMN_USAGE
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CONSTRAINT_NAME = 'fk_payout_paid_by'
          AND TABLE_NAME = 'payout' AND COLUMN_NAME = 'PaidByAdminID'
          AND REFERENCED_TABLE_NAME = 'admin'
          AND REFERENCED_COLUMN_NAME = 'AdminID'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
            '013: constraint fk_payout_paid_by exists but is not payout.PaidByAdminID -> admin.AdminID.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CONSTRAINT_NAME = 'chk_payout_paid_by'
    ) THEN
        ALTER TABLE payout
            ADD CONSTRAINT chk_payout_paid_by CHECK (
                PaidByAdminID IS NULL
                OR (Status = 'Paid' AND PaidAt IS NOT NULL)
            );
    ELSEIF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CONSTRAINT_NAME = 'chk_payout_paid_by'
          AND TABLE_NAME = 'payout' AND CONSTRAINT_TYPE = 'CHECK'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
            '013: constraint chk_payout_paid_by exists but is not a CHECK on payout.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CONSTRAINT_NAME = 'chk_payout_reference'
    ) THEN
        ALTER TABLE payout
            ADD CONSTRAINT chk_payout_reference CHECK (
                PaymentReference IS NULL
                OR (Status = 'Paid'
                    AND CHAR_LENGTH(TRIM(PaymentReference)) > 0)
            );
    ELSEIF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND CONSTRAINT_NAME = 'chk_payout_reference'
          AND TABLE_NAME = 'payout' AND CONSTRAINT_TYPE = 'CHECK'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
            '013: constraint chk_payout_reference exists but is not a CHECK on payout.';
    END IF;

    -- ---------------------------------------------------- payoutadminaction
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'payoutadminaction'
    ) THEN
        CREATE TABLE payoutadminaction (
            PayoutAdminActionID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            PayoutID INT NOT NULL,
            AdminID INT NOT NULL,
            Action ENUM('Generated', 'Approved', 'Paid') NOT NULL,
            NetAmount DECIMAL(10,2) NOT NULL,
            PaymentReference VARCHAR(100) NULL,
            CreatedAtUtc DATETIME(6) NOT NULL,

            CONSTRAINT chk_payout_action_amount CHECK (NetAmount >= 0),
            CONSTRAINT chk_payout_action_reference
                CHECK (PaymentReference IS NULL OR Action = 'Paid'),
            CONSTRAINT fk_payout_action_payout
                FOREIGN KEY (PayoutID) REFERENCES payout(PayoutID),
            CONSTRAINT fk_payout_action_admin
                FOREIGN KEY (AdminID) REFERENCES `admin`(AdminID),

            UNIQUE KEY uq_payout_action_once (PayoutID, Action),
            INDEX idx_payout_action_created (CreatedAtUtc)
        ) ENGINE=InnoDB;
    ELSEIF (
        SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'payoutadminaction'
          AND (
            (COLUMN_NAME = 'PayoutAdminActionID'
                AND COLUMN_TYPE = 'bigint unsigned')
            OR (COLUMN_NAME = 'PayoutID' AND COLUMN_TYPE = 'int')
            OR (COLUMN_NAME = 'AdminID' AND COLUMN_TYPE = 'int')
            OR (COLUMN_NAME = 'Action'
                AND COLUMN_TYPE = 'enum(''Generated'',''Approved'',''Paid'')')
            OR (COLUMN_NAME = 'NetAmount' AND COLUMN_TYPE = 'decimal(10,2)')
            OR (COLUMN_NAME = 'PaymentReference'
                AND COLUMN_TYPE = 'varchar(100)')
            OR (COLUMN_NAME = 'CreatedAtUtc'
                AND COLUMN_TYPE = 'datetime(6)')
          )
    ) <> 7
    OR (
        SELECT COUNT(*) FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'payoutadminaction'
          AND INDEX_NAME = 'uq_payout_action_once' AND NON_UNIQUE = 0
          AND COLUMN_NAME IN ('PayoutID', 'Action')
    ) <> 2
    OR (
        SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND TABLE_NAME = 'payoutadminaction'
          AND (
            (CONSTRAINT_NAME = 'fk_payout_action_payout'
                AND REFERENCED_TABLE_NAME = 'payout')
            OR (CONSTRAINT_NAME = 'fk_payout_action_admin'
                AND REFERENCED_TABLE_NAME = 'admin')
          )
    ) <> 2
    OR (
        SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND TABLE_NAME = 'payoutadminaction' AND CONSTRAINT_TYPE = 'CHECK'
          AND CONSTRAINT_NAME IN (
            'chk_payout_action_amount', 'chk_payout_action_reference')
    ) <> 2 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT =
            '013: payoutadminaction exists but its columns, unique key, foreign keys or checks are incomplete; fix it before re-running.';
    END IF;

    -- ---------------------------------------------------- evidence backfill
    SET v_rate = (
        SELECT CommissionPercentage FROM platformsettings WHERE SettingsID = 1);
    SET v_updated = (
        SELECT UpdatedAt FROM platformsettings WHERE SettingsID = 1);
    SET v_offset = @theo_013_settings_utc_offset;

    IF v_updated IS NOT NULL THEN
        IF v_offset IS NOT NULL THEN
            IF v_offset REGEXP '^[+-](0[0-9]|1[0-4]):[0-5][0-9]$' THEN
                SET v_offset_minutes =
                    (CAST(SUBSTRING(v_offset, 2, 2) AS UNSIGNED) * 60
                     + CAST(SUBSTRING(v_offset, 5, 2) AS UNSIGNED))
                    * IF(LEFT(v_offset, 1) = '-', -1, 1);
                -- local = UTC + offset, so UTC = local - offset
                SET v_boundary =
                    TIMESTAMPADD(MINUTE, -v_offset_minutes, v_updated);
            END IF;
        ELSEIF @@session.time_zone = @@global.time_zone THEN
            SET v_unix = UNIX_TIMESTAMP(v_updated);
            IF v_unix IS NOT NULL AND v_unix > 0 THEN
                SET v_boundary =
                    TIMESTAMPADD(SECOND, v_unix, '1970-01-01 00:00:00');
            END IF;
        END IF;
    END IF;

    IF v_rate IS NOT NULL AND v_boundary IS NOT NULL THEN
        UPDATE bookingpurchase
        SET CommissionPercentage = v_rate,
            CommissionSource = 'Backfilled'
        WHERE PurchaseID > 0
          AND CommissionPercentage IS NULL
          AND CommissionSource IS NULL
          AND CreatedAtUtc >= TIMESTAMPADD(SECOND, 1, v_boundary);
    END IF;
END$$

DELIMITER ;

CALL apply_013_payout_payment_tracking();
DROP PROCEDURE IF EXISTS apply_013_payout_payment_tracking;

INSERT IGNORE INTO schemamigrations (Version)
VALUES ('013_payout_payment_tracking');
