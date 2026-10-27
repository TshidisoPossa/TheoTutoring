CREATE DATABASE IF NOT EXISTS theotutoring;
USE theotutoring;

-- =========================================================
-- 1. USER
-- Firebase Authentication handles passwords.
-- FirebaseUid links the SQL user to Firebase Authentication.
-- =========================================================

CREATE TABLE IF NOT EXISTS `User` (
    UserId INT AUTO_INCREMENT PRIMARY KEY,
    FirebaseUid VARCHAR(128) NOT NULL UNIQUE,
    Name VARCHAR(100) NOT NULL,
    PhoneNum VARCHAR(20) NOT NULL,
    Email VARCHAR(150) NOT NULL UNIQUE,
    Role ENUM('student', 'tutor', 'admin') NOT NULL,
    ProfilePhoto VARCHAR(500) NULL,
    Created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    AccountStatus ENUM(
        'Incomplete', 'Pending', 'Active', 'Suspended', 'Deactivated', 'Rejected'
    )
        NOT NULL DEFAULT 'Active'
);

-- =========================================================
-- 2. PLATFORM SETTINGS
-- Exactly one current settings row, identified by SettingsID = 1.
-- Insert the approved rate and commission values separately.
-- =========================================================

CREATE TABLE IF NOT EXISTS PlatformSettings (
    SettingsID TINYINT PRIMARY KEY,
    TutoringRate DECIMAL(10,2) NOT NULL,
    CommissionPercentage DECIMAL(5,2) NOT NULL,
    UpdatedByAdminID INT NULL,
    UpdatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT chk_settings_id CHECK (SettingsID = 1),
    CONSTRAINT chk_platform_rate CHECK (TutoringRate > 0),
    CONSTRAINT chk_platform_commission
        CHECK (CommissionPercentage BETWEEN 0 AND 100)
);

-- =========================================================
-- 3. STUDENT PROFILE
-- Uploaded proof-of-registration and profile images use
-- Cloudinary URLs. File contents are not stored in MySQL.
-- =========================================================

CREATE TABLE IF NOT EXISTS StudentProfile (
    StudentID INT AUTO_INCREMENT PRIMARY KEY,
    Institution VARCHAR(150) NULL, -- university; NULL for older accounts
    Address VARCHAR(255) NOT NULL,
    ProofOfReg VARCHAR(500) NOT NULL,
    InstitutionYear VARCHAR(20) NOT NULL,
    Course VARCHAR(100) NOT NULL,
    Subject_of_interest VARCHAR(255) NOT NULL,
    UserID INT NOT NULL UNIQUE,

    CONSTRAINT fk_student_user
        FOREIGN KEY (UserID) REFERENCES `User`(UserId)
);

-- =========================================================
-- 4. TUTOR PROFILE
-- The tutoring rate is platform-wide, not per tutor.
-- =========================================================

CREATE TABLE IF NOT EXISTS TutorProfile (
    TutorID INT AUTO_INCREMENT PRIMARY KEY,
    Bio TEXT NULL,
    Experience VARCHAR(50) NULL,
    Certificate VARCHAR(500) NULL,
    IdDocument VARCHAR(500) NULL,
    VerificationStat ENUM('Pending', 'Approved', 'Rejected')
        NOT NULL DEFAULT 'Pending',
    AveRate DECIMAL(3,2) NOT NULL DEFAULT 0,
    UserID INT NOT NULL UNIQUE,
    -- Last time the tutor used the app; "Available Now" while recent.
    LastActiveAtUtc DATETIME(6) NULL,

    CONSTRAINT chk_tutor_average_rating
        CHECK (AveRate BETWEEN 0 AND 5),

    CONSTRAINT fk_tutor_user
        FOREIGN KEY (UserID) REFERENCES `User`(UserId)
);

-- =========================================================
-- 5. ADMIN
-- =========================================================

