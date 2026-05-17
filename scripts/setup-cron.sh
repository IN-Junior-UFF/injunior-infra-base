#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_SCRIPT="$ROOT_DIR/scripts/backup.sh"
RESOURCES_SCRIPT="$ROOT_DIR/scripts/check-resources.sh"
BACKUP_LOG="/var/log/infra-backup.log"
RESOURCES_LOG="/var/log/infra-resources.log"

CRON_BACKUP="0 3 * * * cd $ROOT_DIR && bash $BACKUP_SCRIPT >> $BACKUP_LOG 2>&1"
CRON_RESOURCES="0 * * * * cd $ROOT_DIR && bash $RESOURCES_SCRIPT >> $RESOURCES_LOG 2>&1"

echo "[cron] Validating requirements..."

for script in "$BACKUP_SCRIPT" "$RESOURCES_SCRIPT"; do
  if [ ! -f "$script" ]; then
    echo "Error: $script not found." >&2
    exit 1
  fi
  chmod +x "$script"
done

BACKUP_DIR="${BACKUP_DIR:-/var/backups/infra}"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

for log_file in "$BACKUP_LOG" "$RESOURCES_LOG"; do
  if [ ! -f "$log_file" ]; then
    echo "[cron] Creating $log_file..."
    sudo touch "$log_file"
    sudo chown "$(id -u)":"$(id -g)" "$log_file"
  fi
done

echo "[cron] Running test backup..."
bash "$BACKUP_SCRIPT"
echo "[cron] Test backup successful."

echo "[cron] Registering cron jobs..."
(
  crontab -l 2>/dev/null \
    | grep -v "$BACKUP_SCRIPT" \
    | grep -v "$RESOURCES_SCRIPT" \
    || true
  echo "$CRON_BACKUP"
  echo "$CRON_RESOURCES"
) | crontab -

echo "[cron] Registered: $CRON_BACKUP"
echo "[cron] Registered: $CRON_RESOURCES"
echo ""
echo "[cron] Current crontab:"
crontab -l
