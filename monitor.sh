#!/usr/bin/env bash
set -euo pipefail

HOSTNAME="${HOSTNAME:-$(hostname)}"
MQTT_HOST="${MQTT_ADDRESS:-127.0.0.1}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_USER="${MQTT_USERNAME:-}"
MQTT_PASS="${MQTT_PASSWORD:-}"

BASE_TOPIC="presence/ble"
STATUS_TOPIC="${BASE_TOPIC}/raw/${HOSTNAME}/status"

SCAN_IFACE="${BLE_IFACE:-hci0}"
RSSI_THRESHOLD="${RSSI_THRESHOLD:--85}"
STATE="unknown"
LAST_ONLINE=0
OFFLINE_GRACE=180   # seconds

log() {
  echo "[ble-monitor] $*"
}

mqtt_pub() {
  mosquitto_pub \
    -h "$MQTT_HOST" -p "$MQTT_PORT" \
    ${MQTT_USER:+-u "$MQTT_USER"} \
    ${MQTT_PASS:+-P "$MQTT_PASS"} \
    -t "$1" -m "$2" -r
}

publish_state() {
  local new="$1"
  if [[ "$STATE" != "$new" ]]; then
    STATE="$new"
    log "Publishing $STATE"
    mqtt_pub "$STATUS_TOPIC" "$STATE"
  fi
}

fingerprint_and_publish() {
  local src="$1"
  local payload="$2"
  local rssi="$3"

  local fp
  fp=$(echo "${src}:${payload}" | sha1sum | awk '{print $1}')

  mqtt_pub "${BASE_TOPIC}/fingerprint/${fp}" \
    "{\"state\":\"online\",\"rssi\":${rssi},\"source\":\"${src}\",\"host\":\"${HOSTNAME}\"}"
}

log "Starting BLE Monitor v0.3.1 on $HOSTNAME"
publish_state "offline"

btmon | while read -r line; do
  # Google Android BLE
  if [[ "$line" =~ Service\ Data:\ Google ]]; then
    read -r data_line
    payload=$(echo "$data_line" | awk '{print $2}')
    rssi=$(echo "$line" | grep -oE 'RSSI: -?[0-9]+' | awk '{print $2}')
    [[ -z "$rssi" ]] && continue
    (( rssi > RSSI_THRESHOLD )) || continue

    LAST_ONLINE=$(date +%s)
    fingerprint_and_publish "google_fef3" "$payload" "$rssi"
    publish_state "online"
  fi

  # Apple BLE
  if [[ "$line" =~ Company:\ Apple ]]; then
    payload=$(echo "$line" | sed 's/.*Data: //')
    rssi=$(echo "$line" | grep -oE 'RSSI: -?[0-9]+' | awk '{print $2}')
    [[ -z "$rssi" ]] && continue
    (( rssi > RSSI_THRESHOLD )) || continue

    LAST_ONLINE=$(date +%s)
    fingerprint_and_publish "apple_004c" "$payload" "$rssi"
    publish_state "online"
  fi

  # Offline decay
  now=$(date +%s)
  if (( now - LAST_ONLINE > OFFLINE_GRACE )); then
    publish_state "offline"
  fi
done
