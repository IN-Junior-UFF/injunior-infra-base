#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SITES_DIR="$ROOT_DIR/compose/caddy/sites"

usage() {
  cat >&2 <<EOF
Usage: $0 <name>

  <name>   Project slug (lowercase, hyphens only). Used for:
             - PostgreSQL user/database
             - API subdomain: api.<name>.<DOMAIN_BASE>
             - Caddy site file: $SITES_DIR/<name>.caddy

Examples:
  $0 meu-projeto
EOF
  exit 1
}

[ $# -lt 1 ] && usage

NAME="$1"

if ! echo "$NAME" | grep -qE '^[a-z][a-z0-9-]+$'; then
  echo "Error: name must be lowercase letters, digits and hyphens, starting with a letter." >&2
  exit 1
fi

[ -f "$ROOT_DIR/.env" ] && set -a && . "$ROOT_DIR/.env" && set +a

if [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ]; then
  echo "Error: POSTGRES_USER and POSTGRES_PASSWORD must be set in .env" >&2
  exit 1
fi

if [ -z "$DOMAIN_BASE" ]; then
  echo "Error: DOMAIN_BASE must be set in .env" >&2
  exit 1
fi

DB_NAME="${NAME//-/_}"
DB_USER="${NAME//-/_}"
API_SUBDOMAIN="api.${NAME}.${DOMAIN_BASE}"
CADDY_FILE="$SITES_DIR/${NAME}.caddy"

DB_PASSWORD=$(openssl rand -hex 16)

echo "[provision] Project: $NAME"
echo "[provision] Database: $DB_NAME / User: $DB_USER"
echo "[provision] API subdomain: $API_SUBDOMAIN"
echo ""

echo "[provision] Creating PostgreSQL user and database..."
docker compose -f "$ROOT_DIR/docker-compose.yml" exec -T postgres \
  bash /scripts/create-user-db.sh "$DB_USER" "$DB_PASSWORD" "$DB_NAME" app

mkdir -p "$SITES_DIR"

cat > "$CADDY_FILE" <<EOF
${API_SUBDOMAIN} {
	import compression
	import security_headers
	header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; font-src 'self'"
	reverse_proxy ${NAME}:3000 {
		import proxy_headers
	}
}
EOF

echo "[provision] Reloading Caddy..."
docker compose -f "$ROOT_DIR/docker-compose.yml" exec caddy caddy reload --config /etc/caddy/Caddyfile

echo ""
echo "[provision] Done! Save these credentials in the project .env:"
echo ""
echo "  DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@postgres:5432/${DB_NAME}"
echo "  REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379/<db-index>"
echo ""
echo "  Project deploy path: /home/deploy/projects/${NAME}/"
echo "  Caddy site: $CADDY_FILE"
echo ""
echo "  Network: add 'infra-network' as external network in docker-compose.yml"
