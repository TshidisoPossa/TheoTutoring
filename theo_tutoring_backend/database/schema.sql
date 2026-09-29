CREATE TABLE User (
    UserId INT AUTO_INCREMENT PRIMARY KEY,
    Name VARCHAR(50) NOT NULL,
    PhoneNum VARCHAR(10),
    Email VARCHAR(50) NOT NULL UNIQUE,
    Role VARCHAR(20) NOT NULL,
    ProfilePhoto BLOB,
    Created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    Password VARCHAR(255) NOT NULL,
    AccountStatus VARCHAR(8) DEFAULT 'Active'
);

CREATE TABLE StudentProfile (
    StudentID INT AUTO_INCREMENT PRIMARY KEY,
    Address TEXT,
    ProofofReg BLOB,
    InstitutionYear INT,
    Course VARCHAR(50),
    Subject_of_interest TEXT,
    UserID INT UNIQUE NOT NULL,
    FOREIGN KEY (UserID)
        REFERENCES User(UserId)
);

CREATE TABLE TutorProfile (
    TutorID INT AUTO_INCREMENT PRIMARY KEY,
    Bio TEXT,
    Experience VARCHAR(100),
    Certificate BLOB,
    IdDoc BLOB,
    Hourly_rate DECIMAL(10, 2) NOT NULL,
    VerificationStat VARCHAR(20) DEFAULT 'Pending',
    AveRate DECIMAL(3, 2) DEFAULT 0.00,
    UserID INT UNIQUE NOT NULL,
    FOREIGN KEY (UserID)
        REFERENCES User(UserId)
);