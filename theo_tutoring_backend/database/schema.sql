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
    AccountStatus ENUM('Active', 'Suspended', 'Deactivated')
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
    Experiance VARCHAR(50) NULL,
    Certificate VARCHAR(500) NULL,
    IdDocum VARCHAR(500) NULL,
    VerificationStat ENUM('Pending', 'Approved', 'Rejected')
        NOT NULL DEFAULT 'Pending',
    AveRate DECIMAL(3,2) NOT NULL DEFAULT 0,
    UserID INT NOT NULL UNIQUE,

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

    CONSTRAINT fk_admin_user
        FOREIGN KEY (UserId) REFERENCES `User`(UserId)
);

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

-- =========================================================
-- 10. BOOKING
-- Backend logic must enforce the 3-hour lead time and prevent
-- overlapping bookings within a transaction.
-- =========================================================

CREATE TABLE IF NOT EXISTS Booking (
    Booking_id INT AUTO_INCREMENT PRIMARY KEY,
    StudentID INT NOT NULL,
    TutorID INT NOT NULL,
    SubjectID INT NOT NULL,
    Date DATE NOT NULL,
    StartTime TIME NOT NULL,
    EndTime TIME NOT NULL,
    Note TEXT NULL,
    Status ENUM(
        'Pending', 'Confirmed', 'Completed',
        'Cancelled', 'Rejected'
    ) NOT NULL DEFAULT 'Pending',
    Link VARCHAR(500) NULL,
    Created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_booking_times CHECK (StartTime < EndTime),

    CONSTRAINT fk_booking_student
        FOREIGN KEY (StudentID) REFERENCES StudentProfile(StudentID),

    CONSTRAINT fk_booking_tutor
        FOREIGN KEY (TutorID) REFERENCES TutorProfile(TutorID),

    CONSTRAINT fk_booking_subject
        FOREIGN KEY (SubjectID) REFERENCES Subjects(subjectId),

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
    OverriddenByAdmin BOOLEAN NOT NULL DEFAULT FALSE,
    AdminID INT NULL,

    CONSTRAINT chk_refund_percentage
        CHECK (RefundPercentage BETWEEN 0 AND 100),

    CONSTRAINT fk_refund_booking
        FOREIGN KEY (BookingID) REFERENCES Booking(Booking_id),

    CONSTRAINT fk_refund_admin
        FOREIGN KEY (AdminID) REFERENCES Admin(AdminID)
);

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
    StudentID INT NOT NULL,
    Status ENUM('Pending', 'Approved', 'Rejected')
        NOT NULL DEFAULT 'Pending',
    AdminFeedback TEXT NULL,
    AdminID INT NULL,
    SubmittedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Review_at DATETIME NULL,

    CONSTRAINT fk_application_student
        FOREIGN KEY (StudentID) REFERENCES StudentProfile(StudentID),

    CONSTRAINT fk_application_admin
        FOREIGN KEY (AdminID) REFERENCES Admin(AdminID),

    INDEX idx_application_student_status (StudentID, Status)
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