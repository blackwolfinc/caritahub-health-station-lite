import 'package:flutter/material.dart';

/// Lima jenis alat ukur yang didukung — sama dengan branch health-device.
enum DeviceType {
  tensimeter,
  pulseOximeter,
  thermometer,
  weightScale,
  gripStrength;

  String get label => switch (this) {
    DeviceType.tensimeter => 'Tensimeter',
    DeviceType.pulseOximeter => 'Oksimeter',
    DeviceType.thermometer => 'Termometer',
    DeviceType.weightScale => 'Timbangan',
    DeviceType.gripStrength => 'Kekuatan Genggam',
  };

  /// Label singkat untuk kotak di layar ukur (mudah dibaca kader).
  String get shortLabel => switch (this) {
    DeviceType.tensimeter => 'Tensi',
    DeviceType.pulseOximeter => 'Oksigen',
    DeviceType.thermometer => 'Suhu',
    DeviceType.weightScale => 'Timbang',
    DeviceType.gripStrength => 'Genggam',
  };

  String get subtitle => switch (this) {
    DeviceType.tensimeter => 'Tekanan darah',
    DeviceType.pulseOximeter => 'SpO2 & denyut nadi',
    DeviceType.thermometer => 'Suhu tubuh',
    DeviceType.weightScale => 'Berat & komposisi tubuh',
    DeviceType.gripStrength => 'Genggam tangan (Squegg)',
  };

  String get iconAsset => switch (this) {
    DeviceType.tensimeter => 'assets/icons/ic_health_station_2.svg',
    DeviceType.pulseOximeter => 'assets/icons/ic_pulse.svg',
    DeviceType.thermometer => 'assets/icons/ic_thermometer.svg',
    DeviceType.weightScale => 'assets/icons/ic_ws.svg',
    DeviceType.gripStrength => 'assets/icons/ic_grip.svg',
  };

  Color get iconColor => switch (this) {
    DeviceType.tensimeter => const Color(0xFFD94948),
    DeviceType.pulseOximeter => const Color(0xFF3A73D7),
    DeviceType.thermometer => const Color(0xFFE08A2E),
    DeviceType.weightScale => const Color(0xFF8751B1),
    DeviceType.gripStrength => const Color(0xFF1CB27C),
  };

  Color get iconBgColor => switch (this) {
    DeviceType.tensimeter => const Color(0xFFF9EAE6),
    DeviceType.pulseOximeter => const Color(0xFFE6F0F9),
    DeviceType.thermometer => const Color(0xFFFFF6E9),
    DeviceType.weightScale => const Color(0xFFF6E6F9),
    DeviceType.gripStrength => const Color(0xFFE6F9EF),
  };

  static DeviceType? fromName(String? name) {
    for (final t in DeviceType.values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// Status koneksi satu alat, seperti yang dilihat petugas.
///
/// Sengaja tidak ada `notFound`/`disconnected`: alat yang terdaftar punya
/// perintah auto-connect, jadi alat yang belum melapor berarti [waiting].
enum DeviceStatus {
  /// Belum ada alat yang didaftarkan untuk jenis ini di perangkat ini.
  unregistered,

  /// Bluetooth mati / tidak didukung / izin ditolak.
  unavailable,

  /// Terdaftar, belum tersambung. Auto-connect menunggu alat dinyalakan.
  waiting,

  /// Sedang mencoba menyambung.
  connecting,

  /// Tersambung dan karakteristik sudah di-subscribe.
  connected;

  String get label => switch (this) {
    DeviceStatus.connected => 'Siap',
    DeviceStatus.connecting => 'Menghubungkan…',
    DeviceStatus.waiting => 'Menunggu alat…',
    DeviceStatus.unavailable => 'Bluetooth tidak tersedia',
    DeviceStatus.unregistered => 'Belum didaftarkan',
  };

  Color get color => switch (this) {
    DeviceStatus.connected => const Color(0xFF1CB27C),
    DeviceStatus.connecting => const Color(0xFFE08A2E),
    DeviceStatus.waiting => const Color(0xFF7A7F8F),
    DeviceStatus.unavailable => const Color(0xFFD94948),
    DeviceStatus.unregistered => const Color(0xFF7A7F8F),
  };
}

/// Kemajuan satu alat untuk lansia yang sedang diukur.
enum MeasureStep {
  /// Belum ada bacaan.
  waiting,

  /// Bacaan sedang masuk (belum dikunci).
  measuring,

  /// Hasil dikunci — bacaan berikutnya diabaikan sampai "Ukur ulang".
  done,

  /// Dilewati untuk lansia ini.
  skipped;

  bool get isFinished =>
      this == MeasureStep.done || this == MeasureStep.skipped;
}

/// Apakah perangkat dalam kondisi bisa memakai BLE sama sekali.
enum BleGate {
  ok,
  unsupported,
  adapterOff,
  permissionDenied,
  permissionPermanentlyDenied;

  bool get isOk => this == BleGate.ok;

  String get message => switch (this) {
    BleGate.ok => '',
    BleGate.unsupported => 'Perangkat ini tidak mendukung Bluetooth LE.',
    BleGate.adapterOff => 'Bluetooth mati. Nyalakan untuk menyambung alat.',
    BleGate.permissionDenied =>
      'Izin Bluetooth belum diberikan. Ketuk untuk memberi izin.',
    BleGate.permissionPermanentlyDenied =>
      'Izin Bluetooth ditolak. Buka pengaturan aplikasi untuk mengizinkan.',
  };

  String get actionLabel => switch (this) {
    BleGate.adapterOff => 'Nyalakan',
    BleGate.permissionDenied => 'Beri izin',
    BleGate.permissionPermanentlyDenied => 'Buka pengaturan',
    _ => '',
  };
}

const Object _unset = Object();

@immutable
class DeviceInfo {
  final DeviceType type;
  final DeviceStatus status;
  final String? macAddress;

  const DeviceInfo({required this.type, required this.status, this.macAddress});

  DeviceInfo copyWith({DeviceStatus? status, Object? macAddress = _unset}) {
    return DeviceInfo(
      type: type,
      status: status ?? this.status,
      macAddress: identical(macAddress, _unset)
          ? this.macAddress
          : macAddress as String?,
    );
  }
}

/// Alat BLE yang terikat ke perangkat ini untuk satu [DeviceType].
///
/// [remoteId] (MAC di Android) adalah satu-satunya identitas: beberapa model
/// (IF_B8B, KS M6100P, Squegg) mengiklankan nama yang sama di semua unit.
@immutable
class RegisteredDevice {
  final DeviceType type;
  final String remoteId;
  final String name;

  const RegisteredDevice({
    required this.type,
    required this.remoteId,
    required this.name,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'remoteId': remoteId,
    'name': name,
  };

  static RegisteredDevice? fromJson(Map<String, dynamic> json) {
    final type = DeviceType.fromName(json['type'] as String?);
    final id = json['remoteId'] as String?;
    if (type == null || id == null) return null;
    return RegisteredDevice(
      type: type,
      remoteId: id,
      name: (json['name'] as String?) ?? '',
    );
  }
}

/// Alat BLE yang ditemukan saat mendaftarkan.
class ScannedBleDevice {
  final String remoteId;
  final String name;
  final int rssi;

  const ScannedBleDevice({
    required this.remoteId,
    required this.name,
    required this.rssi,
  });
}