CREATE TABLE IF NOT EXISTS Admin (
    AdminID INT AUTO_INCREMENT PRIMARY KEY,
    UserId INT NOT NULL UNIQUE,
    RoleKey VARCHAR(32) NOT NULL DEFAULT 'admin',

    CONSTRAINT chk_admin_role_key CHECK (RoleKey IN (
        'super_admin', 'admin', 'application_reviewer', 'finance_admin',
        'support_admin', 'monitor_admin'
    )),

    CONSTRAINT fk_admin_user
        FOREIGN KEY (UserId) REFERENCES `User`(UserId)
);

-- Append-only audit of privileged role assignments.
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
            'super_admin', 'admin', 'application_reviewer', 'finance_admin',
            'support_admin', 'monitor_admin'
        ) AND NewRoleKey IN (
            'super_admin', 'admin', 'application_reviewer', 'finance_admin',
            'support_admin', 'monitor_admin'
        )
    ),
    CONSTRAINT fk_admin_role_audit_actor
        FOREIGN KEY (ActorAdminID) REFERENCES Admin(AdminID),
    CONSTRAINT fk_admin_role_audit_target
        FOREIGN KEY (TargetAdminID) REFERENCES Admin(AdminID),
    INDEX idx_admin_role_audit_target (TargetAdminID, ChangedAtUtc)
) ENGINE=InnoDB;

DELIMITER $$
CREATE TRIGGER trg_admin_role_audit_no_update
BEFORE UPDATE ON AdminRoleChangeAudit FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Admin role audit rows are immutable'$$
CREATE TRIGGER trg_admin_role_audit_no_delete
BEFORE DELETE ON AdminRoleChangeAudit FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Admin role audit rows are immutable'$$
DELIMITER ;

ALTER TABLE PlatformSettings
    ADD CONSTRAINT fk_settings_admin
    FOREIGN KEY (UpdatedByAdminID) REFERENCES Admin(AdminID);

-- =========================================================
-- 6. QUALIFICATIONS
-- =========================================================

CREATE TABLE IF NOT EXISTS Qualification (
    QualificationID INT AUTO_INCREMENT PRIMARY KEY,
    TutorID INT NOT NULL,
    Degree VARCHAR(100) NOT NULL,
    Institution VARCHAR(100) NOT NULL,

    CONSTRAINT fk_qualification_tutor
        FOREIGN KEY (TutorID) REFERENCES TutorProfile(TutorID)
);

-- =========================================================
-- 7. SUBJECTS
-- =========================================================

CREATE TABLE IF NOT EXISTS Subjects (
    subjectId INT AUTO_INCREMENT PRIMARY KEY,
    subjectName VARCHAR(100) NOT NULL UNIQUE
);

-- =========================================================
-- 8. TUTOR SUBJECTS
-- =========================================================

CREATE TABLE IF NOT EXISTS TutorSubjects (
    TutorID INT NOT NULL,
    SubjectID INT NOT NULL,

    PRIMARY KEY (TutorID, SubjectID),

    CONSTRAINT fk_tutorsubjects_tutor
        FOREIGN KEY (TutorID) REFERENCES TutorProfile(TutorID),

    CONSTRAINT fk_tutorsubjects_subject
        FOREIGN KEY (SubjectID) REFERENCES Subjects(subjectId)
);

-- =========================================================
-- 9. TUTOR AVAILABILITY
-- =========================================================

CREATE TABLE IF NOT EXISTS TutAvailability (
    AvailabilityID INT AUTO_INCREMENT PRIMARY KEY,
    TutorID INT NOT NULL,
    Day ENUM(
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday'
    ) NOT NULL,
    StartTime TIME NOT NULL,
    end_Time TIME NOT NULL,

    CONSTRAINT chk_availability_times CHECK (StartTime < end_Time),

    CONSTRAINT fk_availability_tutor
        FOREIGN KEY (TutorID) REFERENCES TutorProfile(TutorID)
);

-- One-off changes to the weekly hours on a single date (migration 007).
-- A date with rows here uses only these rows: NULL times = day off,
-- otherwise the only hours open that day.
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

