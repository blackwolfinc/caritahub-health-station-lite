// Port dari caritacore (caritahub-mobile-core @ d22c334):
//   lib/tools/utils/health_parser_utils/{health_enums,health_models,health_parser_utils}.dart
// Disalin agar aplikasi ini tidak bergantung pada repo internal.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:math' as math;

import 'package:collection/collection.dart';

/// Model alat BLE yang dikenali, berdasarkan nama yang diiklankan.
enum BleDeviceModel {
  KS_M6100P('KS M6100P'),
  Yuwell_BO_YX110('Yuwell BO-YX110'),
  Bluetooth_BP('Bluetooth BP'),
  Yuwell_HT_YHW('Yuwell HT-YHW'),
  Yuwell_BP_YE670D('Yuwell BP-YE670D'),
  Yuwell_BP_YE670CR('Yuwell BP-YE670CR'),
  FHR_666_BLE('FHR-666(BLE)'),
  IF_B8B('IF_B8B'),
  Yuwell_CM100('Yuwell CM100');

  final String deviceName;
  const BleDeviceModel(this.deviceName);

  bool get isKS_M6100P => this == BleDeviceModel.KS_M6100P;
  bool get isYuwell_BO_YX110 => this == BleDeviceModel.Yuwell_BO_YX110;
  bool get isBluetooth_BP => this == BleDeviceModel.Bluetooth_BP;
  bool get isYuwell_HT_YHW => this == BleDeviceModel.Yuwell_HT_YHW;

  /// KS M6100P dibaca dengan polling 1 detik; sisanya lewat notify.
  bool get isRead => this == BleDeviceModel.KS_M6100P;
  bool get isSubscribe => !isRead;

  /// Ada parser datanya di [HealthParserUtils]. CM100: format paket belum
  /// diketahui → tidak ditawarkan saat pendaftaran. Doppler tidak dipakai.
  bool get hasParser =>
      this != BleDeviceModel.Yuwell_CM100 && this != BleDeviceModel.FHR_666_BLE;

  static BleDeviceModel? fromDeviceName(String deviceName) {
    final exact = BleDeviceModel.values.firstWhereOrNull(
      (e) => e.deviceName.toLowerCase() == deviceName.toLowerCase(),
    );
    if (exact != null) return exact;
    final normalized = _normalizeDeviceName(deviceName).toLowerCase();
    return BleDeviceModel.values.firstWhereOrNull(
      (e) => e.deviceName.toLowerCase() == normalized,
    );
  }

  /// Membuang akhiran ID unik: "Yuwell BO-YX110-1da3" → "Yuwell BO-YX110".
  static String _normalizeDeviceName(String deviceName) {
    final parts = deviceName.split('-');
    if (parts.length <= 1) return deviceName.trim();
    return parts.sublist(0, parts.length - 1).join('-').trim();
  }

  BleDeviceKind? get kind {
    switch (this) {
      case BleDeviceModel.KS_M6100P:
      case BleDeviceModel.Yuwell_BO_YX110:
        return BleDeviceKind.oxymeter;
      case BleDeviceModel.Bluetooth_BP:
      case BleDeviceModel.Yuwell_HT_YHW:
        return BleDeviceKind.temperature;
      case BleDeviceModel.Yuwell_BP_YE670D:
      case BleDeviceModel.Yuwell_BP_YE670CR:
        return BleDeviceKind.bloodPressure;
      case BleDeviceModel.FHR_666_BLE:
        return BleDeviceKind.doppler;
      case BleDeviceModel.IF_B8B:
        return BleDeviceKind.weightScale;
      case BleDeviceModel.Yuwell_CM100:
        // Di caritacore CM100 tercatat sebagai oksimeter (cek pertama menang).
        return BleDeviceKind.oxymeter;
    }
  }

  String get serviceUUID => switch (this) {
    BleDeviceModel.KS_M6100P => 'fff0',
    BleDeviceModel.Yuwell_BO_YX110 => 'ffe0',
    BleDeviceModel.Bluetooth_BP => 'fff0',
    BleDeviceModel.Yuwell_HT_YHW => '1809',
    BleDeviceModel.Yuwell_BP_YE670D => '1810',
    BleDeviceModel.Yuwell_BP_YE670CR => '1810',
    BleDeviceModel.FHR_666_BLE => 'ae30',
    BleDeviceModel.IF_B8B => 'fff0',
    BleDeviceModel.Yuwell_CM100 => 'fff0',
  };

  String get characteristicUUID => switch (this) {
    BleDeviceModel.KS_M6100P => 'fff1',
    BleDeviceModel.Yuwell_BO_YX110 => 'ffe4',
    BleDeviceModel.Bluetooth_BP => 'fff1',
    BleDeviceModel.Yuwell_HT_YHW => '2a1c',
    BleDeviceModel.Yuwell_BP_YE670D => '2a35',
    BleDeviceModel.Yuwell_BP_YE670CR => '2a35',
    BleDeviceModel.FHR_666_BLE => 'ae02',
    BleDeviceModel.IF_B8B => 'fff3',
    BleDeviceModel.Yuwell_CM100 => 'fff3',
  };
}

