USE theotutoring;

-- Additive follow-up: the 6-digit codes emailed (through Brevo) to verify a
-- new account's email address. Only a SHA-256 hash of each code is stored.
-- A code lasts 10 minutes and allows 5 tries; sending a new code replaces
-- the old one. Once a code is right the backend marks the email verified in
-- Firebase, so nothing else needs to change in MySQL.
CREATE TABLE IF NOT EXISTS emailverificationCode (
    CodeID INT AUTO_INCREMENT PRIMARY KEY,
    UserId INT NOT NULL,
    CodeHash CHAR(64) NOT NULL,
    CreatedAtUtc DATETIME(6) NOT NULL,
    ExpiresAtUtc DATETIME(6) NOT NULL,
    Attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
    UsedAtUtc DATETIME(6) NULL,
    CONSTRAINT fk_email_code_user FOREIGN KEY (UserId)
        REFERENCES `User` (UserId) ON DELETE CASCADE,
    INDEX idx_email_code_user_created (UserId, CreatedAtUtc)
) ENGINE=InnoDB;

INSERT IGNORE INTO SchemaMigrations (Version)
VALUES ('009_email_verification_code');
