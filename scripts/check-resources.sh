#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

[ -f "$ROOT_DIR/.env" ] && set -a && . "$ROOT_DIR/.env" && set +a

DISK_THRESHOLD="${RESOURCE_DISK_THRESHOLD:-80}"
RAM_THRESHOLD="${RESOURCE_RAM_THRESHOLD:-85}"
CPU_THRESHOLD="${RESOURCE_CPU_THRESHOLD:-90}"

TELEGRAM_SILENT="${TELEGRAM_SILENT:-false}"

notify_telegram() {
  local msg="$1"
  [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ] && return 0
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d parse_mode="Markdown" \
    -d disable_notification="$TELEGRAM_SILENT" \
    -d text="$msg" > /dev/null
}

alerts=()

disk_usage=$(df / | awk 'NR==2 { gsub(/%/, "", $5); print $5 }')
if [ "$disk_usage" -ge "$DISK_THRESHOLD" ]; then
  alerts+=("Disco: ${disk_usage}% usado (limite: ${DISK_THRESHOLD}%)")
fi

ram_total=$(free | awk '/^Mem:/ { print $2 }')
ram_used=$(free | awk '/^Mem:/ { print $3 }')
ram_pct=$(( ram_used * 100 / ram_total ))
if [ "$ram_pct" -ge "$RAM_THRESHOLD" ]; then
  alerts+=("RAM: ${ram_pct}% usada (limite: ${RAM_THRESHOLD}%)")
fi

cpu_idle=$(top -bn1 | awk '/^%Cpu/ { print $8 }' | cut -d. -f1)
cpu_pct=$(( 100 - cpu_idle ))
if [ "$cpu_pct" -ge "$CPU_THRESHOLD" ]; then
  alerts+=("CPU: ${cpu_pct}% usada (limite: ${CPU_THRESHOLD}%)")
fi

if [ "${#alerts[@]}" -eq 0 ]; then
  echo "[check-resources] OK — disk: ${disk_usage}%, ram: ${ram_pct}%, cpu: ${cpu_pct}%"
  exit 0
fi

msg="⚠️ *Alerta de recursos*
🖥 Host: \`$(hostname)\`
🕐 Data: \`$(date '+%Y-%m-%d %H:%M')\`
"
for alert in "${alerts[@]}"; do
  msg+="• $alert"$'\n'
  echo "[check-resources] ALERT: $alert"
done

notify_telegram "$msg"
exit 1
