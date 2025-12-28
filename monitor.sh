#!/usr/bin/env bash
# BLE Monitor — Passive Signal Collector
# Version: 0.4.1

set -u

# ------------------------------------------------------------
VERSION="0.4.1"

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

FP_RSSI_DELTA=6
FP_PUBLISH_INTERVAL=30

STATE="unknown"
LAST_ONLINE=0
LAST_STATS=0
LAST_HEARTBEAT=0

EVENT_COUNT=0

declare -A FP_LAST_SEEN
declare -A FP_LAST_PUB
declare -A FP_LAST_RSSI
declare -A FP_RSSI_MIN
declare -A FP_RSSI_MAX
declare -A FP_STATE
declare -A FP_CLASS
declare -A FP_ID

# ------------------------------------------------------------
log() { echo "[ble-monitor] $*"; }

mqtt_pub() {
  local topic="$1" payload="$2"
  local -a cmd=(mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$topic" -m "$payload" -r)
  [[ -n "$MQTT_USER" ]] && cmd+=(-u "$MQTT_USER")
  [[ -n "$MQTT_PASS" ]] && cmd+=(-P "$MQTT_PASS")
  "${cmd[@]}" || return 1
}

publish_state() {
  local new="$1"
  [[ "$STATE" == "$new" ]] && return
  STATE="$new"
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
    "{\"events_interval\":${EVENT_COUNT},\"rssi_min\":${min},\"rssi_max\":${max},\"interval_seconds\":${STATS_INTERVAL},\"version\":\"${VERSION}\"}"

  EVENT_COUNT=0
  LAST_STATS="$now"
}

should_publish_fp() {
  local fp="$1" rssi="$2" now="$3"
  local last_pub="${FP_LAST_PUB[$fp]:-0}"
  local last_rssi="${FP_LAST_RSSI[$fp]:-}"

  (( now - last_pub >= FP_PUBLISH_INTERVAL )) && return 0

  [[ -n "$last_rssi" ]] || return 1
  local delta=$(( rssi - last_rssi ))
  (( delta < 0 )) && delta=$(( -delta ))
  (( delta >= FP_RSSI_DELTA )) && return 0

  return 1
}

publish_fingerprint() {
  local fp="$1" rssi="$2" class="$3" id="$4" now="$5"

  FP_LAST_SEEN["$fp"]="$now"
  FP_LAST_RSSI["$fp"]="$rssi"
  FP_CLASS["$fp"]="$class"
  FP_ID["$fp"]="$id"
  FP_STATE["$fp"]="online"

  [[ -z "${FP_RSSI_MIN[$fp]:-}" || "$rssi" -lt "${FP_RSSI_MIN[$fp]}" ]] && FP_RSSI_MIN["$fp"]="$rssi"
  [[ -z "${FP_RSSI_MAX[$fp]:-}" || "$rssi" -gt "${FP_RSSI_MAX[$fp]}" ]] && FP_RSSI_MAX["$fp"]="$rssi"

  should_publish_fp "$fp" "$rssi" "$now" || return

  FP_LAST_PUB["$fp"]="$now"

  mqtt_pub "${BASE_TOPIC}/fingerprint/${fp}" \
    "{\"state\":\"online\",\"class\":\"${class}\",\"id\":\"${id}\",\"rssi\":${rssi},\"last_seen\":${now},\"age\":0,\"host\":\"${HOSTNAME}\",\"version\":\"${VERSION}\"}"
}

publish_fingerprint_offline() {
  local fp="$1" now="$2"
  FP_STATE["$fp"]="offline"
  local last_seen="${FP_LAST_SEEN[$fp]}"
  local age=$(( now - last_seen ))

  mqtt_pub "${BASE_TOPIC}/fingerprint/${fp}" \
    "{\"state\":\"offline\",\"class\":\"${FP_CLASS[$fp]}\",\"id\":\"${FP_ID[$fp]}\",\"last_seen\":${last_seen},\"age\":${age},\"host\":\"${HOSTNAME}\",\"version\":\"${VERSION}\"}"
}

# ------------------------------------------------------------
log "Starting BLE Monitor v${VERSION} on ${HOSTNAME}"
publish_state "offline"

# ------------------------------------------------------------
btmon 2>/dev/null | while IFS= read -r line; do
  now="$(date +%s)"

  if [[ "$line" == *"RSSI:"* ]]; then
    rssi="$(echo "$line" | grep -oE 'RSSI: -?[0-9]+' | awk '{print $2}')"
    [[ -z "$rssi" ]] && continue
    (( rssi > RSSI_THRESHOLD )) || continue

    payload="$(echo "$line" | sed 's/.*Data: //')"

    if [[ "$line" == *"Company: Apple"* && "$payload" =~ 4c000215 ]]; then
      uuid="$(echo "$payload" | sed -E 's/.*4c000215(..{32}).*/\1/' \
        | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')"
      fp="$(printf 'ibeacon:%s' "$uuid" | sha1sum | awk '{print $1}')"
      publish_fingerprint "$fp" "$rssi" "ibeacon" "$uuid" "$now"

    elif [[ "$payload" =~ feaa ]]; then
      uid="$(echo "$payload" | tr -d ' ' | sed -E 's/.*feaa00(..{32}).*/\1/')"
      fp="$(printf 'eddystone:%s' "$uid" | sha1sum | awk '{print $1}')"
      publish_fingerprint "$fp" "$rssi" "eddystone" "$uid" "$now"

    else
      fp="$(printf '%s' "$payload" | sha1sum | awk '{print $1}')"
      publish_fingerprint "$fp" "$rssi" "generic_ble" "$fp" "$now"
    fi

    EVENT_COUNT=$((EVENT_COUNT + 1))
    LAST_ONLINE="$now"
    publish_state "online"
  fi

  for fp in "${!FP_LAST_SEEN[@]}"; do
    if (( now - FP_LAST_SEEN[$fp] > FP_GRACE )) && [[ "${FP_STATE[$fp]}" == "online" ]]; then
      publish_fingerprint_offline "$fp" "$now"
    fi
  done

  (( now - LAST_ONLINE > OFFLINE_GRACE )) && publish_state "offline"

  publish_stats "$now"
  publish_heartbeat "$now"
done
