// Health-InfraOps MongoDB Initialization Script

// Initialize replica set
rs.initiate({
    _id: "infokesRS",
    members: [
        {
            _id: 0,
            host: "10.0.20.22:27017",
            priority: 2
        },
        {
            _id: 1,
            host: "10.0.20.23:27017",
            priority: 1
        },
        {
            _id: 2,
            host: "10.0.20.24:27017",
            priority: 1,
            arbiterOnly: true
        }
    ]
});

// Wait for replica set to be initialized
sleep(5000);

// Create admin user
db.getSiblingDB("admin").createUser({
    user: "infokes_admin",
    pwd: "secure_admin_password_123",
    roles: [
        { role: "root", db: "admin" },
        { role: "clusterAdmin", db: "admin" }
    ]
});

// Create application database and user
db.getSiblingDB("infokes").createUser({
    user: "infokes_app",
    pwd: "secure_app_password_123",
    roles: [
        { role: "readWrite", db: "infokes" },
        { role: "dbAdmin", db: "infokes" }
    ]
});

// Create monitoring user
db.getSiblingDB("admin").createUser({
    user: "monitor",
    pwd: "monitor_password_123",
    roles: [
        { role: "clusterMonitor", db: "admin" },
        { role: "read", db: "local" }
    ]
});

// Switch to application database
db = db.getSiblingDB("infokes");

// Create collections with validation
db.createCollection("patients", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["patient_id", "national_id", "full_name", "date_of_birth", "gender"],
            properties: {
                patient_id: {
                    bsonType: "string",
                    description: "must be a string and is required"
                },
                national_id: {
                    bsonType: "string",
                    description: "must be a string and is required"
                },
                full_name: {
                    bsonType: "string",
                    description: "must be a string and is required"
                },
                date_of_birth: {
                    bsonType: "date",
                    description: "must be a date and is required"
                },
                gender: {
                    enum: ["M", "F", "OTHER"],
                    description: "must be one of the enum values and is required"
                },
                phone_number: {
                    bsonType: "string"
                },
                email: {
                    bsonType: "string"
                },
                blood_type: {
                    enum: ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-", null]
                }
            }
        }
    }
});

db.createCollection("medical_records", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["record_id", "patient_id", "doctor_id", "visit_date"],
            properties: {
                record_id: {
                    bsonType: "string"
                },
                patient_id: {
                    bsonType: "objectId"
                },
                doctor_id: {
                    bsonType: "objectId"
                },
                visit_date: {
                    bsonType: "date"
                },
                diagnosis: {
                    bsonType: "string"
                },
                treatment: {
                    bsonType: "string"
                }
            }
        }
    }
});

db.createCollection("appointments", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["appointment_id", "patient_id", "doctor_id", "appointment_date"],
            properties: {
                appointment_id: {
                    bsonType: "string"
                },
                patient_id: {
                    bsonType: "objectId"
                },
                doctor_id: {
                    bsonType: "objectId"
                },
                appointment_date: {
                    bsonType: "date"
                },
                status: {
                    enum: ["scheduled", "confirmed", "completed", "cancelled", "no-show"]
                }
            }
        }
    }
});

// Create indexes for better performance
db.patients.createIndex({ "patient_id": 1 }, { unique: true });
db.patients.createIndex({ "national_id": 1 }, { unique: true });
db.patients.createIndex({ "phone_number": 1 });
db.patients.createIndex({ "created_at": -1 });

db.medical_records.createIndex({ "record_id": 1 }, { unique: true });
db.medical_records.createIndex({ "patient_id": 1, "visit_date": -1 });
db.medical_records.createIndex({ "doctor_id": 1 });

db.appointments.createIndex({ "appointment_id": 1 }, { unique: true });
db.appointments.createIndex({ "patient_id": 1, "appointment_date": -1 });
db.appointments.createIndex({ "doctor_id": 1, "appointment_date": -1 });
db.appointments.createIndex({ "status": 1 });

// Create TTL indexes for data expiration (optional)
// db.sessions.createIndex({ "createdAt": 1 }, { expireAfterSeconds: 3600 });

// Insert sample data
db.patients.insertOne({
    patient_id: "PAT-202300001",
    national_id: "1234567890123456",
    full_name: "Budi Santoso",
    date_of_birth: new Date("1985-05-15"),
    gender: "M",
    phone_number: "+628123456789",
    email: "budi.santoso@example.com",
    blood_type: "O+",
    created_at: new Date(),
    updated_at: new Date()
});

db.patients.insertOne({
    patient_id: "PAT-202300002",
    national_id: "1234567890123457",
    full_name: "Siti Rahayu",
    date_of_birth: new Date("1990-08-20"),
    gender: "F",
    phone_number: "+628123456790",
    email: "siti.rahayu@example.com",
    blood_type: "A+",
    created_at: new Date(),
    updated_at: new Date()
});

// Create audit collection for tracking changes
db.createCollection("audit_log", {
    capped: true,
    size: 100000000, // 100MB
    max: 1000000 // 1 million documents
});

db.audit_log.createIndex({ "timestamp": -1 });
db.audit_log.createIndex({ "collection": 1, "operation": 1 });

print("✅ MongoDB initialization completed successfully!");
print("📊 Databases and users created:");
print("   - infokes database with application user");
print("   - Admin user for management");
print("   - Monitor user for monitoring");
print("   - Sample data inserted");