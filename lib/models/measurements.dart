import 'package:flutter/foundation.dart';

/// Sentinel supaya copyWith bisa membedakan "tidak diubah" dari "set ke null".
const Object _u = Object();

T? _pick<T>(Object? v, T? current) => identical(v, _u) ? current : v as T?;

double? _d(Object? v) {
  if (v is! num) return null;
  final d = v.toDouble();
  return d.isFinite ? d : null;
}

/// NaN/Infinity tidak bisa disimpan sebagai JSON — simpan sebagai kosong.
double? _f(double? v) => (v != null && v.isFinite) ? v : null;
int? _i(Object? v) => v is num ? v.toInt() : null;

@immutable
class TensimeterData {
  final int? systolic;
  final int? diastolic;
  final int? pulse;

  const TensimeterData({this.systolic, this.diastolic, this.pulse});

  bool get isEmpty => systolic == null && diastolic == null && pulse == null;

  TensimeterData copyWith({
    Object? systolic = _u,
    Object? diastolic = _u,
    Object? pulse = _u,
  }) => TensimeterData(
    systolic: _pick<int>(systolic, this.systolic),
    diastolic: _pick<int>(diastolic, this.diastolic),
    pulse: _pick<int>(pulse, this.pulse),
  );

  Map<String, dynamic> toJson() => {
    'systolic': systolic,
    'diastolic': diastolic,
    'pulse': pulse,
  };

  factory TensimeterData.fromJson(Map<String, dynamic>? j) => j == null
      ? const TensimeterData()
      : TensimeterData(
          systolic: _i(j['systolic']),
          diastolic: _i(j['diastolic']),
          pulse: _i(j['pulse']),
        );
}

@immutable
class PulseOximeterData {
  final double? spo2;
  final int? heartRate;

  const PulseOximeterData({this.spo2, this.heartRate});

  bool get isEmpty => spo2 == null && heartRate == null;

  PulseOximeterData copyWith({Object? spo2 = _u, Object? heartRate = _u}) =>
      PulseOximeterData(
        spo2: _pick<double>(spo2, this.spo2),
        heartRate: _pick<int>(heartRate, this.heartRate),
      );

  Map<String, dynamic> toJson() => {'spo2': _f(spo2), 'heartRate': heartRate};

  factory PulseOximeterData.fromJson(Map<String, dynamic>? j) => j == null
      ? const PulseOximeterData()
      : PulseOximeterData(spo2: _d(j['spo2']), heartRate: _i(j['heartRate']));
}

@immutable
class ThermometerData {
  /// Selalu disimpan dalam °C. [isCelsius] hanya preferensi tampilan.
  final double? temperature;
  final bool isCelsius;

  const ThermometerData({this.temperature, this.isCelsius = true});

  bool get isEmpty => temperature == null;

  ThermometerData copyWith({Object? temperature = _u, bool? isCelsius}) =>
      ThermometerData(
        temperature: _pick<double>(temperature, this.temperature),
        isCelsius: isCelsius ?? this.isCelsius,
      );

  Map<String, dynamic> toJson() => {'temperature': _f(temperature)};

  factory ThermometerData.fromJson(Map<String, dynamic>? j) => j == null
      ? const ThermometerData()
      : ThermometerData(temperature: _d(j['temperature']));
}

@immutable
class WeightScaleData {
  final double? weight;
  final double? bmi;
  final double? bodyScore;
  final int? bmr;
  final double? bodyWater;
  final double? bodyWaterPercent;
  final double? bodyFatKg;
  final double? bodyFatPercent;
  final double? proteinMass;
  final double? proteinPercent;
  final double? muscleMass;
  final double? musclePercent;
  final double? boneMineral;
  final double? boneMineralPercent;
  final double? visceralFatRate;
  final String? bodyType;

  const WeightScaleData({
    this.weight,
    this.bmi,
    this.bodyScore,
    this.bmr,
    this.bodyWater,
    this.bodyWaterPercent,
    this.bodyFatKg,
    this.bodyFatPercent,
    this.proteinMass,
    this.proteinPercent,
    this.muscleMass,
    this.musclePercent,
    this.boneMineral,
    this.boneMineralPercent,
    this.visceralFatRate,
    this.bodyType,
  });

  bool get isEmpty => weight == null && bmi == null;

