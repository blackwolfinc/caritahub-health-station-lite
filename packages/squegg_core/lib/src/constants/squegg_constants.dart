/// BLE constants for Squegg Smart Hand Grip Trainer
class SqueggConstants {
  SqueggConstants._();

  /// BLE advertised device name fragment used for scanning.
  /// Matches both "Squegg_1" (international) and "weixin-nini" (original CN).
  static const String deviceName = 'squegg';

  /// Fallback name fragment for original Chinese firmware devices.
  static const String deviceNameAlt = 'weixin-nini';

  /// Primary GATT service UUID
  static const String serviceUuid = '0000ffb0-0000-1000-8000-00805f9b34fb';

  /// Notify/read characteristic UUID for grip data
  static const String characteristicUuid = '0000ffb2-0000-1000-8000-00805f9b34fb';

  /// Default scan timeout
  static const Duration scanTimeout = Duration(seconds: 15);

  /// Minimum bytes expected in a valid packet
  static const int minPacketLength = 4;

  /// Battery percentage step — battery raw value maps to multiples of 10
  static const int batteryStep = 10;

  /// Maximum expected grip strength (kg) — used for UI normalization.
  static const double maxStrengthKg = 100.0;

  /// Minimum force (kg) to consider the device actively squeezed.
  ///
  /// The Squegg_1 firmware byte[2] "squeeze flag" rapidly alternates true/false
  /// during a sustained hold, making it unsuitable for stable squeeze detection
  /// or rep counting.  Deriving [SqueggData.isSqueezing] from a force threshold
  /// instead gives clean, monotonic true→false transitions per squeeze cycle.
  ///
  /// Value matches the lower boundary used in the official SDK demo app.
  static const double squeezeThreshold = 2.0;
}