-- =========================================================
-- 10. BOOKING
-- Booking Date/StartTime/EndTime are Africa/Johannesburg local
-- wall-clock values. Backend logic must enforce the strictly-more-
-- than-2-hour lead time and serialize reservations by locking the
-- student then tutor rows before checking bookings and active holds.
-- =========================================================

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
    IdempotencyKey VARCHAR(128)
        CHARACTER SET ascii COLLATE ascii_bin NULL,
    RequestFingerprint CHAR(64)
        CHARACTER SET ascii COLLATE ascii_bin NULL,
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
    CONSTRAINT chk_purchase_idempotency_fields
        CHECK (
            (IdempotencyKey IS NULL AND RequestFingerprint IS NULL)
            OR (IdempotencyKey IS NOT NULL AND RequestFingerprint IS NOT NULL)
        ),

    CONSTRAINT fk_purchase_student
        FOREIGN KEY (StudentID) REFERENCES StudentProfile(StudentID),
    CONSTRAINT fk_purchase_tutor
        FOREIGN KEY (TutorID) REFERENCES TutorProfile(TutorID),
    CONSTRAINT fk_purchase_subject
        FOREIGN KEY (SubjectID) REFERENCES Subjects(subjectId),

    UNIQUE KEY uq_purchase_identity
        (PurchaseID, StudentID, TutorID, SubjectID),
    UNIQUE KEY uq_purchase_student_idempotency
        (StudentID, IdempotencyKey),
    UNIQUE KEY uq_purchase_tutor (PurchaseID, TutorID),
    UNIQUE KEY uq_purchase_total (PurchaseID, TotalAmount),
    INDEX idx_purchase_student_created (StudentID, CreatedAtUtc),
    INDEX idx_purchase_student_purchases (StudentID, PurchaseID),
    INDEX idx_purchase_tutor_created (TutorID, CreatedAtUtc)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS Booking (
    Booking_id INT AUTO_INCREMENT PRIMARY KEY,
    StudentID INT NOT NULL,
    TutorID INT NOT NULL,
    SubjectID INT NOT NULL,
    PurchaseID BIGINT UNSIGNED NULL,
    LessonNumber SMALLINT UNSIGNED NULL,
    LessonPriceAtPurchase DECIMAL(10,2) NULL,
    Date DATE NOT NULL,
    StartTime TIME NOT NULL,
    EndTime TIME NOT NULL,
    Note TEXT NULL,
    CancellationReason TEXT NULL,
    Status ENUM(
        'Pending', 'Confirmed', 'Completed',
        'Cancelled', 'Rejected'
    ) NOT NULL DEFAULT 'Pending',
    Link VARCHAR(500) NULL,
    LinkUpdatedByUserID INT NULL,
    LinkUpdatedAtUtc DATETIME(6) NULL,
    Created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_booking_times CHECK (StartTime < EndTime),
    CONSTRAINT chk_booking_purchase_fields
        CHECK (
            (PurchaseID IS NULL AND LessonNumber IS NULL
                AND LessonPriceAtPurchase IS NULL)
            OR (PurchaseID IS NOT NULL AND LessonNumber IS NOT NULL
                AND LessonPriceAtPurchase IS NOT NULL)
        ),
    CONSTRAINT chk_booking_purchased_lesson_duration
        CHECK (
            PurchaseID IS NULL
            OR TIMEDIFF(EndTime, StartTime) = '01:00:00'
        ),
    CONSTRAINT chk_booking_lesson_price
        CHECK (LessonPriceAtPurchase IS NULL OR LessonPriceAtPurchase >= 0),

    CONSTRAINT fk_booking_student
        FOREIGN KEY (StudentID) REFERENCES StudentProfile(StudentID),

    CONSTRAINT fk_booking_tutor
        FOREIGN KEY (TutorID) REFERENCES TutorProfile(TutorID),

    CONSTRAINT fk_booking_subject
        FOREIGN KEY (SubjectID) REFERENCES Subjects(subjectId),
    CONSTRAINT fk_booking_purchase_identity
        FOREIGN KEY (PurchaseID, StudentID, TutorID, SubjectID)
        REFERENCES BookingPurchase(PurchaseID, StudentID, TutorID, SubjectID),
    CONSTRAINT fk_booking_link_updated_by
        FOREIGN KEY (LinkUpdatedByUserID) REFERENCES `User`(UserId),

    UNIQUE KEY uq_booking_purchase_lesson (PurchaseID, LessonNumber),
    INDEX idx_booking_tutor_date (TutorID, Date, StartTime),
    INDEX idx_booking_student_date (StudentID, Date)
);

