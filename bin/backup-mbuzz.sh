#!/bin/bash
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/tmp/mbuzz_${TIMESTAMP}.dump"
S3_PATH="s3://mbuzz/mbuzz/backups/daily/"

docker exec multibuzz-postgres \
  pg_dump -U multibuzz -Fc multibuzz_production \
  > "$BACKUP_FILE"

s3cmd put "$BACKUP_FILE" "$S3_PATH"

s3cmd ls "$S3_PATH" \
  | sort -r \
  | tail -n +8 \
  | awk '{print $4}' \
  | xargs -I {} s3cmd del {}

rm -f "$BACKUP_FILE"

echo "[$(date)] Backup complete: mbuzz_${TIMESTAMP}.dump"
