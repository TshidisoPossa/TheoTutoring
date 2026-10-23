USE theotutoring;

-- Report table from project documentation 11.1: a student reporting a tutor
-- or a tutor reporting a student. The admin dashboard reviews these
-- (Status Open -> Under review -> Resolved, AdminID = who handled it).
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
) ENGINE=InnoDB;

INSERT IGNORE INTO SchemaMigrations (Version)
VALUES ('004_report');
