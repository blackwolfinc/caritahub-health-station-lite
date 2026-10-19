import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'constants/squegg_constants.dart';
import 'enums/enums.dart';
import 'models/models.dart';
import 'parser/squegg_parser.dart';

/// Primary interface for communicating with a Squegg Smart Hand Grip Trainer.
///
/// Usage:
/// ```dart
/// final squegg = SqueggCore();
///
/// // 1. Listen to scan results
/// squegg.scanResultsStream.listen((devices) { ... });
///
/// // 2. Start scanning
/// await squegg.startScan();
///
/// // 3. Connect to a discovered device
/// await squegg.connect(device.id);
///
/// // 4. Receive live grip data
/// squegg.dataStream.listen((data) {
///   print('Strength: ${data.strength} kg');
/// });
///
/// // 5. Disconnect when done
/// await squegg.disconnect();
/// ```
class SqueggCore {
  // ──────────────────────────── Singleton ─────────────────────────────────

  static final SqueggCore _instance = SqueggCore._internal();
  factory SqueggCore() => _instance;
  SqueggCore._internal();

  // ──────────────────────────── Internal state ────────────────────────────

  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _dataSub;

  // Scan subscriptions — cancelled on every new startScan() call
  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<bool>? _isScanSub;

  final _dataController = StreamController<SqueggData>.broadcast();
  final _connectionController = StreamController<SqueggConnectionState>.broadcast();
  final _scanController = StreamController<List<SqueggDevice>>.broadcast();
  final _allDevicesController = StreamController<List<SqueggDevice>>.broadcast();
  final _scanStateController = StreamController<SqueggScanState>.broadcast();

  final List<SqueggDevice> _discovered = [];
  final List<SqueggDevice> _allDiscovered = [];

  SqueggData? _lastData;

  // ──────────────────────────── Public streams ────────────────────────────

  /// Stream of real-time grip readings from the connected device.
  Stream<SqueggData> get dataStream => _dataController.stream;

  /// Stream of BLE connection state changes.
  Stream<SqueggConnectionState> get connectionStream => _connectionController.stream;

  /// Stream of Squegg-only discovered devices during an active scan.
  Stream<List<SqueggDevice>> get scanResultsStream => _scanController.stream;

  /// Stream of ALL BLE devices found during scan (diagnostic — includes non-Squegg).
  Stream<List<SqueggDevice>> get allDevicesStream => _allDevicesController.stream;

  /// Stream of scan state changes (idle / scanning).
  Stream<SqueggScanState> get scanStateStream => _scanStateController.stream;

  /// The most recently parsed grip reading, or `null` before the first packet.
  SqueggData? get lastData => _lastData;

  /// Whether a Squegg device is currently connected.
  bool get isConnected => _device != null;

  // ──────────────────────────── Scanning ──────────────────────────────────

  /// Start scanning for nearby Squegg devices.
  ///
  /// ⚠️ We intentionally do NOT pass `withNames` to [FlutterBluePlus.startScan].
  /// The Squegg device (`weixin-nini`) advertises its name only in the **scan
  /// response** packet, not in the primary advertisement data.  Android's
  /// hardware BLE scan filter (`ScanFilter`) inspects advertisement data only,
  /// so a hardware name-filter silently drops every Squegg result.
  /// We therefore scan without any hardware filter and match the device name
  /// in Dart, where both advertisement and scan-response names are visible via
  /// [ScanResult.device.platformName] and
  /// [ScanResult.advertisementData.localName].
  ///
  /// Results accumulate in [scanResultsStream]. Scanning stops automatically
  /// after [timeout] (default: [SqueggConstants.scanTimeout]).
  Future<void> startScan({Duration? timeout}) async {
    // Guard: Bluetooth must be on
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      throw StateError(
        'Bluetooth is not enabled. Please turn on Bluetooth and try again.',
      );
    }

    // Stop any existing scan and cancel previous stream subscriptions
    await FlutterBluePlus.stopScan();
    _scanResultsSub?.cancel();
    _isScanSub?.cancel();

    _discovered.clear();
    _allDiscovered.clear();
    _scanStateController.add(SqueggScanState.scanning);

