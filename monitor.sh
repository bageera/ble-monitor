#!/usr/bin/env bash
# ------------------------------------------------------------
# BLE Monitor — Passive Presence Sensor
# Version: v0.3.6
# ------------------------------------------------------------

set -u

# -------------------- Version -------------------------------
VERSION="0.3.6"

# -------------------- Config --------------------------------
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
OFFLINE_GRACE="${OFFLINE_GRACE:-180}"
STATS_INTERVAL="${STATS_INTERVAL:-60}"

STATE="unknown"
LAST_ONLINE=0
BLE_EVENT_COUNT=0
RSSI_MIN=0
RSSI_MAX=0
LAST_STATS_TS=0
# ------------------------------------------------------------

log() {
  echo "[ble-monitor] $*"
}

mqtt_pub() {
  local topic="$1"
  local payload="$2"

  local -a cmd=(
    mosquitto_pub
    -h "$MQTT_HOST"
    -p "$MQTT_PORT"
    -t "$topic"
    -m "$payload"
    -r
  )

  [[ -n "$MQTT_USER" ]] && cmd+=(-u "$MQTT_USER")
  [[ -n "$MQTT_PASS" ]] && cmd+=(-P "$MQTT_PASS")

  "${cmd[@]}" >/dev/null 2>&1 || return 1
}

publish_state() {
  local new="$1"
  if [[ "$STATE" != "$new" ]]; then
    STATE="$new"
    log "Publishing status: $STATE"
    mqtt_pub "$STATUS_TOPIC" "$STATE" || log "MQTT publish failed (status)"
  fi
}

publish_heartbeat() {
  mqtt_pub "$HEARTBEAT_TOPIC" "alive"
}

publish_stats() {
  local now="$1"

  mqtt_pub "$STATS_TOPIC" \
    "{\"events\":${BLE_EVENT_COUNT},\"rssi_min\":${RSSI_MIN},\"rssi_max\":${RSSI_MAX},\"interval\":${STATS_INTERVAL},\"version\":\"${VERSION}\"}"

  BLE_EVENT_COUNT=0
  RSSI_MIN=0
  RSSI_MAX=0
  LAST_STATS_TS="$now"
}

fingerprint_publish() {
  local src="$1"
  local payload="$2"
  local rssi="$3"

  local fp
  fp="$(printf '%s:%s' "$src" "$payload" | sha1sum | awk '{print $1}')"

  mqtt_pub "${BASE_TOPIC}/fingerprint/${fp}" \
    "{\"state\":\"online\",\"rssi\":${rssi},\"source\":\"${src}\",\"host\":\"${HOSTNAME}\",\"version\":\"${VERSION}\"}"
}

# -------------------- Startup --------------------------------
log "Starting BLE Monitor v${VERSION} on ${HOSTNAME}"
publish_state "offline"
publish_heartbeat
# -------------------------------------------------------------

# -------------------- Main Loop -------------------------------
btmon 2>/dev/null | while IFS= read -r line; do
  now="$(date +%s)"

  # ---------------- Generic BLE Activity ---------------------
  if [[ "$line" == *"RSSI:"* ]]; then
    rssi="$(echo "$line" | grep -oE 'RSSI: -?[0-9]+' | awk '{print $2}')"
    [[ -z "$rssi" ]] && continue
    (( rssi > RSSI_THRESHOLD )) || continue

    LAST_ONLINE="$now"
    ((BLE_EVENT_COUNT++))

    [[ "$RSSI_MIN" -eq 0 || "$rssi" -lt "$RSSI_MIN" ]] && RSSI_MIN="$rssi"
    [[ "$RSSI_MAX" -eq 0 || "$rssi" -gt "$RSSI_MAX" ]] && RSSI_MAX="$rssi"

    publish_state "online"

    # ---- Classification Layer -------------------------------
    if [[ "$line" == *"Service Data: Google"* ]]; then
      read -r nextline || true
      payload="$(echo "$nextline" | awk '{print $2}')"
      fingerprint_publish "google_fef3" "$payload" "$rssi"

    elif [[ "$line" == *"Company: Apple"* ]]; then
      payload="$(echo "$line" | sed 's/.*Data: //')"
      fingerprint_publish "apple_004c" "$payload" "$rssi"

    else
      fingerprint_publish "generic_ble" "advertisement" "$rssi"
    fi
  fi

  # ---------------- Offline Decay -----------------------------
  if (( now - LAST_ONLINE > OFFLINE_GRACE )); then
    publish_state "offline"
  fi

  # ---------------- Periodic Stats ---------------------------
  if (( now - LAST_STATS_TS >= STATS_INTERVAL )); then
    publish_stats "$now"
    publish_heartbeat
  fi

done
