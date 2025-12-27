#!/usr/bin/env bash
# BLE Monitor – container-safe, non-flapping edition
# v0.3.2

set -u
set -o pipefail

HOSTNAME="${MQTT_PUBLISHER_IDENTITY:-${HOSTNAME:-$(hostname)}}"

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
  local topic="$1"
  local msg="$2"

  local -a cmd=(
    mosquitto_pub
    -h "$MQTT_HOST"
    -p "$MQTT_PORT"
    -t "$topic"
    -m "$msg"
    -r
  )

  [[ -n "$MQTT_USER" ]] && cmd+=(-u "$MQTT_USER")
  [[ -n "$MQTT_PASS" ]] && cmd+=(-P "$MQTT_PASS")

  "${cmd[@]}" || return 1
}

publish_state() {
  local new="$1"

  if [[ "$STATE" != "$new" ]]; then
    STATE="$new"
    log "Publishing $STATE"
    mqtt_pub "$STATUS_TOPIC" "$STATE" \
      || log "MQTT publish failed (state=$STATE); will retry later"
  fi
}

fingerprint_and_publish() {
  local src="$1"
  local payload="$2"
  local rssi="$3"

  local fp
  fp=$(printf "%s:%s" "$src" "$payload" | sha1sum | awk '{print $1}')

  mqtt_pub "${BASE_TOPIC}/fingerprint/${fp}" \
    "{\"state\":\"online\",\"rssi\":${rssi},\"source\":\"${src}\",\"host\":\"${HOSTNAME}\"}" \
    || log "MQTT publish failed (fingerprint=$fp)"
}

cleanup() {
