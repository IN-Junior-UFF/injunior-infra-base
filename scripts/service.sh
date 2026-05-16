#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

CRITICAL_SERVICES="postgres redis"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/infra}"

usage() {
  cat >&2 <<EOF
Usage: ./scripts/service.sh <command> [service]

Commands:
  update   <service>  Pull latest image and recreate the service
  recreate <service>  Recreate the service without pulling (applies config changes)
  restart  <service>  Restart the service
  start    <service>  Start a stopped service
  stop     <service>  Stop the service (prompts confirmation for critical services)
  logs     <service>  Tail logs (optional: LINES=50 ./scripts/service.sh logs <service>)
  status              Show status and resource usage for all services
  health              Show only unhealthy or restarting containers
  backup              Dump all PostgreSQL databases and Redis to $BACKUP_DIR
  restore  <file>     Restore PostgreSQL from a .sql.gz backup file (auto-detects full or per-db)
EOF
  exit 1
}

is_critical() {
  for s in $CRITICAL_SERVICES; do
    [ "$s" = "$1" ] && return 0
  done
  return 1
}

confirm() {
  read -r -p "$1 [y/N] " reply
  case "$reply" in
    [yY]) return 0 ;;
    *) echo "Aborted." >&2; exit 0 ;;
  esac
}

cmd_recreate() {
  local service="$1"
  echo "[service] Recreating $service..."
  docker compose up -d --no-deps --force-recreate "$service"
  echo "[service] Tailing logs (Ctrl+C to exit)..."
  docker compose logs -f --tail=50 "$service"
}

cmd_update() {
  local service="$1"
  echo "[service] Pulling latest image for $service..."
  docker compose pull "$service"
  echo "[service] Recreating $service..."
  docker compose up -d --no-deps --force-recreate "$service"
  echo "[service] Tailing logs (Ctrl+C to exit)..."
  docker compose logs -f --tail=50 "$service"
}

cmd_restart() {
  local service="$1"
  echo "[service] Restarting $service..."
  docker compose restart "$service"
  docker compose ps
}

cmd_start() {
  local service="$1"
  echo "[service] Starting $service..."
  docker compose up -d "$service"
  docker compose ps
}

cmd_stop() {
  local service="$1"
  if is_critical "$service"; then
    confirm "⚠ $service is a critical service. Stop it?"
  fi
  echo "[service] Stopping $service..."
  docker compose stop "$service"
  docker compose ps
}

cmd_logs() {
  local service="$1"
  local lines="${LINES:-100}"
  docker compose logs -f --tail="$lines" "$service"
}

cmd_backup() {
  bash "$SCRIPT_DIR/backup.sh"
}

cmd_restore() {
  local file="$1"
  [ ! -f "$file" ] && { echo "Error: file not found: $file" >&2; exit 1; }
  local pg_user="${POSTGRES_USER:-postgres}"
  local name
  name=$(basename "$file")

  if gunzip -c "$file" | head -5 | grep -q "PostgreSQL database cluster dump"; then
    confirm "⚠ This will overwrite ALL databases. Restore full cluster from $file?"
    echo "[restore] Restoring full cluster from $file..."
    gunzip -c "$file" | docker compose exec -T postgres psql -U "$pg_user" -d postgres

  elif echo "$name" | grep -q '\.sql\.gz$'; then
    local db
    db=$(echo "$name" | sed 's/^[0-9_-]*\.\(.*\)\.sql\.gz$/\1/')
    confirm "⚠ This will overwrite database '$db'. Restore from $file?"
    echo "[restore] Restoring database '$db' from $file..."
    gunzip -c "$file" | docker compose exec -T postgres psql -U "$pg_user" -d "$db"

  elif echo "$name" | grep -q '\.redis\.rdb$'; then
    confirm "⚠ This will overwrite Redis data. Restore from $file?"
    echo "[restore] Stopping redis..."
    docker compose stop redis
    echo "[restore] Restoring Redis RDB..."
    docker run --rm \
      -v "$(basename "$ROOT_DIR")_redis_data":/data \
      -v "$(dirname "$file")":/backup \
      alpine sh -c "cp /backup/$(basename "$file") /data/dump.rdb"
    echo "[restore] Starting redis..."
    docker compose up -d redis

  else
    echo "Error: unrecognized backup file format: $name" >&2
    exit 1
  fi
  echo "[restore] Done."
}