  WeightScaleData copyWith({
    Object? weight = _u,
    Object? bmi = _u,
    Object? bodyScore = _u,
    Object? bmr = _u,
    Object? bodyWater = _u,
    Object? bodyWaterPercent = _u,
    Object? bodyFatKg = _u,
    Object? bodyFatPercent = _u,
    Object? proteinMass = _u,
    Object? proteinPercent = _u,
    Object? muscleMass = _u,
    Object? musclePercent = _u,
    Object? boneMineral = _u,
    Object? boneMineralPercent = _u,
    Object? visceralFatRate = _u,
    Object? bodyType = _u,
  }) => WeightScaleData(
    weight: _pick<double>(weight, this.weight),
    bmi: _pick<double>(bmi, this.bmi),
    bodyScore: _pick<double>(bodyScore, this.bodyScore),
    bmr: _pick<int>(bmr, this.bmr),
    bodyWater: _pick<double>(bodyWater, this.bodyWater),
    bodyWaterPercent: _pick<double>(bodyWaterPercent, this.bodyWaterPercent),
    bodyFatKg: _pick<double>(bodyFatKg, this.bodyFatKg),
    bodyFatPercent: _pick<double>(bodyFatPercent, this.bodyFatPercent),
    proteinMass: _pick<double>(proteinMass, this.proteinMass),
    proteinPercent: _pick<double>(proteinPercent, this.proteinPercent),
    muscleMass: _pick<double>(muscleMass, this.muscleMass),
    musclePercent: _pick<double>(musclePercent, this.musclePercent),
    boneMineral: _pick<double>(boneMineral, this.boneMineral),
    boneMineralPercent: _pick<double>(
      boneMineralPercent,
      this.boneMineralPercent,
    ),
    visceralFatRate: _pick<double>(visceralFatRate, this.visceralFatRate),
    bodyType: _pick<String>(bodyType, this.bodyType),
  );

  Map<String, dynamic> toJson() => {
    'weight': _f(weight),
    'bmi': _f(bmi),
    'bodyScore': _f(bodyScore),
    'bmr': bmr,
    'bodyWater': _f(bodyWater),
    'bodyWaterPercent': _f(bodyWaterPercent),
    'bodyFatKg': _f(bodyFatKg),
    'bodyFatPercent': _f(bodyFatPercent),
    'proteinMass': _f(proteinMass),
    'proteinPercent': _f(proteinPercent),
    'muscleMass': _f(muscleMass),
    'musclePercent': _f(musclePercent),
    'boneMineral': _f(boneMineral),
    'boneMineralPercent': _f(boneMineralPercent),
    'visceralFatRate': _f(visceralFatRate),
    'bodyType': bodyType,
  };

  factory WeightScaleData.fromJson(Map<String, dynamic>? j) => j == null
      ? const WeightScaleData()
      : WeightScaleData(
          weight: _d(j['weight']),
          bmi: _d(j['bmi']),
          bodyScore: _d(j['bodyScore']),
          bmr: _i(j['bmr']),
          bodyWater: _d(j['bodyWater']),
          bodyWaterPercent: _d(j['bodyWaterPercent']),
          bodyFatKg: _d(j['bodyFatKg']),
          bodyFatPercent: _d(j['bodyFatPercent']),
          proteinMass: _d(j['proteinMass']),
          proteinPercent: _d(j['proteinPercent']),
          muscleMass: _d(j['muscleMass']),
          musclePercent: _d(j['musclePercent']),
          boneMineral: _d(j['boneMineral']),
          boneMineralPercent: _d(j['boneMineralPercent']),
          visceralFatRate: _d(j['visceralFatRate']),
          bodyType: j['bodyType'] as String?,
        );
}

enum GripSide { left, right }

@immutable
class GripStrengthData {
  final double? gripLeft1;
  final double? gripLeft2;
  final double? gripLeft3;
  final double? gripRight1;
  final double? gripRight2;
  final double? gripRight3;

  const GripStrengthData({
    this.gripLeft1,
    this.gripLeft2,
    this.gripLeft3,
    this.gripRight1,
    this.gripRight2,
    this.gripRight3,
  });

  static double? _best(List<double?> values) => values
      .whereType<double>()
      .fold<double?>(null, (max, v) => max == null || v > max ? v : max);

  /// Nilai terbaik (maksimum) dari 3 percobaan tangan kiri.
  double? get gripLeft => _best([gripLeft1, gripLeft2, gripLeft3]);

  /// Nilai terbaik (maksimum) dari 3 percobaan tangan kanan.
  double? get gripRight => _best([gripRight1, gripRight2, gripRight3]);

  bool get isEmpty => gripLeft == null && gripRight == null;

  GripStrengthData copyWith({
    Object? gripLeft1 = _u,
    Object? gripLeft2 = _u,
    Object? gripLeft3 = _u,
    Object? gripRight1 = _u,
    Object? gripRight2 = _u,
    Object? gripRight3 = _u,
  }) => GripStrengthData(
    gripLeft1: _pick<double>(gripLeft1, this.gripLeft1),
    gripLeft2: _pick<double>(gripLeft2, this.gripLeft2),
    gripLeft3: _pick<double>(gripLeft3, this.gripLeft3),
    gripRight1: _pick<double>(gripRight1, this.gripRight1),
    gripRight2: _pick<double>(gripRight2, this.gripRight2),
    gripRight3: _pick<double>(gripRight3, this.gripRight3),
  );

