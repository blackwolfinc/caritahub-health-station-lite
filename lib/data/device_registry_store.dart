import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_models.dart';

/// Alat BLE yang didaftarkan ke perangkat ini, satu per [DeviceType].
/// Disimpan lokal di SharedPreferences.
///
/// Kunci alat ([locked]): hanya alat terdaftar yang dipakai; pemancar alat
/// lain diabaikan dan pendaftaran tidak bisa diubah. Saat kunci mati, alat
/// baru sejenis boleh ditawarkan untuk menggantikan alat terdaftar yang tidak
/// aktif; alat yang ditolak petugas diingat di [ignored].
class DeviceRegistryStore extends ChangeNotifier {
  DeviceRegistryStore._();
  static final DeviceRegistryStore instance = DeviceRegistryStore._();

  static const _key = 'device_registry_v1';
  static const _kLock = 'device_lock_v1';
  static const _kIgnored = 'device_ignored_v1';

  Map<DeviceType, RegisteredDevice> _registry = {};
  bool _locked = false;
  Set<String> _ignored = {};
  bool _loaded = false;

  bool get locked => _locked;
  Set<String> get ignored => Set.unmodifiable(_ignored);
  bool isIgnored(String remoteId) => _ignored.contains(remoteId);

  Map<DeviceType, RegisteredDevice> get registry => Map.unmodifiable(_registry);
  bool get isEmpty => _registry.isEmpty;
  bool get isLoaded => _loaded;
  RegisteredDevice? of(DeviceType type) => _registry[type];

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _locked = prefs.getBool(_kLock) ?? false;
      _ignored = (prefs.getStringList(_kIgnored) ?? const <String>[]).toSet();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final list = (jsonDecode(raw) as List).cast<Map>();
        _registry = {
          for (final m in list)
            if (RegisteredDevice.fromJson(m.cast<String, dynamic>())
                case final RegisteredDevice d)
              d.type: d,
        };
      }
    } catch (e) {
      debugPrint('[Registry] load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> register(RegisteredDevice device) async {
    final current = _registry[device.type];
    if (_locked && current?.remoteId != device.remoteId) {
      throw StateError('Kunci alat aktif — matikan kunci untuk mengganti alat');
    }
    _registry = {..._registry, device.type: device};
    // Alat yang sekarang dipakai tidak lagi dianggap "ditolak".
    if (_ignored.remove(device.remoteId)) await _persistIgnored();
    await _persist();
    notifyListeners();
  }

  Future<void> unregister(DeviceType type) async {
    if (_locked) {
      throw StateError('Kunci alat aktif — matikan kunci untuk menghapus alat');
    }
    _registry = Map.of(_registry)..remove(type);
    await _persist();
    notifyListeners();
  }

  Future<void> setLocked(bool value) async {
    if (_locked == value) return;
    _locked = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLock, value);
  }

  /// Tolak alat ini: tidak ditawarkan lagi sebagai pengganti.
  Future<void> ignore(String remoteId) async {
    if (!_ignored.add(remoteId)) return;
    notifyListeners();
    await _persistIgnored();
  }

  Future<void> clearIgnored() async {
    if (_ignored.isEmpty) return;
    _ignored = {};
    notifyListeners();
    await _persistIgnored();
  }

  Future<void> _persistIgnored() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kIgnored, _ignored.toList()..sort());
  }

  /// Untuk test: lupakan isi yang sudah dimuat supaya [load] membaca ulang.
  @visibleForTesting
  void debugReset() {
    _registry = {};
    _locked = false;
    _ignored = {};
    _loaded = false;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final d in _registry.values) d.toJson()]),
    );
  }
}
