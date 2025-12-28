#!/usr/bin/env bash
# BLE Monitor — Passive Signal Collector
# Version: 0.3.8

set -u

# ------------------------------------------------------------
VERSION="0.3.8"

HOSTNAME="${MQTT_PUBLISHER_IDENTITY:-${HOSTNAME:-$(hostname)}}"

MQTT_HOST="${MQTT_ADDRESS:-127.0.0.1}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_USER="${MQTT_USERNAME:-}"
MQTT_PASS="${MQTT_PASSWORD:-}"

BASE_TOPIC="${MQTT_TOPIC_PREFIX:-presence/ble/raw}"

STATUS_TOPIC="${BASE_TOPIC}/${HOSTNAME}/status"
HEARTBEAT_TOPIC="${BASE_TOPIC}/${HOSTNAME}/heartbeat"
STATS_TOPIC="${BASE_TOPIC}/${HOSTNAME}/stats"

RSSI_THRESHOLD="${RSSI_THRESHOLD:--85}"

OFFLINE_GRACE=180
FP_GRACE=300

STATS_INTERVAL=60
HEARTBEAT_INTERVAL=60

STATE="unknown"
LAST_ONLINE=0
LAST_STATS=0
LAST_HEARTBEAT=0

EVENT_COUNT=0

declare -A FP_LAST_SEEN
declare -A FP_RSSI_MIN
declare -A FP_RSSI_MAX
declare -A FP_STATE

# ------------------------------------------------------------
log() {
  echo "[ble-monitor] $*"
}

mqtt_pub() {
  local topic="$1"
  local payload="$2"

  local -a cmd=(mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$topic" -m "$payload" -r)
  [[ -n "$MQTT_USER" ]] && cmd+=(-u "$MQTT_USER")
  [[ -n "$MQTT_PASS" ]] && cmd+=(-P "$MQTT_PASS")

  "${cmd[@]}" || return 1
}

publish_state() {
  local new="$1"
  [[ "$STATE" == "$new" ]] && return
  STATE="$new"
  log "Status → $STATE"
  mqtt_pub "$STATUS_TOPIC" "$STATE"
}

publish_heartbeat() {
  local now="$1"
  (( now - LAST_HEARTBEAT < HEARTBEAT_INTERVAL )) && return
  mqtt_pub "$HEARTBEAT_TOPIC" "alive"
  LAST_HEARTBEAT="$now"
}

publish_stats() {
  local now="$1"
  (( now - LAST_STATS < STATS_INTERVAL )) && return

  local min=0 max=0
  for fp in "${!FP_RSSI_MIN[@]}"; do
    (( min == 0 || FP_RSSI_MIN[$fp] < min )) && min="${FP_RSSI_MIN[$fp]}"
    (( FP_RSSI_MAX[$fp] > max )) && max="${FP_RSSI_MAX[$fp]}"
  done

  mqtt_pub "$STATS_TOPIC" \
    "{\"events\":${EVENT_COUNT},\"rssi_min\":${min},\"rssi_max\":${max},\"interval\":${STATS_INTERVAL},\"version\":\"${VERSION}\"}"

  EVENT_COUNT=0
  LAST_STATS="$now"
}

publish_fingerprint() {
  local fp="$1" rssi="$2" source="$3" now="$4"

  FP_LAST_SEEN["$fp"]="$now"
  FP_STATE["$fp"]="online"

  [[ -z "${FP_RSSI_MIN[$fp]:-}" || "$rssi" -lt "${FP_RSSI_MIN[$fp]}" ]] && FP_RSSI_MIN["$fp"]="$rssi"
  [[ -z "${FP_RSSI_MAX[$fp]:-}" || "$rssi" -gt "${FP_RSSI_MAX[$fp]}" ]] && FP_RSSI_MAX["$fp"]="$rssi"

  mqtt_pub "${BASE_TOPIC}/fingerprint/${fp}" \
    "{\"state\":\"online\",\"rssi\":${rssi},\"source\":\"${source}\",\"host\":\"${HOSTNAME}\",\"version\":\"${VERSION}\"}"
}

# ------------------------------------------------------------
log "Starting BLE Monitor v${VERSION} on ${HOSTNAME}"
publish_state "offline"

# ------------------------------------------------------------
btmon 2>/dev/null | while IFS= read -r line; do
  now="$(date +%s)"

  # -------- Generic BLE advertisement ------------------------
  if [[ "$line" == *"RSSI:"* ]]; then
    rssi="$(echo "$line" | grep -oE 'RSSI: -?[0-9]+' | awk '{print $2}')"
    [[ -z "$rssi" ]] && continue
    (( rssi > RSSI_THRESHOLD )) || continue

    payload="$(echo "$line" | sed 's/.*Data: //')"
    fp="$(printf '%s' "$payload" | sha1sum | awk '{print $1}')"

    EVENT_COUNT=$((EVENT_COUNT + 1))
    LAST_ONLINE="$now"

    publish_fingerprint "$fp" "$rssi" "generic_ble" "$now"
    publish_state "online"
  fi

  # -------- Fingerprint decay --------------------------------
  for fp in "${!FP_LAST_SEEN[@]}"; do
    if (( now - FP_LAST_SEEN[$fp] > FP_GRACE )) && [[ "${FP_STATE[$fp]}" == "online" ]]; then
      FP_STATE["$fp"]="offline"
      mqtt_pub "${BASE_TOPIC}/fingerprint/${fp}/state" "offline"
    fi
  done

  # -------- Node offline decay -------------------------------
  (( now - LAST_ONLINE > OFFLINE_GRACE )) && publish_state "offline"

  # -------- Periodic signals --------------------------------
  publish_stats "$now"
  publish_heartbeat "$now"
done
