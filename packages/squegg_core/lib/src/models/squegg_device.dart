import 'package:flutter/foundation.dart';

/// A Squegg device discovered during a BLE scan.
@immutable
class SqueggDevice {
  /// Platform-specific device identifier.
  /// - Android: MAC address (e.g. `AA:BB:CC:DD:EE:FF`)
  /// - iOS: UUID (e.g. `12345678-1234-...`)
  final String id;

  /// Advertised name of the device (typically `weixin-nini`).
  final String name;

  /// Received signal strength in dBm. More negative = farther away.
  final int rssi;

  const SqueggDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  /// Signal quality label derived from [rssi].
  String get signalQuality {
    if (rssi >= -60) return 'Excellent';
    if (rssi >= -70) return 'Good';
    if (rssi >= -80) return 'Fair';
    return 'Weak';
  }

  SqueggDevice copyWith({String? id, String? name, int? rssi}) => SqueggDevice(
        id: id ?? this.id,
        name: name ?? this.name,
        rssi: rssi ?? this.rssi,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SqueggDevice && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SqueggDevice(id: $id, name: $name, rssi: $rssi dBm)';
}
