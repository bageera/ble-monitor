#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# BLE Monitor — Stateless Signal Publisher
#
# Publishes:
#   presence/ble/raw/<node>/status   → online | offline   (retained)
#   presence/ble/raw/<node>/seen     → true              (non-retained)
#   presence/ble/raw/<node>/rssi     → <dBm>             (non-retained)
#
# Does NOT:
#   - Track identities
#   - Publish home / not_home
#   - Persist MACs
#   - Perform aggregation
###############################################################################

VERSION="0.3.0"

###############################################################################
# Environment
###############################################################################

NODE_NAME="${HOSTNAME:-ble-node}"

MQTT_SERVER="${MQTT_ADDRESS:-127.0.0.1}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_USERNAME="${MQTT_USERNAME:-}"
MQTT_PASSWORD="${MQTT_PASSWORD:-}"

PUBLISH_INTERVAL=30        # seconds between "seen" publishes
SCAN_IFACE="${SCAN_IFACE:-hci0}"

LAST_SEEN_TS=0

###############################################################################
# Helpers
###############################################################################

mqtt_pub() {
  local topic="$1"
  local payload="$2"
  local retain="${3:-false}"

  local retain_flag=""
  [ "$retain" = "true" ] && retain_flag="-r"

  mosquitto_pub \
    -h "$MQTT_SERVER" \
    -p "$MQTT_PORT" \
    -u "$MQTT_USERNAME" \
    -P "$MQTT_PASSWORD" \
    -t "$topic" \
    -m "$payload" \
    $retain_flag
}

log() {
  echo "[ble-monitor] $*"
}

###############################################################################
# Lifecycle
###############################################################################

on_exit() {
  log "Publishing offline"
  mqtt_pub "presence/ble/raw/${NODE_NAME}/status" "offline" true
}

trap on_exit EXIT INT TERM

log "Starting BLE Monitor v${VERSION} on ${NODE_NAME}"
mqtt_pub "presence/ble/raw/${NODE_NAME}/status" "online" true

###############################################################################
# BLE Scan Loop
###############################################################################

log "Listening for BLE advertisements on ${SCAN_IFACE}"

btmon --readline 2>/dev/null | while read -r line; do
  # Only care about Google BLE payloads (Android presence signal)
  if [[ "$line" =~ Google ]]; then
    now=$(date +%s)

    if (( now - LAST_SEEN_TS >= PUBLISH_INTERVAL )); then
      log "BLE seen (Google payload)"
      mqtt_pub "presence/ble/raw/${NODE_NAME}/seen" "true"
      LAST_SEEN_TS=$now
    fi
  fi

  # Extract RSSI if present
  if [[ "$line" =~ RSSI:\ ([\-0-9]+)\ dBm ]]; then
    rssi="${BASH_REMATCH[1]}"
    mqtt_pub "presence/ble/raw/${NODE_NAME}/rssi" "$rssi"
  fi
done
