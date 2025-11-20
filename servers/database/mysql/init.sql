-- Health-InfraOps MySQL Database Initialization

-- Create database
CREATE DATABASE IF NOT EXISTS infokes 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

-- Create application user
CREATE USER IF NOT EXISTS 'infokes_user'@'10.0.10.%' 
IDENTIFIED BY 'secure_password_123';

-- Grant privileges
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, EXECUTE 
ON infokes.* TO 'infokes_user'@'10.0.10.%';

-- Create monitoring user
CREATE USER IF NOT EXISTS 'monitor'@'10.0.40.%' 
IDENTIFIED BY 'monitor_password_123';

-- Grant monitoring privileges
GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO 'monitor'@'10.0.40.%';

-- Create backup user
CREATE USER IF NOT EXISTS 'backup_user'@'10.0.50.%' 
IDENTIFIED BY 'backup_password_123';

-- Grant backup privileges
GRANT SELECT, RELOAD, LOCK TABLES, REPLICATION CLIENT ON *.* TO 'backup_user'@'10.0.50.%';

-- Use database
USE infokes;

-- Create patients table
CREATE TABLE IF NOT EXISTS patients (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    patient_id VARCHAR(20) UNIQUE NOT NULL,
    national_id VARCHAR(20) UNIQUE NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    date_of_birth DATE NOT NULL,
    gender ENUM('M', 'F', 'OTHER') NOT NULL,
    phone_number VARCHAR(20),
    email VARCHAR(255),
    address TEXT,
    emergency_contact VARCHAR(255),
    blood_type ENUM('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_patient_id (patient_id),
    INDEX idx_national_id (national_id),
    INDEX idx_phone (phone_number),
    INDEX idx_created (created_at)
) ENGINE=InnoDB;

-- Create medical_records table
CREATE TABLE IF NOT EXISTS medical_records (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    record_id VARCHAR(30) UNIQUE NOT NULL,
    patient_id BIGINT NOT NULL,
    doctor_id BIGINT NOT NULL,
    visit_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    symptoms TEXT,
    diagnosis TEXT,
    treatment TEXT,
    prescription TEXT,
    notes TEXT,
    follow_up_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE,
    INDEX idx_record_id (record_id),
    INDEX idx_patient_visit (patient_id, visit_date),
    INDEX idx_doctor (doctor_id),
    INDEX idx_visit_date (visit_date)
) ENGINE=InnoDB;

-- Create appointments table
CREATE TABLE IF NOT EXISTS appointments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    appointment_id VARCHAR(25) UNIQUE NOT NULL,
    patient_id BIGINT NOT NULL,
    doctor_id BIGINT NOT NULL,
    appointment_date TIMESTAMP NOT NULL,
    status ENUM('scheduled', 'confirmed', 'completed', 'cancelled', 'no-show') DEFAULT 'scheduled',
    appointment_type ENUM('consultation', 'follow-up', 'emergency', 'routine') DEFAULT 'consultation',
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE,
    INDEX idx_appointment_id (appointment_id),
    INDEX idx_patient_appointment (patient_id, appointment_date),
    INDEX idx_doctor_appointment (doctor_id, appointment_date),
    INDEX idx_status (status),
    INDEX idx_appointment_date (appointment_date)
) ENGINE=InnoDB;

-- Create users table (doctors & staff)
CREATE TABLE IF NOT EXISTS users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    role ENUM('doctor', 'nurse', 'admin', 'receptionist') NOT NULL,
    specialization VARCHAR(100),
    license_number VARCHAR(50),
    phone_number VARCHAR(20),
    is_active BOOLEAN DEFAULT TRUE,
    last_login TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_email (email),
    INDEX idx_role (role),
    INDEX idx_specialization (specialization)
) ENGINE=InnoDB;

-- Create audit_log table
CREATE TABLE IF NOT EXISTS audit_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT,
    action VARCHAR(100) NOT NULL,
    table_name VARCHAR(50) NOT NULL,
    record_id BIGINT,
    old_values JSON,
    new_values JSON,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_action (user_id, action),
    INDEX idx_table_record (table_name, record_id),
    INDEX idx_created (created_at)
) ENGINE=InnoDB;

-- Insert initial admin user
INSERT IGNORE INTO users (
    username, email, password_hash, full_name, role, specialization, license_number
) VALUES (
    'admin',
    'admin@infokes.co.id',
    '$2b$12$LQv3c1yqBWVHxkd0L8k4CuBq6W3oYzL7Hj5M2aNcLpLbLpLpLpLpL', -- password: admin123
    'System Administrator',
    'admin',
    'System Administration',
    'ADMIN-001'
);

-- Insert sample doctor
INSERT IGNORE INTO users (
    username, email, password_hash, full_name, role, specialization, license_number
) VALUES (
    'dr_wijaya',
    'dr.wijaya@infokes.co.id',
    '$2b$12$LQv3c1yqBWVHxkd0L8k4CuBq6W3oYzL7Hj5M2aNcLpLbLpLpLpLp',
    'Dr. Wijaya Kusuma',
    'doctor',
    'General Practitioner',
    'DOK-2023001'
);

-- Create stored procedure for patient statistics
DELIMITER //
CREATE PROCEDURE GetPatientStatistics(IN start_date DATE, IN end_date DATE)
BEGIN
    SELECT 
        COUNT(*) as total_patients,
        COUNT(CASE WHEN DATE(created_at) BETWEEN start_date AND end_date THEN 1 END) as new_patients,
        COUNT(DISTINCT DATE(created_at)) as active_days,
        AVG(DATEDIFF(CURRENT_DATE, date_of_birth)/365) as average_age
    FROM patients;
END //
DELIMITER ;

-- Create view for appointment overview
CREATE VIEW appointment_overview AS
SELECT 
    a.appointment_id,
    p.full_name as patient_name,
    u.full_name as doctor_name,
    a.appointment_date,
    a.status,
    a.appointment_type
FROM appointments a
JOIN patients p ON a.patient_id = p.id
JOIN users u ON a.doctor_id = u.id;

-- Update privileges
FLUSH PRIVILEGES;

-- Log initialization
INSERT INTO audit_log (user_id, action, table_name, record_id, ip_address)
VALUES (1, 'DATABASE_INIT', 'system', 1, '127.0.0.1');