    try {
      // No hardware filter — Dart-level filtering below.
      // androidCheckLocationServices: false because we declare neverForLocation
      // in the manifest; on Android 12+ location is not needed for BLE scanning.
      await FlutterBluePlus.startScan(
        timeout: timeout ?? SqueggConstants.scanTimeout,
        androidCheckLocationServices: false,
      );

      debugPrint('[SqueggCore] Scan started — timeout: ${timeout ?? SqueggConstants.scanTimeout}');

      // Listen to scan results and filter by device name in Dart.
      _scanResultsSub = FlutterBluePlus.scanResults.listen(
        (results) {
          bool squeggChanged = false;
          bool allChanged = false;

          for (final result in results) {
            // Resolve name: platformName covers both advertisement + scan response.
            // Fall back to advertisementData.advName for completeness.
            final platformName = result.device.platformName;
            final advName = result.advertisementData.advName;
            final name = platformName.isNotEmpty ? platformName : advName;

            // Log ALL devices for debugging
            debugPrint('[SqueggCore] BLE device found:'
                ' id=${result.device.remoteId.str}'
                ' platformName="$platformName"'
                ' advName="$advName"'
                ' rssi=${result.rssi}');

            final device = SqueggDevice(
              id: result.device.remoteId.str,
              name: name,
              rssi: result.rssi,
            );

            // Track all NAMED devices (diagnostic) — skip unnamed devices
            if (name.isNotEmpty) {
              final allIdx = _allDiscovered.indexWhere((d) => d.id == device.id);
              if (allIdx == -1) {
                _allDiscovered.add(device);
                allChanged = true;
              } else if (_allDiscovered[allIdx].rssi != device.rssi) {
                _allDiscovered[allIdx] = device;
                allChanged = true;
              }
            }

            if (!_isSqueggDevice(name)) continue;
            debugPrint('[SqueggCore] ✅ Squegg device matched: $name');

            final squeggIdx = _discovered.indexWhere((d) => d.id == device.id);
            if (squeggIdx == -1) {
              _discovered.add(device);
              squeggChanged = true;
            } else if (_discovered[squeggIdx].rssi != device.rssi) {
              _discovered[squeggIdx] = device;
              squeggChanged = true;
            }
          }

          if (allChanged) _allDevicesController.add(List.unmodifiable(_allDiscovered));
          if (squeggChanged) _scanController.add(List.unmodifiable(_discovered));
        },
        onError: (Object e) {
          debugPrint('[SqueggCore] scanResults error: $e');
          _scanStateController.add(SqueggScanState.idle);
        },
      );

      // Track when the scan ends (timeout or explicit stop).
      _isScanSub = FlutterBluePlus.isScanning.listen((scanning) {
        if (!scanning) {
          debugPrint('[SqueggCore] Scan stopped. Discovered ${_discovered.length} Squegg device(s).');
          _scanStateController.add(SqueggScanState.idle);
        }
      });
    } catch (e) {
      debugPrint('[SqueggCore] startScan error: $e');
      _scanStateController.add(SqueggScanState.idle);
      rethrow;
    }
  }

  /// Returns `true` if [name] matches a Squegg device.
  ///
  /// Case-insensitive partial match — handles both international ("Squegg_1")
  /// and original Chinese firmware ("weixin-nini") variants.
  bool _isSqueggDevice(String name) {
    final lower = name.toLowerCase();
    return lower.contains(SqueggConstants.deviceName.toLowerCase()) ||
        lower.contains(SqueggConstants.deviceNameAlt.toLowerCase());
  }

  /// Stop an in-progress scan early.
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanResultsSub?.cancel();
    _isScanSub?.cancel();
    _scanStateController.add(SqueggScanState.idle);
  }

  // ──────────────────────────── Connection ────────────────────────────────

  /// Connect to the Squegg device with [deviceId].
  ///
  /// Throws if the device is not reachable or if a connection is already open.
  Future<void> connect(String deviceId) async {
    if (_device != null) await disconnect();

    _connectionController.add(SqueggConnectionState.connecting);
    debugPrint('[SqueggCore] Connecting to $deviceId');

    try {
      final device = BluetoothDevice.fromId(deviceId);

      // Clear Android GATT cache before connecting — prevents intermittent
      // status=133 (GATT_ERROR) caused by a stale service/attribute cache
      // left over from a previous connection session.
      // Safe to ignore on iOS or when the device has never been bonded.
      try {
        await device.clearGattCache();
        debugPrint('[SqueggCore] GATT cache cleared');
      } catch (_) {
        // clearGattCache may throw on iOS or on first-time connections;
        // not critical — proceed with connect regardless.
      }

      await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
      _device = device;

      // Track connection-state changes
      _connectionSub = device.connectionState.listen((state) {
        switch (state) {
          case BluetoothConnectionState.connected:
            _connectionController.add(SqueggConnectionState.connected);
            debugPrint('[SqueggCore] Connected');
            break;
          case BluetoothConnectionState.disconnected:
            _connectionController.add(SqueggConnectionState.disconnected);
            _device = null;
            _dataSub?.cancel();
            debugPrint('[SqueggCore] Disconnected');
            break;
          default:
            break;
        }
      });

      await _subscribeToNotifications(device);
    } catch (e) {
      _connectionController.add(SqueggConnectionState.disconnected);
      _device = null;
      debugPrint('[SqueggCore] Connection error: $e');
      rethrow;
    }
  }

  /// Disconnect from the currently connected device.
  Future<void> disconnect() async {
    if (_device == null) return;
    _connectionController.add(SqueggConnectionState.disconnecting);
    await _device!.disconnect();
    _connectionSub?.cancel();
    _dataSub?.cancel();
    _device = null;
    _connectionController.add(SqueggConnectionState.disconnected);
    debugPrint('[SqueggCore] Disconnected gracefully');
  }

  // ──────────────────────────── BLE notification ──────────────────────────

  Future<void> _subscribeToNotifications(BluetoothDevice device) async {
    debugPrint('[SqueggCore] Discovering services...');
    final services = await device.discoverServices();

    debugPrint('[SqueggCore] Found ${services.length} service(s):');
    for (final s in services) {
      debugPrint('[SqueggCore]   service uuid=${s.uuid}');
    }

    final targetUuid = Guid(SqueggConstants.serviceUuid);
    BluetoothService? targetService;
    for (final service in services) {
      if (service.uuid == targetUuid) {
        targetService = service;
        break;
      }
    }

    if (targetService == null) {
      debugPrint('[SqueggCore] Target service ${SqueggConstants.serviceUuid} not found');
      return;
    }
    debugPrint('[SqueggCore] Target service found ✅');

    debugPrint('[SqueggCore] Found ${targetService.characteristics.length} characteristic(s):');
    for (final c in targetService.characteristics) {
      debugPrint('[SqueggCore]   char uuid=${c.uuid}');
    }

    final charUuid = Guid(SqueggConstants.characteristicUuid);
    BluetoothCharacteristic? characteristic;
    for (final c in targetService.characteristics) {
      if (c.uuid == charUuid) {
        characteristic = c;
        break;
      }
    }

    if (characteristic == null) {
      debugPrint('[SqueggCore] Target characteristic ${SqueggConstants.characteristicUuid} not found');
      return;
    }
    debugPrint('[SqueggCore] Target characteristic found ✅');

    await characteristic.setNotifyValue(true);
    debugPrint('[SqueggCore] Subscribed to notifications');

    // Also listen on lastValueStream to catch any cached/immediately available value
    _dataSub = characteristic.lastValueStream.listen((value) {
      if (value.isEmpty) return;

      if (kDebugMode) {
        // Raw hex — every byte individually labelled for easy protocol analysis.
        // Format: idx:hex(ascii) …
        final labeled = value.asMap().entries.map((e) {
          final b = e.value & 0xFF;
          final hex = b.toRadixString(16).padLeft(2, '0');
          final ch = (b >= 0x20 && b < 0x7F) ? String.fromCharCode(b) : '.';
          return '${e.key}:$hex($ch)';
        }).join('  ');
        debugPrint('[SqueggCore] ── packet (${value.length}B) ──  $labeled');
      }

      final data = SqueggParser.parseNotification(value);
      if (data != null) {
        _lastData = data;
        _dataController.add(data);
        debugPrint('[SqueggCore] ▶ $data');
      }
    });
  }

  // ──────────────────────────── Bluetooth state ───────────────────────────

  /// Stream of Bluetooth adapter state changes.
  Stream<BluetoothAdapterState> get bluetoothStateStream => FlutterBluePlus.adapterState;

  /// Whether Bluetooth is currently on.
  Future<bool> get isBluetoothOn async =>
      await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;

  // ──────────────────────────── Lifecycle ─────────────────────────────────

  /// Release all streams and cancel all subscriptions.
  ///
  /// Call this when the app is shutting down or the plugin is no longer needed.
  void dispose() {
    _connectionSub?.cancel();
    _dataSub?.cancel();
    _scanResultsSub?.cancel();
    _isScanSub?.cancel();
    _dataController.close();
    _connectionController.close();
    _scanController.close();
    _allDevicesController.close();
    _scanStateController.close();
  }
}
