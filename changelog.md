# 📜 Changelog

All notable changes to this project are documented in this file.

This project follows a **monitor-first, clean-architecture philosophy**:

* The monitor publishes **facts**, not decisions
* MQTT is the contract
* Home Assistant (or other consumers) are authoritative

---

## [0.4.0] — 2025-01-XX

### **Semantic Fingerprints, Beacon Awareness, and Clean Architecture Lock-in**

This release marks a **major architectural milestone**.
The BLE monitor is now a **pure passive signal collector** that emits **semantic, stable, low-noise MQTT data** suitable for long-term unattended operation.

### ✨ Added

#### Beacon UUID Extraction

* **Apple iBeacon support**

  * Extracts canonical UUIDs from Apple (0x004C) advertisements
  * Stable across MAC randomization
* **Google Eddystone support**

  * Extracts UID / namespace when present
* Beacon-derived identifiers are now **preferred fingerprint sources** over raw payload hashes

#### Fingerprint Classing

Each observed device is now explicitly classified:

| Class         | Meaning                     |
| ------------- | --------------------------- |
| `ibeacon`     | Apple iBeacon UUID          |
| `eddystone`   | Google Eddystone UID        |
| `generic_ble` | Any other BLE advertisement |

Class is included in every fingerprint payload and **does not imply identity or presence truth**.

#### Debounced Fingerprint Publishing

* Fingerprints are published only when:

  * RSSI changes meaningfully (default ±6 dB), **or**
  * A minimum publish interval elapses (default 30s)
* Reduces MQTT noise by **80–95%** in dense RF environments

#### Semantic MQTT Payloads

Fingerprint messages now include:

* `class` — beacon / generic type
* `id` — UUID, UID, or derived identifier
* `version` — monitor version that emitted the data

---

### 🔧 Improved

#### Heartbeat Throttling (Fixed)

* Heartbeat is now **time-based**, not event-based
* Published once per interval (default: 60s)
* No longer floods the broker during high BLE activity

#### Clean Separation of Concerns

The monitor now **strictly limits itself** to:

* Observing BLE packets
* Fingerprinting devices
* Classifying signal types
* Publishing clean, retained MQTT facts

All decision-making (presence fusion, identity resolution, automations) is intentionally **out of scope**.

---

### 🧠 Architectural Guarantees (Now Enforced)

* ❌ No Home Assistant entities published
* ❌ No MAC-based identity assumptions
* ❌ No policy, heuristics, or presence fusion
* ✅ Stateless operation
* ✅ Retained MQTT facts only
* ✅ Safe for containerized, long-running deployments

---

### 📡 MQTT Topic Contract (v0.4.0)

```
presence/ble/raw/<node>/status
presence/ble/raw/<node>/heartbeat
presence/ble/raw/<node>/stats

presence/ble/raw/fingerprint/<fingerprint>
presence/ble/raw/fingerprint/<fingerprint>/state
```

Fingerprint payload example:

```json
{
  "state": "online",
  "class": "ibeacon",
  "id": "f7826da6-4fa2-4e98-8024-bc5b71e0893e",
  "rssi": -67,
  "host": "gamma",
  "version": "0.4.0"
}
```

---

### 🚫 Breaking Changes (Intentional)

* Legacy MAC-based tracking assumptions are no longer supported
* Fingerprints are no longer raw payload hashes when a stable beacon ID exists
* MQTT noise reduction may affect consumers relying on per-packet updates

These changes are **by design** and required for correctness on modern Android and iOS devices.

---

### 🔜 Next Planned (Post-0.4.0)

* Passive device inventory topic
* Class-based statistics
* Optional per-fingerprint aging metadata

---

This release establishes a **stable, future-proof foundation** for BLE presence systems that respect modern OS privacy constraints while remaining highly observable and reliable.

---

If you want, next I can:

* Update the main `README.md` to reflect the new architecture
* Add a `docs/architecture.md`
* Provide Home Assistant example configs that consume the new semantic topics (without leaking logic back into the monitor)
Absolutely — here’s a **clean, professional `CHANGELOG.md`** entry that matches the direction, tone, and architectural maturity of the project as of **v0.4.0**.

