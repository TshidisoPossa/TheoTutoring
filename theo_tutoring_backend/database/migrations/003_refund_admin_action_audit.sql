-- Run once against an existing theotutoring database before starting the
-- admin refunds API. No existing records are modified.
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
