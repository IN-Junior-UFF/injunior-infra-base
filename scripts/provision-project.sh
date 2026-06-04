#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SITES_DIR="$ROOT_DIR/compose/caddy/sites"

usage() {
  cat >&2 <<EOF
Usage: $0 <name> [--prefix|-p <prefix>] [--with-name|-n] [--port|-P <port>] [--deploy-key] [--no-db] [--no-csp]

  <name>                Project slug (lowercase, hyphens only). Used for:
                          - PostgreSQL user/database (unless --no-db)
                          - Caddy site file: $SITES_DIR/<name>.caddy

  --prefix|-p <prefix>  Subdomain prefix (default: api). Use @ for no prefix.
  --with-name|-n        Include <name> in the subdomain.
  --port|-P <port>      Container port to proxy to (default: 3000).
  --deploy-key          Generate an SSH deploy key pair for this project.
                          Private key saved to ~/.ssh/<name>_deploy_key.
                          Public key printed at the end — add it to GitHub.
  --no-db               Skip PostgreSQL user/database creation.
  --no-csp              Omit Content-Security-Policy header from Caddy config.
                          Useful for Next.js frontends that manage their own CSP.

Examples:
  $0 meu-projeto                       -> api.<DOMAIN_BASE>
  $0 meu-projeto --prefix admin        -> admin.<DOMAIN_BASE>
  $0 meu-projeto -p @                  -> <DOMAIN_BASE>
  $0 meu-projeto --with-name           -> api.meu-projeto.<DOMAIN_BASE>
  $0 meu-projeto -n --prefix admin     -> admin.meu-projeto.<DOMAIN_BASE>
  $0 meu-projeto -P 8080               -> proxy to port 8080
  $0 meu-projeto --deploy-key          -> also generates SSH deploy key
  $0 meu-projeto --no-db               -> skip database provisioning
  $0 meu-projeto --no-csp              -> omit CSP header (e.g. Next.js apps)
EOF
  exit 1
}

[ $# -lt 1 ] && usage

NAME="$1"
shift

PREFIX="api"
WITH_NAME=false
PORT="3000"
DEPLOY_KEY=false
NO_DB=false
NO_CSP=false
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix|-p)
      [ $# -lt 2 ] && { echo "Error: --prefix requires a value." >&2; exit 1; }
      PREFIX="$2"
      shift 2
      ;;
    --with-name|-n)
      WITH_NAME=true
      shift
      ;;
    --port|-P)
      [ $# -lt 2 ] && { echo "Error: --port requires a value." >&2; exit 1; }
      PORT="$2"
      shift 2
      ;;
    --deploy-key)
      DEPLOY_KEY=true
      shift
      ;;
    --no-db)
      NO_DB=true
      shift
      ;;
    --no-csp)
      NO_CSP=true
      shift
      ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      usage
      ;;
  esac
done

if ! echo "$NAME" | grep -qE '^[a-z][a-z0-9-]+$'; then
  echo "Error: name must be lowercase letters, digits and hyphens, starting with a letter." >&2
  exit 1
fi

[ -f "$ROOT_DIR/.env" ] && set -a && . "$ROOT_DIR/.env" && set +a

if [ "$NO_DB" = false ] && { [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ]; }; then
  echo "Error: POSTGRES_USER and POSTGRES_PASSWORD must be set in .env" >&2
  exit 1
fi

if [ -z "$DOMAIN_BASE" ]; then
  echo "Error: DOMAIN_BASE must be set in .env" >&2
  exit 1
fi

if [ "$NO_DB" = false ]; then
  DB_NAME="${NAME//-/_}"
  DB_USER="${NAME//-/_}"
fi
if [ "$WITH_NAME" = true ]; then
  if [ "$PREFIX" = "@" ]; then
    API_SUBDOMAIN="${NAME}.${DOMAIN_BASE}"
  else
    API_SUBDOMAIN="${PREFIX}.${NAME}.${DOMAIN_BASE}"
  fi
else
  if [ "$PREFIX" = "@" ]; then
    API_SUBDOMAIN="${DOMAIN_BASE}"
  else
    API_SUBDOMAIN="${PREFIX}.${DOMAIN_BASE}"
  fi
fi
CADDY_FILE="$SITES_DIR/${NAME}.caddy"

echo "[provision] Project: $NAME"
if [ "$NO_DB" = false ]; then
  echo "[provision] Database: $DB_NAME / User: $DB_USER"
fi
echo "[provision] Subdomain: $API_SUBDOMAIN"
echo ""

if [ "$NO_DB" = false ]; then
  DB_PASSWORD=$(openssl rand -hex 16)
  echo "[provision] Creating PostgreSQL user and database..."
  docker compose -f "$ROOT_DIR/docker-compose.yml" exec -T postgres \
    bash /scripts/create-user-db.sh "$DB_USER" "$DB_PASSWORD" "$DB_NAME" app
fi

mkdir -p "$SITES_DIR"

if [ "$NO_CSP" = true ]; then
  cat > "$CADDY_FILE" <<EOF
${API_SUBDOMAIN} {
	import compression
	import security_headers
	reverse_proxy ${NAME}:${PORT} {
		import proxy_headers
	}
}
EOF
else
  cat > "$CADDY_FILE" <<EOF
${API_SUBDOMAIN} {
	import compression
	import security_headers
	header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; font-src 'self'"
	reverse_proxy ${NAME}:${PORT} {
		import proxy_headers
	}
}
EOF
fi

echo "[provision] Reloading Caddy..."
docker compose -f "$ROOT_DIR/docker-compose.yml" exec caddy caddy reload --config /etc/caddy/Caddyfile

if [ "$DEPLOY_KEY" = true ]; then
  DEPLOY_KEY_PATH="$HOME/.ssh/${NAME}_deploy_key"
  echo "[provision] Generating deploy key..."
  ssh-keygen -t ed25519 -f "$DEPLOY_KEY_PATH" -N "" -C "${NAME}-deploy" -q
  chmod 600 "$DEPLOY_KEY_PATH"
  echo "[provision] Deploy key saved to $DEPLOY_KEY_PATH"
fi

echo ""
echo "[provision] Done!"
echo ""
if [ "$NO_DB" = false ]; then
  echo "  Save these credentials in the project .env:"
  echo ""
  echo "  DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@postgres:5432/${DB_NAME}"
  echo "  REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379/<db-index>"
  echo ""
fi
echo "  Project deploy path: /home/deploy/projects/${NAME}/"
echo "  Caddy site: $CADDY_FILE"
echo ""
echo "  Network: add 'infra-network' as external network in docker-compose.yml"

if [ "$DEPLOY_KEY" = true ]; then
  echo ""
  echo "  Deploy key (add to GitHub → Settings → Deploy keys):"
  echo ""
  cat "${DEPLOY_KEY_PATH}.pub"
fi
