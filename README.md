---

# `ble-monitor` (Passive BLE → MQTT)

![version](https://img.shields.io/badge/version-0.3.3-green.svg)
![mqtt](https://img.shields.io/badge/MQTT-required-blue.svg)

## TL;DR

**Passive Bluetooth Low Energy monitor** that listens to BLE advertisements and publishes **raw proximity signals** to MQTT.

This project **does not identify people or devices** and **does not make presence decisions**.

> BLE is treated as a *signal*, not an identity source.
> Home Assistant (or another consumer) is authoritative.

---

## Design Principles (Non-Negotiable)

* **Passive only**

  * No BLE connections
  * No pairing
  * No name requests
  * No scanning control

* **Stateless**

  * No memory across restarts
  * No device identity assumptions
  * No Home Assistant logic

* **MQTT is the contract**

  * Idempotent, retained messages
  * Restart-safe
  * HA can rehydrate state at any time

* **Android-safe**

  * Assumes MAC randomization
  * No resolvable identity tracking
  * Uses service payload fingerprints only

---

## What This Project Is (and Is Not)

### ✅ This project **does**

* Listen to BLE advertisements via `btmon`
* Detect nearby BLE activity (Apple + Google)
* Measure RSSI
* Publish **raw presence signals** to MQTT
* Emit heartbeats and node health

### ❌ This project **does NOT**

* Track people
* Track MAC addresses
* Publish `device_tracker` topics
* Publish `person.*`
* Aggregate presence
* Decide “home” vs “away”

Those responsibilities belong **upstream** (Home Assistant, Node-RED, etc.).

---

## MQTT Topic Schema (v0.3.3)

### 1️⃣ Node Presence State

```
presence/ble/raw/<node>/status
```

Payload:

```
online | offline
```

Meaning:

> “This node has recently observed BLE activity above threshold.”

---

### 2️⃣ Heartbeat (Process Liveness)

```
presence/ble/raw/<node>/heartbeat
```

Payload:

```
alive
```

Published every 60 seconds regardless of BLE activity.

---

### 3️⃣ Fingerprint Telemetry (Debug / Analytics)

```
presence/ble/raw/fingerprint/<hash>
```

Payload (JSON):

```json
{
  "state": "online",
  "rssi": -62,
  "threshold": -85,
  "source": "google_fef3",
  "host": "gamma",
  "version": "0.3.3"
}
```

Notes:

* Fingerprints are **content-based**, not identity-based
* Rate-limited to avoid MQTT flooding
* Intended for observability, not automations

---

## Android BLE Limitation (Important)

Modern Android devices intentionally prevent passive BLE identity tracking:

* MAC addresses are masked or zeroed
* Identifiers rotate cryptographically
* Only service-level payloads (e.g. Google `FEF3`) are visible

**This is not a bug.**
This project is designed with that limitation as a first-class constraint.

As a result:

> **BLE presence ≠ device identity**

---

## Intended Architecture

```
BLE Monitor (this repo)
        ↓
     MQTT
        ↓
Home Assistant
  ├─ Wi-Fi (identity anchor)
  ├─ BLE (confidence signal)
  ├─ Bayesian fusion
  └─ Person entities
```

---

## Docker (Recommended)

```yaml
services:
  ble_monitor:
    image: ghcr.io/bageera/ble-monitor:v0.3.3
    network_mode: host
    privileged: true
    restart: unless-stopped

    environment:
      MQTT_ADDRESS: "127.0.0.1"
      MQTT_PORT: "1883"
      MQTT_USERNAME: "${MQTT_USERNAME}"
      MQTT_PASSWORD: "${MQTT_PASSWORD}"
      MQTT_PUBLISHER_IDENTITY: "gamma"
      MQTT_TOPIC_PREFIX: "presence/ble/raw"

    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /run/dbus:/run/dbus:ro
```

---

## Home Assistant Integration (Example)

### BLE Signal (Not Identity)

```yaml
binary_sensor:
  - platform: mqtt
    name: "BLE Presence Gamma"
    state_topic: "presence/ble/raw/gamma/status"
    payload_on: "online"
    payload_off: "offline"
    device_class: presence
    expire_after: 300
```

### Node Health

```yaml
binary_sensor:
  - platform: mqtt
    name: "BLE Monitor Gamma Health"
    state_topic: "presence/ble/raw/gamma/heartbeat"
    payload_on: "alive"
    device_class: connectivity
    expire_after: 120
```

---

## Verifying MQTT Output (Do This Now)

### Watch all BLE topics

```bash
mosquitto_sub -h 127.0.0.1 -v -t 'presence/ble/#'
```

You should see:

```
presence/ble/raw/gamma/status online
presence/ble/raw/gamma/heartbeat alive
presence/ble/raw/fingerprint/abc123 {...}
```

### Check retained status

```bash
mosquitto_sub -h 127.0.0.1 -v -t 'presence/ble/raw/gamma/status' -C 1
```

Should immediately return `online` or `offline`.

---

## Versioning

* Semantic versioning
* `latest` is only updated on tagged releases
* Production deployments should pin explicit versions

---

## License & Attribution

This project is a **conceptual fork** of `andrewjfreyer/monitor`, but **differs fundamentally in architecture**.

No active scanning.
No identity tracking.
No device management.

---

## Summary

This project exists to do **one thing well**:

> **Turn passive BLE radio noise into a clean, reliable MQTT signal.**

Everything else belongs elsewhere — by design.