-- =========================================================
-- 11. PAYMENT
-- Commission snapshots preserve the rate used for the payment.
-- =========================================================

CREATE TABLE IF NOT EXISTS Payment (
    PaymentID INT AUTO_INCREMENT PRIMARY KEY,
    BookingId INT NOT NULL UNIQUE,
    PaymentMethod VARCHAR(30) NOT NULL,
    PaymentStatus ENUM(
        'Pending', 'Successful', 'Unsuccessful', 'Refunded'
    ) NOT NULL DEFAULT 'Pending',
    Paid_At DATETIME NULL,
    Amount DECIMAL(10,2) NOT NULL,
    CommissionPercentage DECIMAL(5,2) NULL,
    CommissionAmount DECIMAL(10,2) NULL,

    CONSTRAINT chk_payment_amount CHECK (Amount >= 0),

    CONSTRAINT chk_payment_commission_percentage
        CHECK (
            CommissionPercentage IS NULL
            OR CommissionPercentage BETWEEN 0 AND 100
        ),

    CONSTRAINT chk_payment_commission_amount
        CHECK (CommissionAmount IS NULL OR CommissionAmount >= 0),

    CONSTRAINT fk_payment_booking
        FOREIGN KEY (BookingId) REFERENCES Booking(Booking_id)
);

-- PaymentAttempt is the purchase-level payment ledger for new bookings.
-- The legacy Payment table remains unchanged for existing records/flows.
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

    UNIQUE KEY uq_payment_attempt_idempotency (PurchaseID, IdempotencyKey),
    UNIQUE KEY uq_payment_attempt_number (PurchaseID, AttemptNumber),
    UNIQUE KEY uq_payment_attempt_reference (PaymentReference),
    UNIQUE KEY uq_payment_attempt_purchase_identity
        (PurchaseID, PaymentAttemptID),
    INDEX idx_payment_attempt_status (PaymentStatus, CreatedAtUtc)
) ENGINE=InnoDB;