enum BleDeviceKind {
  oxymeter,
  temperature,
  bloodPressure,
  doppler,
  weightScale;

  bool get isOxymeter => this == BleDeviceKind.oxymeter;
  bool get isTemperature => this == BleDeviceKind.temperature;
  bool get isBloodPressure => this == BleDeviceKind.bloodPressure;
  bool get isDoppler => this == BleDeviceKind.doppler;
  bool get isWeightScale => this == BleDeviceKind.weightScale;
}

class BloodPressureReading {
  final int systolic;
  final int diastolic;
  final int pulse;
  const BloodPressureReading({
    required this.systolic,
    required this.diastolic,
    required this.pulse,
  });
}

class OxymeterReading {
  final int? heartRate;
  final int? oxygen;
  const OxymeterReading({this.heartRate, this.oxygen});
}

class HealthParserUtils {
  HealthParserUtils._();

  static OxymeterReading parseOxymeter(List<int> value, BleDeviceModel model) {
    int? heartRate;
    int? oxygen;
    if (value.length >= 5 && model.isKS_M6100P) {
      heartRate = value[3];
      oxygen = value[4];
    }
    if (model.isYuwell_BO_YX110) {
      // Satu notifikasi bisa berisi beberapa frame "FE <panjang> <tipe> …"
      // (mis. 0x57 lalu 0x55). Nilai hanya ada di frame 0x55:
      // [4] nadi, [5] SpO2. Frame lain diabaikan. Byte sebelum 0xFE pertama
      // = potongan frame sebelumnya (aliran bergeser) → dilewati.
      var framed = false;
      var i = 0;
      while (i + 6 <= value.length) {
        final n = value[i + 1];
        if (value[i] != 0xFE || n < 6) {
          i++;
          continue;
        }
        framed = true;
        if (value[i + 2] == 0x55) {
          heartRate = value[i + 4];
          oxygen = value[i + 5];
        }
        i += n;
      }
      // Format lama caritacore (6 byte, [4] nadi, [5] SpO2) hanya bila
      // paket sama sekali tanpa 0xFE. Selain itu = sampah → tanpa nilai.
      if (!framed && value.length == 6 && !value.contains(0xFE)) {
        heartRate = value[4];
        oxygen = value[5];
      }
    }
    return OxymeterReading(heartRate: heartRate, oxygen: oxygen);
  }

  static double? parseTemperature(List<int> value, BleDeviceModel model) {
    if (value.length >= 3 && model.isYuwell_HT_YHW) {
      // 0x2A1C: [0] flag, [1..3] mantisa 24-bit bertanda, [4] eksponen
      // 8-bit bertanda (IEEE-11073 FLOAT). Paket 3–4 byte = format lama /100.
      var raw = (value[1] & 0xFF) | ((value[2] & 0xFF) << 8);
      var t = raw / 100.0;
      if (value.length >= 5) {
        raw |= (value[3] & 0xFF) << 16;
        if (raw >= 0x800000) raw -= 0x1000000;
        final exp = (value[4] & 0xFF) >= 0x80
            ? (value[4] & 0xFF) - 0x100
            : value[4] & 0xFF;
        t = exp < 0
            ? raw / math.pow(10, -exp)
            : (raw * math.pow(10, exp)).toDouble();
      }
      // Flag bit0 = Fahrenheit.
      final celsius = (value[0] & 0x01) != 0 ? (t - 32) * 5 / 9 : t;
      if (celsius >= 34.0 && celsius <= 42.0) return celsius;
    }
    if (value.length >= 9 && model.isBluetooth_BP) {
      return (value[5] - 0x30) * 10 +
          (value[6] - 0x30) +
          (value[8] - 0x30) * 0.1;
    }
    return null;
  }

  /// BLE Blood Pressure Measurement (0x2A35), format IEEE-11073.
  /// Flag: bit1 = cap waktu (7 byte), bit2 = nadi, bit3 = ID user, bit4 =
  /// status. Nadi tepat sesudah cap waktu (offset 7 atau 14).
  static BloodPressureReading? parseBloodPressure(List<int> value) {
    if (value.length < 7) return null;
    final flags = value[0];
    final systolic = (value[1] & 0xFF) | ((value[2] & 0xFF) << 8);
    final diastolic = (value[3] & 0xFF) | ((value[4] & 0xFF) << 8);
    var pulse = 0;
    if ((flags & 0x04) != 0) {
      var offset = (flags & 0x02) != 0 ? 14 : 7;
      // Tata letak caritacore: cap waktu terkirim walau bit1 tidak diset —
      // paket punya 7 byte lebih dari yang dinyatakan flag.
      final expected =
          offset +
          2 +
          ((flags & 0x08) != 0 ? 1 : 0) +
          ((flags & 0x10) != 0 ? 2 : 0);
      if (offset == 7 && value.length >= expected + 7) offset = 14;
      if (value.length >= offset + 2) {
        pulse = (value[offset] & 0xFF) | ((value[offset + 1] & 0xFF) << 8);
      }
    }
    return BloodPressureReading(
      systolic: systolic,
      diastolic: diastolic,
      pulse: pulse,
    );
  }
}