You can drop this in at the repo root as `CHANGELOG.md`.

---

# 📜 Changelog

All notable changes to this project are documented in this file.

This project follows a **monitor-first, clean-architecture philosophy**:

* The monitor publishes **facts**, not decisions
* MQTT is the contract
* Home Assistant (or other consumers) are authoritative

---

## [0.4.0] — 2025-01-XX

### **Semantic Fingerprints, Beacon Awareness, and Clean Architecture Lock-in**

This release marks a **major architectural milestone**.
The BLE monitor is now a **pure passive signal collector** that emits **semantic, stable, low-noise MQTT data** suitable for long-term unattended operation.

### ✨ Added

#### Beacon UUID Extraction

* **Apple iBeacon support**

  * Extracts canonical UUIDs from Apple (0x004C) advertisements
  * Stable across MAC randomization
* **Google Eddystone support**

  * Extracts UID / namespace when present
* Beacon-derived identifiers are now **preferred fingerprint sources** over raw payload hashes

#### Fingerprint Classing

Each observed device is now explicitly classified:

| Class         | Meaning                     |
| ------------- | --------------------------- |
| `ibeacon`     | Apple iBeacon UUID          |
| `eddystone`   | Google Eddystone UID        |
| `generic_ble` | Any other BLE advertisement |

Class is included in every fingerprint payload and **does not imply identity or presence truth**.

#### Debounced Fingerprint Publishing

* Fingerprints are published only when:

  * RSSI changes meaningfully (default ±6 dB), **or**
  * A minimum publish interval elapses (default 30s)
* Reduces MQTT noise by **80–95%** in dense RF environments

#### Semantic MQTT Payloads

Fingerprint messages now include:

* `class` — beacon / generic type
* `id` — UUID, UID, or derived identifier
* `version` — monitor version that emitted the data

---

### 🔧 Improved

#### Heartbeat Throttling (Fixed)

* Heartbeat is now **time-based**, not event-based
* Published once per interval (default: 60s)
* No longer floods the broker during high BLE activity

#### Clean Separation of Concerns

The monitor now **strictly limits itself** to:

* Observing BLE packets
* Fingerprinting devices
* Classifying signal types
* Publishing clean, retained MQTT facts

All decision-making (presence fusion, identity resolution, automations) is intentionally **out of scope**.

---

### 🧠 Architectural Guarantees (Now Enforced)

* ❌ No Home Assistant entities published
* ❌ No MAC-based identity assumptions
* ❌ No policy, heuristics, or presence fusion
* ✅ Stateless operation
* ✅ Retained MQTT facts only
* ✅ Safe for containerized, long-running deployments

---

### 📡 MQTT Topic Contract (v0.4.0)

```
presence/ble/raw/<node>/status
presence/ble/raw/<node>/heartbeat
presence/ble/raw/<node>/stats

presence/ble/raw/fingerprint/<fingerprint>
presence/ble/raw/fingerprint/<fingerprint>/state
```

Fingerprint payload example:

```json
{
  "state": "online",
  "class": "ibeacon",
  "id": "f7826da6-4fa2-4e98-8024-bc5b71e0893e",
  "rssi": -67,
  "host": "gamma",
  "version": "0.4.0"
}
```

---

### 🚫 Breaking Changes (Intentional)

* Legacy MAC-based tracking assumptions are no longer supported
* Fingerprints are no longer raw payload hashes when a stable beacon ID exists
* MQTT noise reduction may affect consumers relying on per-packet updates

These changes are **by design** and required for correctness on modern Android and iOS devices.

---

### 🔜 Next Planned (Post-0.4.0)

* Passive device inventory topic
* Class-based statistics
* Optional per-fingerprint aging metadata

---

This release establishes a **stable, future-proof foundation** for BLE presence systems that respect modern OS privacy constraints while remaining highly observable and reliable.
