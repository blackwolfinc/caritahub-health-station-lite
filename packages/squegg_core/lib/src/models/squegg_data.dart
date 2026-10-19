import 'package:flutter/foundation.dart';

/// Real-time grip data streamed from the Squegg device.
///
/// Parsed from a BLE notification packet on [SqueggConstants.characteristicUuid].
///
/// ## Packet fields
///
/// | Field          | Source                  | Description                                    |
/// |----------------|-------------------------|------------------------------------------------|
/// | [strength]     | bytes[3..null]          | Real-time instantaneous force in kg            |
/// | [isSqueezing]  | derived from [strength] | `true` when force ≥ 2 kg threshold             |
/// | [batteryCharge]| byte[1]                 | Battery % in 10 % steps                        |
///
/// ## isSqueezing
///
/// The device flag at byte[2] rapidly alternates `'0'`/`'1'` during a
/// sustained hold, so [isSqueezing] is derived from a force threshold
/// ([SqueggConstants.squeezeThreshold] = 2.0 kg) instead.  This gives
/// clean, monotonic `false → true → false` transitions per squeeze cycle.
@immutable
class SqueggData {
  /// Real-time grip force in kilograms, rounded to 1 decimal place.
  ///
  /// Derived from the ASCII decimal string at bytes[3..null] in the BLE
  /// packet.  Suitable for live force-feedback gauges and waveform charts.
  final double strength;

  /// Whether the user is currently applying significant force to the device.
  ///
  /// Derived from [strength] ≥ [SqueggConstants.squeezeThreshold] (2.0 kg).
  ///   • false → true  : squeeze starts
  ///   • true  → false : squeeze released  ← counted as one rep
  final bool isSqueezing;

  /// Battery charge as a percentage (10–100, in 10 % increments).
  final int batteryCharge;

  /// Timestamp when this reading was parsed.
  final DateTime timestamp;

  const SqueggData({
    required this.strength,
    required this.isSqueezing,
    required this.batteryCharge,
    required this.timestamp,
  });

  /// Convenience constructor that auto-sets [timestamp] to now.
  factory SqueggData.now({
    required double strength,
    required bool isSqueezing,
    required int batteryCharge,
  }) =>
      SqueggData(
        strength: strength,
        isSqueezing: isSqueezing,
        batteryCharge: batteryCharge,
        timestamp: DateTime.now(),
      );

  /// Normalized [strength] in the range [0.0, 1.0] relative to [maxKg].
  double normalizedStrength({double maxKg = 100.0}) =>
      (strength / maxKg).clamp(0.0, 1.0);

  SqueggData copyWith({
    double? strength,
    bool? isSqueezing,
    int? batteryCharge,
    DateTime? timestamp,
  }) =>
      SqueggData(
        strength: strength ?? this.strength,
        isSqueezing: isSqueezing ?? this.isSqueezing,
        batteryCharge: batteryCharge ?? this.batteryCharge,
        timestamp: timestamp ?? this.timestamp,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SqueggData &&
          strength == other.strength &&
          isSqueezing == other.isSqueezing &&
          batteryCharge == other.batteryCharge &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      Object.hash(strength, isSqueezing, batteryCharge, timestamp);

  @override
  String toString() =>
      'SqueggData(strength: ${strength}kg, isSqueezing: $isSqueezing, battery: $batteryCharge%)';
}
