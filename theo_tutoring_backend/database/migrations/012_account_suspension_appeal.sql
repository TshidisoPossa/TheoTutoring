-- Runs against the database selected when connecting, for example:
--   mysql --default-character-set=utf8mb4 -u USER -p theotutoring < 012_account_suspension_appeal.sql
--
-- Table names are case-sensitive on the server (lower_case_table_names = 0),
-- so every table is named exactly as it physically exists: user, admin,
-- notification, schemamigrations; the two new tables are created in
-- lowercase too, matching the backend's queries.
--
-- Additive: account suspensions and their appeals.
--
-- accountsuspension  one row each time an administrator suspends a student or
--                    tutor: who did it, why and when, and how it ended
--                    (appeal approved, reinstated or deactivated by an
--                    administrator). Rows are never deleted, so the history
--                    of every suspension is kept. At most one suspension per
--                    user is Active at a time (uq_suspension_one_active).
--                    PreviousAccountStatus is what an approved appeal
--                    restores (e.g. a Pending tutor goes back to Pending).
--
-- suspensionappeal   the user's one appeal against a suspension: their
--                    explanation and when they sent it, then which
--                    administrator decided it, the decision, the note shown
--                    to the user and when. One appeal per suspension
--                    (uq_appeal_one_per_suspension): a rejected appeal is
--                    final for that suspension. Closed means the suspension
--                    ended another way (an administrator reinstated or
--                    deactivated the account) before the appeal was decided.
--
-- NotificationID / DecisionNotificationID point at the existing notification
-- table, the SQL record of what the user was told. Its
-- FirestoreNotificationID stays NULL until the in-app notification was
-- delivered, so undelivered notices can be found and sent again.
--
-- The backend changes AccountStatus, these rows and the notification rows in
-- one transaction, locking the user row first (see lib/account_suspensions.dart).
--
-- Safe to run again: both tables use CREATE TABLE IF NOT EXISTS (an existing
-- table is left as it is, not checked) and the ledger row uses INSERT IGNORE.
CREATE TABLE IF NOT EXISTS accountsuspension (
    SuspensionID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    UserID INT NOT NULL,
    SuspendedByAdminID INT NOT NULL,
    Reason VARCHAR(1000) NOT NULL,
    PreviousAccountStatus VARCHAR(20) NOT NULL,
    SuspendedAtUtc DATETIME(6) NOT NULL,
    Status ENUM('Active', 'Lifted') NOT NULL DEFAULT 'Active',
    LiftedAtUtc DATETIME(6) NULL,
    LiftedByAdminID INT NULL,
    LiftReason ENUM('AppealApproved', 'Reinstated', 'Deactivated') NULL,
    NotificationID BIGINT NULL,
    -- NULL unless Active, so the unique key allows one Active row per user
    ActiveUserID INT AS (CASE WHEN Status = 'Active' THEN UserID END) STORED,

    CONSTRAINT chk_suspension_reason CHECK (CHAR_LENGTH(TRIM(Reason)) >= 10),
    CONSTRAINT chk_suspension_lifted CHECK (
        (Status = 'Active' AND LiftedAtUtc IS NULL AND LiftReason IS NULL)
        OR (Status = 'Lifted' AND LiftedAtUtc IS NOT NULL
            AND LiftReason IS NOT NULL)
    ),
    CONSTRAINT fk_suspension_user
        FOREIGN KEY (UserID) REFERENCES `user`(UserId),
    CONSTRAINT fk_suspension_admin
        FOREIGN KEY (SuspendedByAdminID) REFERENCES `admin`(AdminID),
    CONSTRAINT fk_suspension_lifted_by
        FOREIGN KEY (LiftedByAdminID) REFERENCES `admin`(AdminID),
    CONSTRAINT fk_suspension_notification
        FOREIGN KEY (NotificationID) REFERENCES notification(NotificationID),
    UNIQUE KEY uq_suspension_one_active (ActiveUserID),
    INDEX idx_suspension_user (UserID, SuspendedAtUtc)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS suspensionappeal (
    AppealID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    SuspensionID BIGINT UNSIGNED NOT NULL,
    UserID INT NOT NULL,
    Explanation VARCHAR(2000) NOT NULL,
    SubmittedAtUtc DATETIME(6) NOT NULL,
    Status ENUM('Pending', 'Approved', 'Rejected', 'Closed')
        NOT NULL DEFAULT 'Pending',
    ReviewedByAdminID INT NULL,
    DecisionNote VARCHAR(1000) NULL,
    DecidedAtUtc DATETIME(6) NULL,
    DecisionNotificationID BIGINT NULL,

    CONSTRAINT chk_appeal_explanation
        CHECK (CHAR_LENGTH(TRIM(Explanation)) >= 20),
    CONSTRAINT chk_appeal_decided CHECK (
        (Status = 'Pending' AND DecidedAtUtc IS NULL
            AND ReviewedByAdminID IS NULL)
        OR (Status <> 'Pending' AND DecidedAtUtc IS NOT NULL
            AND ReviewedByAdminID IS NOT NULL)
    ),
    CONSTRAINT fk_appeal_suspension
        FOREIGN KEY (SuspensionID) REFERENCES accountsuspension(SuspensionID),
    CONSTRAINT fk_appeal_user
        FOREIGN KEY (UserID) REFERENCES `user`(UserId),
    CONSTRAINT fk_appeal_reviewer
        FOREIGN KEY (ReviewedByAdminID) REFERENCES `admin`(AdminID),
    CONSTRAINT fk_appeal_notification
        FOREIGN KEY (DecisionNotificationID)
        REFERENCES notification(NotificationID),
    UNIQUE KEY uq_appeal_one_per_suspension (SuspensionID),
    INDEX idx_appeal_status (Status, SubmittedAtUtc),
    INDEX idx_appeal_user (UserID, SubmittedAtUtc)
) ENGINE=InnoDB;

INSERT IGNORE INTO schemamigrations (Version)
VALUES ('012_account_suspension_appeal');