-- One successful, purchase-wide settlement. PaymentID links the legacy
-- per-booking Payment row for single lessons; package settlements leave it NULL.
CREATE TABLE IF NOT EXISTS PurchasePayment (
    PurchasePaymentID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    PurchaseID BIGINT UNSIGNED NOT NULL,
    PaymentAttemptID BIGINT UNSIGNED NOT NULL,
    PaymentID INT NULL,
    Amount DECIMAL(12,2) NOT NULL,
    CreatedAtUtc DATETIME(6) NOT NULL,

    CONSTRAINT chk_purchase_payment_amount CHECK (Amount > 0),
    CONSTRAINT fk_purchase_payment_purchase
        FOREIGN KEY (PurchaseID) REFERENCES BookingPurchase(PurchaseID),
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

-- =========================================================
-- 12. REFUND
-- One refund record per booking.
-- =========================================================

CREATE TABLE IF NOT EXISTS Refund (
    RefundID INT AUTO_INCREMENT PRIMARY KEY,
    BookingID INT NOT NULL UNIQUE,
    CancellationTime DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    RefundPercentage DECIMAL(5,2) NOT NULL DEFAULT 0,
    RefundStatus ENUM(
        'Pending', 'Approved', 'Rejected', 'Processed'
    ) NOT NULL DEFAULT 'Pending',
    RefundAmount DECIMAL(10,2) NULL,
    OverriddenByAdmin BOOLEAN NOT NULL DEFAULT FALSE,
    AdminID INT NULL,
    ExceptionReviewStatus ENUM(
        'NotRequested', 'Pending', 'Approved', 'Rejected'
    ) NOT NULL DEFAULT 'NotRequested',
    ExceptionReason TEXT NULL,
    ExceptionReviewedByAdminID INT NULL,
    ExceptionReviewedAtUtc DATETIME(6) NULL,
    ProcessedAtUtc DATETIME(6) NULL,

    CONSTRAINT chk_refund_percentage
        CHECK (RefundPercentage BETWEEN 0 AND 100),
    CONSTRAINT chk_refund_amount
        CHECK (RefundAmount IS NULL OR RefundAmount >= 0),

    CONSTRAINT fk_refund_booking
        FOREIGN KEY (BookingID) REFERENCES Booking(Booking_id),

    CONSTRAINT fk_refund_admin
        FOREIGN KEY (AdminID) REFERENCES Admin(AdminID),

    CONSTRAINT fk_refund_exception_admin
        FOREIGN KEY (ExceptionReviewedByAdminID) REFERENCES Admin(AdminID)
);

-- Refund remains the per-booking case/aggregate; this table records
-- idempotent monetary refund attempts without weakening Refund.BookingID UNIQUE.
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

    UNIQUE KEY uq_refund_transaction_idempotency (RefundID, IdempotencyKey),
    UNIQUE KEY uq_refund_transaction_reference (RefundReference),
    INDEX idx_refund_transaction_status (TransactionStatus, CreatedAtUtc)
) ENGINE=InnoDB;

-- Administrative refund decisions are kept separately from payment
-- processing so every approve, deny, or override remains attributable.
CREATE TABLE IF NOT EXISTS RefundAdminAction (
    RefundAdminActionID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    RefundID INT NOT NULL,
    AdminID INT NOT NULL,
    Action ENUM('Approved', 'Denied', 'Overridden') NOT NULL,
    Reason TEXT NULL,
    RefundPercentage DECIMAL(5,2) NULL,
    RefundAmount DECIMAL(10,2) NULL,
    CreatedAtUtc DATETIME(6) NOT NULL,

    CONSTRAINT chk_refund_admin_action_percentage
        CHECK (
            RefundPercentage IS NULL
            OR RefundPercentage BETWEEN 0 AND 100
        ),
    CONSTRAINT chk_refund_admin_action_amount
        CHECK (RefundAmount IS NULL OR RefundAmount >= 0),
    CONSTRAINT fk_refund_action_refund
        FOREIGN KEY (RefundID) REFERENCES Refund(RefundID),
    CONSTRAINT fk_refund_action_admin
        FOREIGN KEY (AdminID) REFERENCES Admin(AdminID),

    INDEX idx_refund_action_history
        (RefundID, CreatedAtUtc, RefundAdminActionID)
) ENGINE=InnoDB;

-- User-submitted issues shown in the administrator Refunds & Issues screen.
CREATE TABLE IF NOT EXISTS UserReport (
    ReportID INT AUTO_INCREMENT PRIMARY KEY,
    ReporterUserID INT NOT NULL,
    ReportedUserID INT NOT NULL,
    BookingID INT NULL,
    Reason VARCHAR(191) NOT NULL,
    Description TEXT NOT NULL,
    ReportStatus ENUM('Open', 'UnderReview', 'Resolved')
        NOT NULL DEFAULT 'Open',
    ResolutionNote TEXT NULL,
    ResolvedByAdminID INT NULL,
    CreatedAtUtc DATETIME(6) NOT NULL,
    ResolvedAtUtc DATETIME(6) NULL,

    CONSTRAINT chk_user_report_distinct_users
        CHECK (ReporterUserID <> ReportedUserID),
    CONSTRAINT fk_user_report_reporter
        FOREIGN KEY (ReporterUserID) REFERENCES `User`(UserId),
    CONSTRAINT fk_user_report_reported
        FOREIGN KEY (ReportedUserID) REFERENCES `User`(UserId),
    CONSTRAINT fk_user_report_booking
        FOREIGN KEY (BookingID) REFERENCES Booking(Booking_id),
    CONSTRAINT fk_user_report_admin
        FOREIGN KEY (ResolvedByAdminID) REFERENCES Admin(AdminID),

    INDEX idx_user_report_status_created (ReportStatus, CreatedAtUtc)
) ENGINE=InnoDB;