cmd_health() {
  echo "=== Unhealthy / Restarting ==="
  unhealthy=$(docker compose ps --format "table {{.Service}}\t{{.Status}}" \
    | awk 'NR==1 { next } /(unhealthy|restarting|Exit|starting)/ { print }' \
    | column -t -s $'\t')
  [ -n "$unhealthy" ] && echo "$unhealthy" || echo "All services healthy."

  echo ""
  echo "=== Restart counts ==="
  project=$(basename "$ROOT_DIR")
  restarts=$(docker ps --filter "label=com.docker.compose.project=$project" \
    --format "{{.Names}}\t{{.Status}}" \
    | awk -F'\t' '$2 ~ /Restarting/ || ($2 ~ /\([1-9][0-9]*\)/ ) { print $1 "\t" $2 }' \
    | column -t -s $'\t')
  [ -n "$restarts" ] && echo "$restarts" || echo "No unexpected restarts."
}

cmd_status() {
  echo "=== Services ==="
  docker compose ps --format "table {{.Service}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" \
    | awk 'NR==1 { print; next } { gsub(/0\.0\.0\.0:|::/,""); gsub(/\[.*?\]->/,""); print }' \
    | column -t -s $'\t'

  echo ""
  echo "=== Resources ==="
  project=$(basename "$ROOT_DIR")
  containers=$(docker ps --filter "label=com.docker.compose.project=$project" --format "{{.Names}}")
  docker stats --no-stream $containers \
    --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

  echo ""
  echo "=== Host ==="
  if [ "$(uname)" = "Linux" ]; then
    cpu_used=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | awk '{printf "%.1f%%", $1}')
    mem_total=$(free -m | awk '/^Mem:/ {print $2}')
    mem_used=$(free -m | awk '/^Mem:/ {print $3}')
    mem_pct=$(awk "BEGIN {printf \"%.1f%%\", $mem_used / $mem_total * 100}")
  else
    cores=$(sysctl -n hw.logicalcpu)
    cpu_used=$(ps -A -o %cpu | awk -v cores="$cores" '{s+=$1} END {printf "%.1f%%", s/cores}')
    mem_total=$(sysctl -n hw.memsize | awk '{printf "%d", $1/1024/1024}')
    mem_used=$(vm_stat | awk '/active|wired/ {sum += $NF} END {printf "%d", sum * 4096 / 1024 / 1024}')
    mem_pct=$(awk "BEGIN {printf \"%.1f%%\", $mem_used / $mem_total * 100}")
  fi
  disk_used=$(df -h / | awk 'NR==2 {print $3}')
  disk_total=$(df -h / | awk 'NR==2 {print $2}')
  disk_pct=$(df / | awk 'NR==2 {print $5}')
  printf "%-6s %s\n" "CPU:"  "$cpu_used"
  printf "%-6s %s / %s (%s)\n" "RAM:"  "${mem_used}MiB" "${mem_total}MiB" "$mem_pct"
  printf "%-6s %s / %s (%s)\n" "Disk:" "$disk_used" "$disk_total" "$disk_pct"
}

COMMAND="${1:-}"
SERVICE="${2:-}"

[ -z "$COMMAND" ] && usage

[ -f "$ROOT_DIR/.env" ] && set -a && . "$ROOT_DIR/.env" && set +a

case "$COMMAND" in
  update|recreate|restart|start|stop|logs)
    [ -z "$SERVICE" ] && { echo "Error: service name required for '$COMMAND'" >&2; usage; }
    "cmd_$COMMAND" "$SERVICE"
    ;;
  status)  cmd_status  ;;
  health)  cmd_health  ;;
  backup)  cmd_backup  ;;
  restore)
    [ -z "$SERVICE" ] && { echo "Error: backup file required for 'restore'" >&2; usage; }
    cmd_restore "$SERVICE"
    ;;
  *)
    echo "Error: unknown command '$COMMAND'" >&2
    usage
    ;;
esac
