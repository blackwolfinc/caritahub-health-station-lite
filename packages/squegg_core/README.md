# squegg_core

Flutter package for the **Squegg Smart Hand Grip Trainer** — a BLE-connected grip strength device.

> **Unofficial** — not affiliated with or endorsed by Squegg / Nudiao.

---

## Features

- Scan for nearby Squegg devices (BLE name filter: `weixin-nini`)
- Connect / disconnect with automatic state tracking
- Real-time grip data stream: **strength (kg)**, **isSqueezing**, **battery %**
- Pure Dart/Flutter — no native method channels, powered by `flutter_blue_plus`

---

## BLE Protocol

| Field | UUID |
|-------|------|
| Service | `0000ffb0-0000-1000-8000-00805f9b34fb` |
| Characteristic (notify) | `0000ffb2-0000-1000-8000-00805f9b34fb` |
| Device name | `weixin-nini` |

### Packet format

Raw notification bytes are ASCII char codes. After stripping the first unknown byte:

```
[ skip ] [ battery_digit ] [ squeeze_digit ] [ strength_chars... ]
```

- **battery** → `(digit + 1) × 10`  →  10–100 %
- **isSqueezing** → digit ≠ `'0'`
- **strength** → join remaining chars → `double`, rounded to 1 decimal

Example: bytes `[49,57,49,49,57,46,54,50,55]` → `strength: 19.6 kg, isSqueezing: true, battery: 100%`

---

## Installation

```yaml
dependencies:
  squegg_core:
    path: ../squegg_core   # or pub.dev version when published
```

### Android — `AndroidManifest.xml`

```xml
<!-- Android 12+ -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- Android 11 and below -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />

<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
```

Also set `minSdk = 21` in `app/build.gradle.kts`.

### iOS — `Info.plist`

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Required to connect to your Squegg grip trainer.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Required to communicate with your Squegg device.</string>
```

---

## Quick Start

```dart
import 'package:squegg_core/squegg_core.dart';

final squegg = SqueggCore();

// 1. Scan
squegg.scanResultsStream.listen((devices) {
  print('Found: $devices');
});
await squegg.startScan();

// 2. Connect
await squegg.connect(deviceId);

// 3. Live data
squegg.dataStream.listen((data) {
  print('${data.strength} kg  squeeze=${data.isSqueezing}  bat=${data.batteryCharge}%');
});

// 4. Disconnect
await squegg.disconnect();
```

---

## API

### `SqueggCore` (singleton)

| Method / Stream | Description |
|---|---|
| `startScan({Duration? timeout})` | Start BLE scan, filtered to Squegg devices |
| `stopScan()` | Stop scan early |
| `connect(String deviceId)` | Connect and subscribe to notifications |
| `disconnect()` | Graceful disconnect |
| `dataStream` | `Stream<SqueggData>` — live grip readings |
| `connectionStream` | `Stream<SqueggConnectionState>` |
| `scanResultsStream` | `Stream<List<SqueggDevice>>` |
| `scanStateStream` | `Stream<SqueggScanState>` |
| `lastData` | Last `SqueggData?` synchronously |
| `isConnected` | `bool` |
| `bluetoothStateStream` | `Stream<BluetoothAdapterState>` |
| `dispose()` | Release all streams |

### `SqueggData`

```dart
SqueggData {
  double strength;       // kg, 1 decimal place
  bool isSqueezing;
  int batteryCharge;     // 10–100 (steps of 10)
  DateTime timestamp;

  double normalizedStrength({double maxKg = 100.0}); // 0.0–1.0
}
```

### `SqueggDevice`

```dart
SqueggDevice {
  String id;    // MAC (Android) or UUID (iOS)
  String name;
  int rssi;
  String signalQuality;  // 'Excellent' | 'Good' | 'Fair' | 'Weak'
}
```

### `SqueggParser`

```dart
SqueggParser.parse(List<int> bytes) → SqueggData?
```

Use directly if you manage BLE yourself.

---

## Example App

The `example/` directory contains a full-featured demo app built with **Cubit + Freezed**:

| Screen | Description |
|---|---|
| **Dashboard** | Connection status, live gauge, quick actions |
| **Simple** | Raw SDK demo — raw bytes → parsed values |
| **Train** | Real-time force gauge, target zone, session waveform |
| **Assess** | 3-rep grip strength assessment with fatigue index |
| **History** | Past training sessions and assessment results |

```
cd example
flutter pub get
dart run build_runner build
flutter run
```

---

## Enums

```dart
enum SqueggConnectionState { disconnected, connecting, connected, disconnecting }
enum SqueggScanState { idle, scanning }
```
