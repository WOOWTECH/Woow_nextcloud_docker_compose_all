#!/bin/bash
# ===========================================
# Nextcloud Restore Script
# Nextcloud 還原腳本
# ===========================================
# Usage: ./scripts/restore.sh <backup_file.tar.gz>
# 用法: ./scripts/restore.sh <備份檔案.tar.gz>
# ===========================================

set -e

# Check argument
if [ -z "$1" ]; then
    echo "Usage: $0 <backup_file.tar.gz>"
    echo "用法: $0 <備份檔案.tar.gz>"
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found / 錯誤：找不到備份檔案: $BACKUP_FILE"
    exit 1
fi

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEMP_DIR=$(mktemp -d)

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    echo "Error: .env file not found / 錯誤：找不到 .env 檔案"
    exit 1
fi

echo "=========================================="
echo "Starting Nextcloud Restore / 開始 Nextcloud 還原"
echo "Backup file: $BACKUP_FILE"
echo "=========================================="

# Confirm
read -p "This will overwrite existing data. Continue? (y/N) / 這將覆蓋現有資料。繼續？(y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted / 已取消"
    exit 1
fi

# Extract backup
echo "[1/6] Extracting backup / 解壓縮備份..."
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"

# Find extracted files
DB_DUMP=$(find "$TEMP_DIR" -name "*_db.sql" | head -1)
DATA_ARCHIVE=$(find "$TEMP_DIR" -name "*_data.tar.gz" | head -1)
CONFIG_ARCHIVE=$(find "$TEMP_DIR" -name "*_config.tar.gz" | head -1)

if [ -z "$DB_DUMP" ] || [ -z "$DATA_ARCHIVE" ] || [ -z "$CONFIG_ARCHIVE" ]; then
    echo "Error: Invalid backup file / 錯誤：無效的備份檔案"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Enable maintenance mode
echo "[2/6] Enabling maintenance mode / 啟用維護模式..."
podman exec nextcloud-app php occ maintenance:mode --on || true

# Stop nextcloud and cron
echo "[3/6] Stopping services / 停止服務..."
podman stop nextcloud-app nextcloud-cron || true

# Restore database
echo "[4/6] Restoring PostgreSQL / 還原 PostgreSQL..."
podman exec -i nextcloud-db psql -U "${POSTGRES_USER:-nextcloud}" -d postgres -c "DROP DATABASE IF EXISTS ${POSTGRES_DB:-nextcloud};"
podman exec -i nextcloud-db psql -U "${POSTGRES_USER:-nextcloud}" -d postgres -c "CREATE DATABASE ${POSTGRES_DB:-nextcloud};"
cat "$DB_DUMP" | podman exec -i nextcloud-db psql -U "${POSTGRES_USER:-nextcloud}" -d "${POSTGRES_DB:-nextcloud}"

# Restore data
echo "[5/6] Restoring Nextcloud data / 還原 Nextcloud 資料..."
rm -rf "$PROJECT_DIR/data/nextcloud/data"
tar -xzf "$DATA_ARCHIVE" -C "$PROJECT_DIR/data/nextcloud"

# Restore config
tar -xzf "$CONFIG_ARCHIVE" -C "$PROJECT_DIR/data/nextcloud/html"

# Restart services
echo "[6/6] Restarting services / 重新啟動服務..."
podman start nextcloud-app nextcloud-cron

# Wait for startup
sleep 10

# Disable maintenance mode
podman exec nextcloud-app php occ maintenance:mode --off || true

# Fix permissions
podman exec nextcloud-app chown -R www-data:www-data /var/www/html/data
podman exec nextcloud-app chown -R www-data:www-data /var/www/html/config

# Cleanup
rm -rf "$TEMP_DIR"

echo "=========================================="
echo "Restore completed / 還原完成"
echo "Please verify your Nextcloud instance"
echo "請驗證您的 Nextcloud 實例"
echo "=========================================="
