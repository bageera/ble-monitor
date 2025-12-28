#!/usr/bin/env bash
#version v0.3.3

# ---- Config -------------------------------------------------
HOSTNAME="${MQTT_PUBLISHER_IDENTITY:-${HOSTNAME:-$(hostname)}}"

MQTT_HOST="${MQTT_ADDRESS:-127.0.0.1}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_USER="${MQTT_USERNAME:-}"
MQTT_PASS="${MQTT_PASSWORD:-}"

BASE_TOPIC="${MQTT_TOPIC_PREFIX:-presence/ble/raw}"
STATUS_TOPIC="${BASE_TOPIC}/${HOSTNAME}/status"

RSSI_THRESHOLD="${RSSI_THRESHOLD:--85}"
OFFLINE_GRACE=180

STATE="unknown"
LAST_ONLINE=0
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

  "${cmd[@]}" || return 1
}

publish_state() {
  local new="$1"

  if [[ "$STATE" != "$new" ]]; then
    STATE="$new"
    log "Publishing $STATE"
    mqtt_pub "$STATUS_TOPIC" "$STATE" || log "MQTT publish failed (state=$STATE)"
  fi
}

fingerprint_publish() {
  local src="$1"
  local payload="$2"
  local rssi="$3"

  local fp
  fp="$(printf '%s:%s' "$src" "$payload" | sha1sum | awk '{print $1}')"

  mqtt_pub "${BASE_TOPIC}/fingerprint/${fp}" \
    "{\"state\":\"online\",\"rssi\":${rssi},\"source\":\"${src}\",\"host\":\"${HOSTNAME}\"}" \
    || log "MQTT publish failed (fingerprint)"
}

log "Starting BLE Monitor v0.3.2 on ${HOSTNAME}"
publish_state "offline"

# ---- Main Loop ----------------------------------------------
btmon 2>/dev/null | while IFS= read -r line; do
  now="$(date +%s)"

  # -------- Android / Google BLE -----------------------------
  if [[ "$line" == *"Service Data: Google"* ]]; then
    read -r nextline || continue

    payload="$(echo "$nextline" | awk '{print $2}')"
    rssi="$(echo "$line" | grep -oE 'RSSI: -?[0-9]+' | awk '{print $2}')"

    [[ -z "$rssi" ]] && continue
    (( rssi > RSSI_THRESHOLD )) || continue

    LAST_ONLINE="$now"
    fingerprint_publish "google_fef3" "$payload" "$rssi"
    publish_state "online"
    continue
  fi

  # -------- Apple BLE ----------------------------------------
  if [[ "$line" == *"Company: Apple"* ]]; then
    payload="$(echo "$line" | sed 's/.*Data: //')"
    rssi="$(echo "$line" | grep -oE 'RSSI: -?[0-9]+' | awk '{print $2}')"

    [[ -z "$rssi" ]] && continue
    (( rssi > RSSI_THRESHOLD )) || continue

    LAST_ONLINE="$now"
    fingerprint_publish "apple_004c" "$payload" "$rssi"
    publish_state "online"
    continue
  fi

  # -------- Offline decay ------------------------------------
  if (( now - LAST_ONLINE > OFFLINE_GRACE )); then
    publish_state "offline"
  fi

done
