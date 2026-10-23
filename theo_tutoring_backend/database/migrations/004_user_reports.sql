-- Adds the report-case storage consumed by GET /admin/refunds and
-- POST /admin/refunds/{report-id}/resolve. Existing rows are not modified.
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