  Map<String, dynamic> toJson() => {
    'gripLeft1': _f(gripLeft1),
    'gripLeft2': _f(gripLeft2),
    'gripLeft3': _f(gripLeft3),
    'gripRight1': _f(gripRight1),
    'gripRight2': _f(gripRight2),
    'gripRight3': _f(gripRight3),
  };

  factory GripStrengthData.fromJson(Map<String, dynamic>? j) => j == null
      ? const GripStrengthData()
      : GripStrengthData(
          gripLeft1: _d(j['gripLeft1']),
          gripLeft2: _d(j['gripLeft2']),
          gripLeft3: _d(j['gripLeft3']),
          gripRight1: _d(j['gripRight1']),
          gripRight2: _d(j['gripRight2']),
          gripRight3: _d(j['gripRight3']),
        );
}

@immutable
class OthersMeasurementData {
  final double? height;
  final double? calfCircumference;

  const OthersMeasurementData({this.height, this.calfCircumference});

  bool get isEmpty => height == null && calfCircumference == null;

  OthersMeasurementData copyWith({
    Object? height = _u,
    Object? calfCircumference = _u,
  }) => OthersMeasurementData(
    height: _pick<double>(height, this.height),
    calfCircumference: _pick<double>(calfCircumference, this.calfCircumference),
  );

  Map<String, dynamic> toJson() => {
    'height': _f(height),
    'calfCircumference': _f(calfCircumference),
  };

  factory OthersMeasurementData.fromJson(Map<String, dynamic>? j) => j == null
      ? const OthersMeasurementData()
      : OthersMeasurementData(
          height: _d(j['height']),
          calfCircumference: _d(j['calfCircumference']),
        );
}

@immutable
class AllMeasurements {
  final TensimeterData tensimeter;
  final PulseOximeterData pulseOximeter;
  final ThermometerData thermometer;
  final WeightScaleData weightScale;
  final GripStrengthData gripStrength;
  final OthersMeasurementData others;

  const AllMeasurements({
    this.tensimeter = const TensimeterData(),
    this.pulseOximeter = const PulseOximeterData(),
    this.thermometer = const ThermometerData(),
    this.weightScale = const WeightScaleData(),
    this.gripStrength = const GripStrengthData(),
    this.others = const OthersMeasurementData(),
  });

  /// Ada hasil dari salah satu alat. Kartu "Lainnya" tidak dihitung karena
  /// tingginya bisa terisi otomatis dari profil (sama dengan aplikasi asli).
  bool get hasAnyData =>
      !tensimeter.isEmpty ||
      !pulseOximeter.isEmpty ||
      !thermometer.isEmpty ||
      !weightScale.isEmpty ||
      !gripStrength.isEmpty;

  /// Alat yang belum menghasilkan angka apa pun.
  List<String> get missingLabels => [
    if (tensimeter.systolic == null) 'Tensimeter',
    if (pulseOximeter.spo2 == null) 'Oksimeter',
    if (thermometer.temperature == null) 'Termometer',
    if (weightScale.weight == null) 'Timbangan',
    if (gripStrength.gripLeft == null || gripStrength.gripRight == null)
      'Kekuatan genggam',
  ];

  AllMeasurements copyWith({
    TensimeterData? tensimeter,
    PulseOximeterData? pulseOximeter,
    ThermometerData? thermometer,
    WeightScaleData? weightScale,
    GripStrengthData? gripStrength,
    OthersMeasurementData? others,
  }) => AllMeasurements(
    tensimeter: tensimeter ?? this.tensimeter,
    pulseOximeter: pulseOximeter ?? this.pulseOximeter,
    thermometer: thermometer ?? this.thermometer,
    weightScale: weightScale ?? this.weightScale,
    gripStrength: gripStrength ?? this.gripStrength,
    others: others ?? this.others,
  );

  Map<String, dynamic> toJson() => {
    'tensimeter': tensimeter.toJson(),
    'pulseOximeter': pulseOximeter.toJson(),
    'thermometer': thermometer.toJson(),
    'weightScale': weightScale.toJson(),
    'gripStrength': gripStrength.toJson(),
    'others': others.toJson(),
  };

  factory AllMeasurements.fromJson(Map<String, dynamic>? j) {
    Map<String, dynamic>? m(String k) =>
        (j?[k] as Map?)?.cast<String, dynamic>();
    return AllMeasurements(
      tensimeter: TensimeterData.fromJson(m('tensimeter')),
      pulseOximeter: PulseOximeterData.fromJson(m('pulseOximeter')),
      thermometer: ThermometerData.fromJson(m('thermometer')),
      weightScale: WeightScaleData.fromJson(m('weightScale')),
      gripStrength: GripStrengthData.fromJson(m('gripStrength')),
      others: OthersMeasurementData.fromJson(m('others')),
    );
  }
}