-- A hold row represents one 60-minute slot in a purchase. Expiration
-- timestamps are UTC; lesson date/time remain Johannesburg local values.
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
        CHECK (StartTime < EndTime AND TIMEDIFF(EndTime, StartTime) = '01:00:00'),
    CONSTRAINT fk_hold_purchase
        FOREIGN KEY (PurchaseID) REFERENCES BookingPurchase(PurchaseID),
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

    INDEX idx_reschedule_booking_status (BookingID, RescheduleStatus)
) ENGINE=InnoDB;

-- =========================================================
-- 13. REVIEWS
-- One review per booking.
-- Backend must verify that the booking is completed and that
-- the student and tutor match that booking.
-- =========================================================

CREATE TABLE IF NOT EXISTS Reviews (
    Reviewid INT AUTO_INCREMENT PRIMARY KEY,
    StudentID INT NOT NULL,
    TutorID INT NOT NULL,
    Rating TINYINT NOT NULL,
    `comment` TEXT NULL,
    Created_At DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    BookingID INT NOT NULL UNIQUE,

    CONSTRAINT chk_review_rating CHECK (Rating BETWEEN 1 AND 5),

    CONSTRAINT fk_review_student
        FOREIGN KEY (StudentID) REFERENCES StudentProfile(StudentID),

    CONSTRAINT fk_review_tutor
        FOREIGN KEY (TutorID) REFERENCES TutorProfile(TutorID),

    CONSTRAINT fk_review_booking
        FOREIGN KEY (BookingID) REFERENCES Booking(Booking_id)
);

-- =========================================================
-- 13b. REPORTS
-- A student reporting a tutor or a tutor reporting a student.
-- The administrator reviews them (AdminID = who handled it).
-- =========================================================

CREATE TABLE IF NOT EXISTS Report (
    ReportID INT AUTO_INCREMENT PRIMARY KEY,
    ReporterID INT NOT NULL,
    ReportedUserID INT NOT NULL,
    BookingID INT NULL,
    AdminID INT NULL,
    Reason TEXT NOT NULL,
    Status ENUM('Open', 'Under review', 'Resolved')
        NOT NULL DEFAULT 'Open',
    Created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_report_not_self
        CHECK (ReporterID <> ReportedUserID),

    CONSTRAINT fk_report_reporter
        FOREIGN KEY (ReporterID) REFERENCES `User`(UserId),

    CONSTRAINT fk_report_reported_user
        FOREIGN KEY (ReportedUserID) REFERENCES `User`(UserId),

    CONSTRAINT fk_report_booking
        FOREIGN KEY (BookingID) REFERENCES Booking(Booking_id),

    CONSTRAINT fk_report_admin
        FOREIGN KEY (AdminID) REFERENCES Admin(AdminID),

    INDEX idx_report_status (Status, Created_at)
);

-- =========================================================
-- 14. MESSAGING AUDIT
-- Firestore remains the primary chat store.
-- Firestore message IDs can link audit records to source messages.
-- =========================================================

