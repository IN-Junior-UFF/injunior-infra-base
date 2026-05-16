#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

[ -f "$ROOT_DIR/.env" ] && set -a && . "$ROOT_DIR/.env" && set +a

BACKUP_DIR="${BACKUP_DIR:-/var/backups/infra}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-60}"
pg_user="${POSTGRES_USER:-postgres}"

upload_gdrive() {
  [ -z "$RCLONE_REMOTE" ] && return 0
  local remote="${RCLONE_REMOTE}:${RCLONE_PATH:-infra/backups}"
  echo "[backup] Uploading today's files to $remote..."
  rclone copy "$BACKUP_DIR" "$remote" \
    --include "$(date +%Y-%m-%d)_*" \
    --transfers 4 \
    --quiet
  echo "[backup] Upload complete."
  echo "[backup] Removing remote backups older than $RETENTION_DAYS days..."
  rclone delete "$remote" \
    --min-age "${RETENTION_DAYS}d" \
    --quiet
  echo "[backup] Remote rotation complete."
}

notify_telegram() {
  local msg="$1"
  [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ] && return 0
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d parse_mode="Markdown" \
    -d disable_notification="true" \
    -d text="$msg" > /dev/null
}

on_error() {
  local msg
  msg="Backup falhou em \`$(date '+%Y-%m-%d %H:%M')\`
Verifique: \`tail -50 /var/log/infra-backup.log\`"
  echo "[backup] ERROR: backup failed."
  notify_telegram "$msg"
}
trap on_error ERR

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

ts="$(date +%Y-%m-%d_%H-%M)"

echo "[backup] Dumping full PostgreSQL cluster..."
docker compose exec -T postgres pg_dumpall -U "$pg_user" \
  | gzip > "$BACKUP_DIR/$ts.all.sql.gz"
chmod 600 "$BACKUP_DIR/$ts.all.sql.gz"
echo "[backup] Full dump: $BACKUP_DIR/$ts.all.sql.gz ($(du -h "$BACKUP_DIR/$ts.all.sql.gz" | cut -f1))"

echo "[backup] Dumping individual databases..."
databases=$(docker compose exec -T postgres psql -U "$pg_user" -d postgres -Atc \
  "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres');")
for db in $databases; do
  file="$BACKUP_DIR/$ts.$db.sql.gz"
  echo "[backup]   → $db"
  docker compose exec -T postgres pg_dump -U "$pg_user" "$db" \
    | gzip > "$file"
  chmod 600 "$file"
done

echo "[backup] Backing up Redis RDB..."
docker compose exec -T redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning BGSAVE > /dev/null
sleep 2
docker run --rm \
  -v "$(basename "$ROOT_DIR")_redis_data":/data \
  -v "$BACKUP_DIR":/backup \
  alpine cp /data/dump.rdb "/backup/$ts.redis.rdb"
chmod 600 "$BACKUP_DIR/$ts.redis.rdb"
echo "[backup] Redis RDB: $BACKUP_DIR/$ts.redis.rdb"

echo "[backup] Removing backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +"$RETENTION_DAYS" -delete
find "$BACKUP_DIR" -name "*.rdb" -mtime +"$RETENTION_DAYS" -delete

total_size=$(du -sh "$BACKUP_DIR" | cut -f1)
file_count=$(find "$BACKUP_DIR" \( -name "*.sql.gz" -o -name "*.rdb" \) | wc -l | tr -d ' ')

echo "[backup] Done. $file_count files, $total_size total."

upload_gdrive

notify_telegram "✅ *Backup concluído*
🖥 Host: \`$(hostname)\`
🕐 Data: \`$ts\`
📦 Arquivos: $file_count · $total_size total
🗓 Retenção: ${RETENTION_DAYS} dias${RCLONE_REMOTE:+
☁️ Enviado para Google Drive}"
