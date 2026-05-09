#!/usr/bin/env bash
set -e

ENV_FILE="$(dirname "$0")/../.env"

if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: openssl is required." >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  cp "$(dirname "$0")/../.env.example" "$ENV_FILE"
fi

SECRETS=(
  POSTGRES_PASSWORD
  REDIS_PASSWORD
)

chmod 600 "$ENV_FILE"

for key in "${SECRETS[@]}"; do
  existing=$(grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2-)
  if [ -n "$existing" ]; then
    continue
  fi

  value=$(openssl rand -hex 16)

  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    rm -f "${ENV_FILE}.bak"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi

  echo "Generated: $key"
done

echo "Secrets saved to .env"