CREATE TABLE IF NOT EXISTS Messaging (
    MessageID BIGINT AUTO_INCREMENT PRIMARY KEY,
    FirestoreMessageID VARCHAR(128) NULL UNIQUE,
    UserID INT NOT NULL,
    BookingID INT NULL,
    ReceiveID INT NOT NULL,
    SenderID INT NOT NULL,
    MessageText TEXT NOT NULL,
    SentAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    IsRead BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_messaging_user
        FOREIGN KEY (UserID) REFERENCES `User`(UserId),

    CONSTRAINT fk_messaging_booking
        FOREIGN KEY (BookingID) REFERENCES Booking(Booking_id),

    CONSTRAINT fk_messaging_receiver
        FOREIGN KEY (ReceiveID) REFERENCES `User`(UserId),

    CONSTRAINT fk_messaging_sender
        FOREIGN KEY (SenderID) REFERENCES `User`(UserId),

    INDEX idx_messaging_booking (BookingID, SentAt)
);

-- =========================================================
-- 15. NOTIFICATION AUDIT
-- Firestore stores notification data; FCM delivers push alerts.
-- =========================================================

CREATE TABLE IF NOT EXISTS Notification (
    NotificationID BIGINT AUTO_INCREMENT PRIMARY KEY,
    FirestoreNotificationID VARCHAR(128) NULL UNIQUE,
    UserID INT NOT NULL,
    Type VARCHAR(50) NOT NULL,
    Message TEXT NOT NULL,
    IsRead BOOLEAN NOT NULL DEFAULT FALSE,
    Created_AT DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    BookingID INT NULL,

    CONSTRAINT fk_notification_user
        FOREIGN KEY (UserID) REFERENCES `User`(UserId),

    CONSTRAINT fk_notification_booking
        FOREIGN KEY (BookingID) REFERENCES Booking(Booking_id),

    INDEX idx_notification_user_date (UserID, Created_AT)
);

-- =========================================================
-- 16. TUTOR APPLICATIONS
-- Separate records preserve application history and allow
-- resubmission after rejection.
-- =========================================================

CREATE TABLE IF NOT EXISTS TutorApplication (
    TutApplication INT AUTO_INCREMENT PRIMARY KEY,
    TutorID INT NOT NULL,
    Status ENUM('Pending', 'Approved', 'Rejected')
        NOT NULL DEFAULT 'Pending',
    AdminFeedback TEXT NULL,
    AdminID INT NULL,
    SubmittedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Review_at DATETIME NULL,

    CONSTRAINT fk_application_tutor
        FOREIGN KEY (TutorID) REFERENCES TutorProfile(TutorID),

    CONSTRAINT fk_application_admin
        FOREIGN KEY (AdminID) REFERENCES Admin(AdminID),

    INDEX idx_application_tutor_status (TutorID, Status)
);

-- =========================================================
-- 17. PAYOUTS
-- Workflow: Pending -> Approved -> Paid.
-- CommissionAmount and NetAmount are captured for the payout.
-- =========================================================

CREATE TABLE IF NOT EXISTS Payout (
    PayoutID INT AUTO_INCREMENT PRIMARY KEY,
    TutorID INT NOT NULL,
    Amount DECIMAL(10,2) NOT NULL,
    CommissionAmount DECIMAL(10,2) NOT NULL DEFAULT 0,
    NetAmount DECIMAL(10,2) NOT NULL,
    Status ENUM('Pending', 'Approved', 'Paid')
        NOT NULL DEFAULT 'Pending',
    BookingID INT NOT NULL UNIQUE,
    IsRead BOOLEAN NOT NULL DEFAULT FALSE,
    Created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    AdminID INT NULL,
    ApprovedAt DATETIME NULL,
    PaidAt DATETIME NULL,

    CONSTRAINT chk_payout_amount CHECK (Amount >= 0),
    CONSTRAINT chk_payout_commission CHECK (CommissionAmount >= 0),
    CONSTRAINT chk_payout_net CHECK (NetAmount >= 0),

    CONSTRAINT fk_payout_tutor
        FOREIGN KEY (TutorID) REFERENCES TutorProfile(TutorID),

    CONSTRAINT fk_payout_booking
        FOREIGN KEY (BookingID) REFERENCES Booking(Booking_id),

    CONSTRAINT fk_payout_admin
        FOREIGN KEY (AdminID) REFERENCES Admin(AdminID)
);
