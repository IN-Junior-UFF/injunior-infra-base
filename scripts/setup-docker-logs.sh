#!/usr/bin/env bash
set -e

DAEMON_FILE="/etc/docker/daemon.json"

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: run as root or with sudo." >&2
  exit 1
fi

if [ -f "$DAEMON_FILE" ]; then
  cp "$DAEMON_FILE" "${DAEMON_FILE}.bak"
  echo "Backup saved: ${DAEMON_FILE}.bak"
fi

cat > "$DAEMON_FILE" <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "7"
  }
}
EOF

echo "Docker log rotation configured (7 files x 50m = ~350m max per container)."
echo "Restart Docker to apply: systemctl restart docker"
