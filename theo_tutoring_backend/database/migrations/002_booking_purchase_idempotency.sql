USE theotutoring;

-- Additive follow-up: preserve existing purchases by leaving historical
-- idempotency values NULL. New purchase writes must always supply both values.
DROP PROCEDURE IF EXISTS apply_002_booking_purchase_idempotency;
DELIMITER $$

CREATE PROCEDURE apply_002_booking_purchase_idempotency()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'BookingPurchase'
          AND COLUMN_NAME = 'IdempotencyKey'
    ) THEN
        ALTER TABLE BookingPurchase
            ADD COLUMN IdempotencyKey VARCHAR(128)
                CHARACTER SET ascii COLLATE ascii_bin NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'BookingPurchase'
          AND COLUMN_NAME = 'RequestFingerprint'
    ) THEN
        ALTER TABLE BookingPurchase
            ADD COLUMN RequestFingerprint CHAR(64)
                CHARACTER SET ascii COLLATE ascii_bin NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE()
          AND TABLE_NAME = 'BookingPurchase'
          AND CONSTRAINT_NAME = 'chk_purchase_idempotency_fields'
    ) THEN
        ALTER TABLE BookingPurchase
            ADD CONSTRAINT chk_purchase_idempotency_fields
            CHECK (
                (IdempotencyKey IS NULL AND RequestFingerprint IS NULL)
                OR (IdempotencyKey IS NOT NULL
                    AND RequestFingerprint IS NOT NULL)
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'BookingPurchase'
          AND INDEX_NAME = 'uq_purchase_student_idempotency'
    ) THEN
        ALTER TABLE BookingPurchase
            ADD UNIQUE KEY uq_purchase_student_idempotency
                (StudentID, IdempotencyKey);
    END IF;
END$$

DELIMITER ;

CALL apply_002_booking_purchase_idempotency();
DROP PROCEDURE IF EXISTS apply_002_booking_purchase_idempotency;

INSERT IGNORE INTO SchemaMigrations (Version)
VALUES ('002_booking_purchase_idempotency')
