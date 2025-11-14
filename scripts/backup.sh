#!/bin/bash
# Backup PostgreSQL and upload to S3/local folder

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/backups"
DB_CONTAINER="postgres_db"
FILE="$BACKUP_DIR/healthdb_$TIMESTAMP.sql"

mkdir -p $BACKUP_DIR
docker exec $DB_CONTAINER pg_dump -U admin healthdb > $FILE

echo "✅ Backup created at $FILE"

# Uncomment if you have AWS CLI configured
# aws s3 cp $FILE s3://your-s3-bucket/backups/
