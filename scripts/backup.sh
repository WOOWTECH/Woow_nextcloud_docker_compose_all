#!/bin/bash
# ===========================================
# Nextcloud Backup Script
# Nextcloud 備份腳本
# ===========================================
# Usage: ./scripts/backup.sh [backup_dir]
# 用法: ./scripts/backup.sh [備份目錄]
# ===========================================

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${1:-$PROJECT_DIR/backups}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="nextcloud_backup_${TIMESTAMP}"

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    echo "Error: .env file not found / 錯誤：找不到 .env 檔案"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "=========================================="
echo "Starting Nextcloud Backup / 開始 Nextcloud 備份"
echo "Timestamp: $TIMESTAMP"
echo "=========================================="

# 1. Enable maintenance mode
echo "[1/5] Enabling maintenance mode / 啟用維護模式..."
podman exec nextcloud-app php occ maintenance:mode --on || true

# 2. Backup PostgreSQL database
echo "[2/5] Backing up PostgreSQL / 備份 PostgreSQL..."
podman exec nextcloud-db pg_dump -U "${POSTGRES_USER:-nextcloud}" "${POSTGRES_DB:-nextcloud}" > "$BACKUP_DIR/${BACKUP_NAME}_db.sql"

# 3. Backup Nextcloud data
echo "[3/5] Backing up Nextcloud data / 備份 Nextcloud 資料..."
tar -czf "$BACKUP_DIR/${BACKUP_NAME}_data.tar.gz" -C "$PROJECT_DIR/data/nextcloud" data

# 4. Backup Nextcloud config
echo "[4/5] Backing up Nextcloud config / 備份 Nextcloud 設定..."
tar -czf "$BACKUP_DIR/${BACKUP_NAME}_config.tar.gz" -C "$PROJECT_DIR/data/nextcloud/html" config

# 5. Disable maintenance mode
echo "[5/5] Disabling maintenance mode / 停用維護模式..."
podman exec nextcloud-app php occ maintenance:mode --off || true

# Create combined archive
echo "Creating combined archive / 建立合併檔案..."
tar -czf "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" \
    -C "$BACKUP_DIR" \
    "${BACKUP_NAME}_db.sql" \
    "${BACKUP_NAME}_data.tar.gz" \
    "${BACKUP_NAME}_config.tar.gz"

# Cleanup individual files
rm -f "$BACKUP_DIR/${BACKUP_NAME}_db.sql"
rm -f "$BACKUP_DIR/${BACKUP_NAME}_data.tar.gz"
rm -f "$BACKUP_DIR/${BACKUP_NAME}_config.tar.gz"

echo "=========================================="
echo "Backup completed / 備份完成"
echo "File: $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
echo "Size: $(du -h "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" | cut -f1)"
echo "=========================================="
