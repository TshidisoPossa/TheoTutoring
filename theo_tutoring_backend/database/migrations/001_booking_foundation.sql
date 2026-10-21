USE theotutoring;

-- This migration is additive. Existing Booking, Payment, Refund, and other
-- tables/rows are retained. SchemaMigrations is the manual migration ledger.
CREATE TABLE IF NOT EXISTS SchemaMigrations (
    Version VARCHAR(128) PRIMARY KEY,
    AppliedAt DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;

DROP PROCEDURE IF EXISTS apply_20261019_01_booking_foundation;
DELIMITER $$

CREATE PROCEDURE apply_20261019_01_booking_foundation()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM SchemaMigrations
        WHERE Version = '20261019_01_booking_foundation'
    ) THEN
        CREATE TABLE IF NOT EXISTS BookingPurchase (
            PurchaseID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            StudentID INT NOT NULL,
            TutorID INT NOT NULL,
            SubjectID INT NOT NULL,
            PurchaseType ENUM('Single', 'Package') NOT NULL,
            LessonCount SMALLINT UNSIGNED NOT NULL,
            RatePerLesson DECIMAL(10,2) NOT NULL,
            SubtotalAmount DECIMAL(12,2) NOT NULL,
            DiscountPercent DECIMAL(5,2) NOT NULL DEFAULT 0.00,
            DiscountAmount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
            TotalAmount DECIMAL(12,2) NOT NULL,
            PurchaseStatus ENUM(
                'Draft', 'Held', 'PaymentPending', 'Paid',
                'Cancelled', 'Expired', 'PartiallyRefunded', 'Refunded'
            ) NOT NULL DEFAULT 'Draft',
            CreatedAtUtc DATETIME(6) NOT NULL,

            CONSTRAINT chk_purchase_lesson_count
                CHECK (
                    (PurchaseType = 'Single' AND LessonCount = 1)
                    OR (PurchaseType = 'Package' AND LessonCount >= 2)
                ),
            CONSTRAINT chk_purchase_discount
                CHECK (
                    (PurchaseType = 'Single' AND DiscountPercent = 0)
                    OR (PurchaseType = 'Package' AND LessonCount >= 10
                        AND DiscountPercent = 10)
                    OR (PurchaseType = 'Package' AND LessonCount < 10
                        AND DiscountPercent = 0)
                ),
            CONSTRAINT chk_purchase_amounts
                CHECK (
                    RatePerLesson > 0
                    AND SubtotalAmount = ROUND(RatePerLesson * LessonCount, 2)
                    AND DiscountAmount = ROUND(
                        SubtotalAmount * DiscountPercent / 100, 2
                    )
                    AND TotalAmount = SubtotalAmount - DiscountAmount
                ),
            CONSTRAINT fk_purchase_student
                FOREIGN KEY (StudentID) REFERENCES StudentProfile(StudentID),
            CONSTRAINT fk_purchase_tutor
                FOREIGN KEY (TutorID) REFERENCES TutorProfile(TutorID),
            CONSTRAINT fk_purchase_subject
                FOREIGN KEY (SubjectID) REFERENCES Subjects(subjectId),

            UNIQUE KEY uq_purchase_identity
                (PurchaseID, StudentID, TutorID, SubjectID),
            UNIQUE KEY uq_purchase_tutor (PurchaseID, TutorID),
            UNIQUE KEY uq_purchase_total (PurchaseID, TotalAmount),
            INDEX idx_purchase_student_created (StudentID, CreatedAtUtc),
            INDEX idx_purchase_student_purchases (StudentID, PurchaseID),
            INDEX idx_purchase_tutor_created (TutorID, CreatedAtUtc)
        ) ENGINE=InnoDB;

        CREATE TABLE IF NOT EXISTS PaymentAttempt (
            PaymentAttemptID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            PurchaseID BIGINT UNSIGNED NOT NULL,
            AttemptNumber SMALLINT UNSIGNED NOT NULL,
            IdempotencyKey VARCHAR(128) NOT NULL,
            PaymentMethod ENUM('CreditDebitCard', 'PayPal', 'EFT') NOT NULL,
            PaymentMode ENUM('Demo') NOT NULL DEFAULT 'Demo',
            DemoOutcome ENUM(
                'NotApplicable', 'SimulatedSuccess', 'SimulatedFailure'
            ) NOT NULL DEFAULT 'NotApplicable',
            PaymentStatus ENUM(
                'Pending', 'Successful', 'Failed', 'OutcomeUnknown',
                'ReconciliationRequired', 'Cancelled', 'Refunded'
            ) NOT NULL DEFAULT 'Pending',
            PaymentReference VARCHAR(191) NULL,
            Amount DECIMAL(12,2) NOT NULL,
            FailureCode VARCHAR(64) NULL,
            CreatedAtUtc DATETIME(6) NOT NULL,
            UpdatedAtUtc DATETIME(6) NOT NULL,
            ResolvedAtUtc DATETIME(6) NULL,

            CONSTRAINT chk_payment_attempt_demo_outcome
                CHECK (
                    PaymentMode = 'Demo'
                    AND (
                        (PaymentStatus = 'Successful'
                            AND DemoOutcome = 'SimulatedSuccess')
                        OR (PaymentStatus = 'Failed'
                            AND DemoOutcome = 'SimulatedFailure')
                        OR PaymentStatus NOT IN ('Successful', 'Failed')
                    )
                ),
            CONSTRAINT chk_payment_attempt_amount CHECK (Amount > 0),
            CONSTRAINT fk_payment_attempt_purchase
                FOREIGN KEY (PurchaseID, Amount)
                REFERENCES BookingPurchase(PurchaseID, TotalAmount),

            UNIQUE KEY uq_payment_attempt_idempotency
                (PurchaseID, IdempotencyKey),
            UNIQUE KEY uq_payment_attempt_number (PurchaseID, AttemptNumber),
            UNIQUE KEY uq_payment_attempt_reference (PaymentReference),
            UNIQUE KEY uq_payment_attempt_purchase_identity
                (PurchaseID, PaymentAttemptID),
            INDEX idx_payment_attempt_status (PaymentStatus, CreatedAtUtc)
        ) ENGINE=InnoDB;

        CREATE TABLE IF NOT EXISTS PurchasePayment (
            PurchasePaymentID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            PurchaseID BIGINT UNSIGNED NOT NULL,
            PaymentAttemptID BIGINT UNSIGNED NOT NULL,
            PaymentID INT NULL,
            Amount DECIMAL(12,2) NOT NULL,
            CreatedAtUtc DATETIME(6) NOT NULL,

            CONSTRAINT chk_purchase_payment_amount CHECK (Amount > 0),
            CONSTRAINT fk_purchase_payment_purchase
                FOREIGN KEY (PurchaseID)
                REFERENCES BookingPurchase(PurchaseID),
            CONSTRAINT fk_purchase_payment_attempt
                FOREIGN KEY (PurchaseID, PaymentAttemptID)
                REFERENCES PaymentAttempt(PurchaseID, PaymentAttemptID),
            CONSTRAINT fk_purchase_payment_total
                FOREIGN KEY (PurchaseID, Amount)
                REFERENCES BookingPurchase(PurchaseID, TotalAmount),
            CONSTRAINT fk_purchase_payment_legacy
                FOREIGN KEY (PaymentID) REFERENCES Payment(PaymentID),

            UNIQUE KEY uq_purchase_payment_purchase (PurchaseID),
            UNIQUE KEY uq_purchase_payment_attempt (PaymentAttemptID),
            UNIQUE KEY uq_purchase_payment_legacy (PaymentID),
            INDEX idx_purchase_payment_created (CreatedAtUtc)
        ) ENGINE=InnoDB;

        IF NOT EXISTS (
            SELECT 1 FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'Booking' AND COLUMN_NAME = 'PurchaseID'
        ) THEN
            ALTER TABLE Booking
                ADD COLUMN PurchaseID BIGINT UNSIGNED NULL;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'Booking' AND COLUMN_NAME = 'LessonNumber'
        ) THEN
            ALTER TABLE Booking
                ADD COLUMN LessonNumber SMALLINT UNSIGNED NULL;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'Booking'
              AND COLUMN_NAME = 'LessonPriceAtPurchase'
        ) THEN
            ALTER TABLE Booking
                ADD COLUMN LessonPriceAtPurchase DECIMAL(10,2) NULL;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'Booking'
              AND COLUMN_NAME = 'LinkUpdatedByUserID'
        ) THEN
            ALTER TABLE Booking
                ADD COLUMN LinkUpdatedByUserID INT NULL;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'Booking'
              AND COLUMN_NAME = 'LinkUpdatedAtUtc'
        ) THEN
            ALTER TABLE Booking
                ADD COLUMN LinkUpdatedAtUtc DATETIME(6) NULL;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Booking'
              AND INDEX_NAME = 'uq_booking_purchase_lesson'
        ) THEN
            ALTER TABLE Booking
                ADD UNIQUE KEY uq_booking_purchase_lesson
                    (PurchaseID, LessonNumber);
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
            WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'Booking'
              AND CONSTRAINT_NAME = 'chk_booking_purchase_fields'
        ) THEN
            ALTER TABLE Booking
                ADD CONSTRAINT chk_booking_purchase_fields CHECK (
                    (PurchaseID IS NULL AND LessonNumber IS NULL
                        AND LessonPriceAtPurchase IS NULL)
                    OR (PurchaseID IS NOT NULL AND LessonNumber IS NOT NULL
                        AND LessonPriceAtPurchase IS NOT NULL)
                );
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
            WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'Booking'
              AND CONSTRAINT_NAME = 'chk_booking_lesson_price'
        ) THEN
            ALTER TABLE Booking
                ADD CONSTRAINT chk_booking_lesson_price
                CHECK (
                    LessonPriceAtPurchase IS NULL
                    OR LessonPriceAtPurchase >= 0
                );
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
            WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'Booking'
              AND CONSTRAINT_NAME = 'chk_booking_purchased_lesson_duration'
        ) THEN
            ALTER TABLE Booking
                ADD CONSTRAINT chk_booking_purchased_lesson_duration
                CHECK (
                    PurchaseID IS NULL
                    OR TIMEDIFF(EndTime, StartTime) = '01:00:00'
                );
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
            WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'Booking'
              AND CONSTRAINT_NAME = 'fk_booking_purchase_identity'
        ) THEN
            ALTER TABLE Booking
                ADD CONSTRAINT fk_booking_purchase_identity
                FOREIGN KEY (PurchaseID, StudentID, TutorID, SubjectID)
                REFERENCES BookingPurchase(
                    PurchaseID, StudentID, TutorID, SubjectID
                );
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
            WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'Booking'
              AND CONSTRAINT_NAME = 'fk_booking_link_updated_by'
        ) THEN
            ALTER TABLE Booking
                ADD CONSTRAINT fk_booking_link_updated_by
                FOREIGN KEY (LinkUpdatedByUserID) REFERENCES `User`(UserId);
        END IF;

        CREATE TABLE IF NOT EXISTS BookingSlotHold (
            HoldID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            PurchaseID BIGINT UNSIGNED NOT NULL,
            LessonNumber SMALLINT UNSIGNED NOT NULL,
            TutorID INT NOT NULL,
            BookingID INT NULL UNIQUE,
            LessonDate DATE NOT NULL,
            StartTime TIME NOT NULL,
            EndTime TIME NOT NULL,
            HoldStatus ENUM('Active', 'Consumed', 'Expired', 'Released')
                NOT NULL DEFAULT 'Active',
            CreatedAtUtc DATETIME(6) NOT NULL,
            ExpiresAtUtc DATETIME(6) NOT NULL,
            ConsumedAtUtc DATETIME(6) NULL,
            ReleasedAtUtc DATETIME(6) NULL,

            CONSTRAINT chk_hold_times
                CHECK (
                    StartTime < EndTime
                    AND TIMEDIFF(EndTime, StartTime) = '01:00:00'
                ),
            CONSTRAINT fk_hold_purchase
                FOREIGN KEY (PurchaseID)
                REFERENCES BookingPurchase(PurchaseID),
            CONSTRAINT fk_hold_purchase_tutor
                FOREIGN KEY (PurchaseID, TutorID)
                REFERENCES BookingPurchase(PurchaseID, TutorID),
            CONSTRAINT fk_hold_booking
                FOREIGN KEY (BookingID) REFERENCES Booking(Booking_id),

            UNIQUE KEY uq_hold_purchase_lesson (PurchaseID, LessonNumber),
            INDEX idx_hold_tutor_conflict
                (TutorID, LessonDate, HoldStatus, ExpiresAtUtc, StartTime)
        ) ENGINE=InnoDB;

        CREATE TABLE IF NOT EXISTS BookingReschedule (
            RescheduleID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            BookingID INT NOT NULL,
            RequestedByUserID INT NOT NULL,
            ReviewedByUserID INT NULL,
            OriginalDate DATE NOT NULL,
            OriginalStartTime TIME NOT NULL,
            OriginalEndTime TIME NOT NULL,
            ProposedDate DATE NOT NULL,
            ProposedStartTime TIME NOT NULL,
            ProposedEndTime TIME NOT NULL,
            RescheduleStatus ENUM(
                'Pending', 'Approved', 'Rejected', 'Cancelled', 'Applied'
            ) NOT NULL DEFAULT 'Pending',
            Reason TEXT NULL,
            RequestedAtUtc DATETIME(6) NOT NULL,
            ReviewedAtUtc DATETIME(6) NULL,
            AppliedAtUtc DATETIME(6) NULL,

            CONSTRAINT chk_reschedule_original_times
                CHECK (OriginalStartTime < OriginalEndTime),
            CONSTRAINT chk_reschedule_proposed_times
                CHECK (ProposedStartTime < ProposedEndTime),
            CONSTRAINT chk_reschedule_proposed_duration
                CHECK (TIMEDIFF(ProposedEndTime, ProposedStartTime) = '01:00:00'),
            CONSTRAINT fk_reschedule_booking
                FOREIGN KEY (BookingID) REFERENCES Booking(Booking_id),
            CONSTRAINT fk_reschedule_requester
                FOREIGN KEY (RequestedByUserID) REFERENCES `User`(UserId),
            CONSTRAINT fk_reschedule_reviewer
                FOREIGN KEY (ReviewedByUserID) REFERENCES `User`(UserId),

            INDEX idx_reschedule_booking_status
                (BookingID, RescheduleStatus)
        ) ENGINE=InnoDB;

        CREATE TABLE IF NOT EXISTS RefundTransaction (
            RefundTransactionID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            RefundID INT NOT NULL,
            IdempotencyKey VARCHAR(128) NOT NULL,
            RefundReference VARCHAR(191) NULL,
            Amount DECIMAL(12,2) NOT NULL,
            TransactionStatus ENUM(
                'Pending', 'Processing', 'Successful', 'Failed',
                'OutcomeUnknown', 'ReconciliationRequired', 'Cancelled'
            ) NOT NULL DEFAULT 'Pending',
            CreatedAtUtc DATETIME(6) NOT NULL,
            UpdatedAtUtc DATETIME(6) NOT NULL,
            ResolvedAtUtc DATETIME(6) NULL,

            CONSTRAINT chk_refund_transaction_amount CHECK (Amount > 0),
            CONSTRAINT fk_refund_transaction_refund
                FOREIGN KEY (RefundID) REFERENCES Refund(RefundID),

            UNIQUE KEY uq_refund_transaction_idempotency
                (RefundID, IdempotencyKey),
            UNIQUE KEY uq_refund_transaction_reference (RefundReference),
            INDEX idx_refund_transaction_status
                (TransactionStatus, CreatedAtUtc)
        ) ENGINE=InnoDB;

        IF NOT EXISTS (
            SELECT 1 FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Refund'
              AND COLUMN_NAME = 'RefundAmount'
        ) THEN
            ALTER TABLE Refund ADD COLUMN RefundAmount DECIMAL(10,2) NULL;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Refund'
              AND COLUMN_NAME = 'ExceptionReviewStatus'
        ) THEN
            ALTER TABLE Refund ADD COLUMN ExceptionReviewStatus ENUM(
                'NotRequested', 'Pending', 'Approved', 'Rejected'
            ) NOT NULL DEFAULT 'NotRequested';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Refund'
              AND COLUMN_NAME = 'ExceptionReason'
        ) THEN
            ALTER TABLE Refund ADD COLUMN ExceptionReason TEXT NULL;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Refund'
              AND COLUMN_NAME = 'ExceptionReviewedByAdminID'
        ) THEN
            ALTER TABLE Refund ADD COLUMN ExceptionReviewedByAdminID INT NULL;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Refund'
              AND COLUMN_NAME = 'ExceptionReviewedAtUtc'
        ) THEN
            ALTER TABLE Refund ADD COLUMN ExceptionReviewedAtUtc DATETIME(6) NULL;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Refund'
              AND COLUMN_NAME = 'ProcessedAtUtc'
        ) THEN
            ALTER TABLE Refund ADD COLUMN ProcessedAtUtc DATETIME(6) NULL;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
            WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'Refund'
              AND CONSTRAINT_NAME = 'chk_refund_amount'
        ) THEN
            ALTER TABLE Refund
                ADD CONSTRAINT chk_refund_amount
                CHECK (RefundAmount IS NULL OR RefundAmount >= 0);
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
            WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'Refund'
              AND CONSTRAINT_NAME = 'chk_refund_percentage'
        ) THEN
            ALTER TABLE Refund
                ADD CONSTRAINT chk_refund_percentage
                CHECK (RefundPercentage BETWEEN 0 AND 100);
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
            WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'Refund'
              AND CONSTRAINT_NAME = 'fk_refund_exception_admin'
        ) THEN
            ALTER TABLE Refund
                ADD CONSTRAINT fk_refund_exception_admin
                FOREIGN KEY (ExceptionReviewedByAdminID)
                REFERENCES Admin(AdminID);
        END IF;

        INSERT INTO SchemaMigrations (Version)
        VALUES ('20261019_01_booking_foundation');
    END IF;
END$$

DELIMITER ;

CALL apply_20261019_01_booking_foundation();
DROP PROCEDURE IF EXISTS apply_20261019_01_booking_foundation;
