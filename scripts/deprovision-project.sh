#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SITES_DIR="$ROOT_DIR/compose/caddy/sites"

usage() {
  cat >&2 <<EOF
Usage: $0 <name>

  <name>   Project slug used during provisioning.

Examples:
  $0 meu-projeto
EOF
  exit 1
}

[ $# -lt 1 ] && usage

NAME="$1"

[ -f "$ROOT_DIR/.env" ] && set -a && . "$ROOT_DIR/.env" && set +a

if [ -z "$POSTGRES_USER" ]; then
  echo "Error: POSTGRES_USER must be set in .env" >&2
  exit 1
fi

DB_NAME="${NAME//-/_}"
DB_USER="${NAME//-/_}"
CADDY_FILE="$SITES_DIR/${NAME}.caddy"

echo "This will permanently delete:"
echo "  - PostgreSQL database: $DB_NAME"
echo "  - PostgreSQL user: $DB_USER"
echo "  - Caddy site file: $CADDY_FILE"
echo ""
read -r -p "Deprovision $NAME? [y/N] " reply
case "$reply" in
  [yY]) ;;
  *) echo "Aborted." >&2; exit 0 ;;
esac

echo "[deprovision] Dropping database and user..."
docker compose -f "$ROOT_DIR/docker-compose.yml" exec -T postgres \
  psql -U "$POSTGRES_USER" -d postgres <<-EOSQL
DROP DATABASE IF EXISTS "${DB_NAME}";
DROP ROLE IF EXISTS "${DB_USER}";
EOSQL

if [ -f "$CADDY_FILE" ]; then
  echo "[deprovision] Removing Caddy site file..."
  rm "$CADDY_FILE"
  echo "[deprovision] Reloading Caddy..."
  docker compose -f "$ROOT_DIR/docker-compose.yml" exec caddy caddy reload --config /etc/caddy/Caddyfile
else
  echo "[deprovision] Caddy site file not found, skipping."
fi

echo "[deprovision] Done. Remember to:"
echo "  - Remove /home/deploy/projects/${NAME}/ from the VPS"
echo "  - Disable the deploy workflow in the project repo"
