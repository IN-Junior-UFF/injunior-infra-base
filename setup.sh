#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "[setup] Copying .env.example to .env..."
  cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
fi

log() { echo "[setup] $*"; }

log "Generating secrets..."
bash "$SCRIPT_DIR/scripts/gen-secrets.sh"

set -a
source "$SCRIPT_DIR/.env"
set +a

if [ -z "$DOMAIN_BASE" ]; then
  echo "Error: DOMAIN_BASE must be set in .env (ex: cliente.com)" >&2
  exit 1
fi

log "Generating redis.conf..."
sed "s|REDIS_PASSWORD_PLACEHOLDER|${REDIS_PASSWORD}|" \
  "$SCRIPT_DIR/compose/redis/redis.conf.template" > "$SCRIPT_DIR/compose/redis/redis.conf"
chmod 600 "$SCRIPT_DIR/compose/redis/redis.conf"

if grep -q "REDIS_PASSWORD_PLACEHOLDER" "$SCRIPT_DIR/compose/redis/redis.conf"; then
  echo "Error: redis.conf still contains placeholder — REDIS_PASSWORD may be empty." >&2
  exit 1
fi
log "redis.conf generated."

if [ "$(uname)" = "Linux" ]; then
  BACKUP_DIR="${BACKUP_DIR:-/var/backups/infra}"
  log "Creating backup directory $BACKUP_DIR..."
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"
fi

log "Starting postgres..."
docker compose up -d postgres

log "Waiting for postgres to be healthy..."
until docker compose exec postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" > /dev/null 2>&1; do
  sleep 2
done
log "Postgres is ready."

log "Starting redis..."
docker compose up -d redis

log "Starting caddy..."
docker compose up -d caddy

log ""
log "Setup complete. All services are running."
log "Domain base: $DOMAIN_BASE"
log ""
log "Next steps:"
log "  1. Configure DNS: api.<project>.$DOMAIN_BASE → VPS IP"
log "  2. Provision a project: ./scripts/provision-project.sh <name>"
log "  3. Set up automated backups: ./scripts/setup-cron.sh"
