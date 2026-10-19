import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/health_record.dart';
import 'health_ranges.dart';

/// Warna zona — lembut tapi tetap terbaca di layar iMin di bawah lampu terang.
class ZoneColors {
  ZoneColors._();
  static const good = Color(0xFF3FBF8A);
  static const watch = Color(0xFFF2BE4E);
  static const high = Color(0xFFF08A4B);
  static const danger = Color(0xFFE05A59);
  static const neutral = Color(0xFFC9CCD6);
}

@immutable
class GaugeZone {
  final double from;
  final double to;
  final String label;
  final Color color;
  const GaugeZone(this.from, this.to, this.label, this.color);
}

/// Skala visual untuk satu besaran: rentang, zona, dan aturan pengelompokan.
@immutable
class GaugeSpec {
  final String caption;
  final String unit;
  final double min;
  final double max;
  final List<GaugeZone> zones;

  /// Angka di bawah bilah (batas zona yang penting).
  final List<double> ticks;
  final int decimals;

  /// Teks rentang normal saat belum ada nilai.
  final String normalText;

  /// Indeks zona untuk nilai; mengikuti aturan normal di [HealthRanges].
  final int Function(double v) classify;

  const GaugeSpec({
    required this.caption,
    required this.unit,
    required this.min,
    required this.max,
    required this.zones,
    required this.ticks,
    required this.classify,
    required this.normalText,
    this.decimals = 0,
  });

  /// Zona dari angka yang tampil (dibulatkan [decimals]) — 37,53 tampil
  /// "37,5" dan dinilai Normal, sama dengan analisa & struk.
  GaugeZone zoneOf(double v) =>
      zones[classify(shown(v)).clamp(0, zones.length - 1)];

  double shown(double v) {
    final f = math.pow(10, decimals);
    return (v * f).round() / f;
  }
}

/// Rentang & zona yang dipakai di layar ukur, hasil, dan grafik tren.
///
/// Batas normal mengikuti [HealthRanges] (pedoman Kemenkes RI) supaya
/// sama dengan tanda `*` di struk. Label sama dengan kartu analisa
/// (istilah PNPK Hipertensi 2021). Kategori di luar normal hanya alat bantu
/// baca, bukan diagnosis.
class HealthZones {
  HealthZones._();

  static final systolic = GaugeSpec(
    caption: 'Sistolik',
    unit: 'mmHg',
    min: 80,
    max: 180,
    normalText: 'Normal ${HealthRanges.systolicRange}',
    ticks: const [90, 140, 160],
    zones: const [
      GaugeZone(80, 90, 'Rendah', ZoneColors.watch),
      GaugeZone(90, 140, 'Normal', ZoneColors.good),
      GaugeZone(140, 160, 'Tinggi', ZoneColors.high),
      GaugeZone(160, 180, 'Tinggi · derajat 2', ZoneColors.danger),
    ],
    classify: (v) => v < HealthRanges.minSystolic
        ? 0
        : v <= HealthRanges.maxSystolic
        ? 1
        : v < 160
        ? 2
        : 3,
  );

  static final diastolic = GaugeSpec(
    caption: 'Diastolik',
    unit: 'mmHg',
    min: 50,
    max: 120,
    normalText: 'Normal ${HealthRanges.diastolicRange}',
    ticks: const [60, 90, 100],
    zones: const [
      GaugeZone(50, 60, 'Rendah', ZoneColors.watch),
      GaugeZone(60, 90, 'Normal', ZoneColors.good),
      GaugeZone(90, 100, 'Tinggi', ZoneColors.high),
      GaugeZone(100, 120, 'Tinggi · derajat 2', ZoneColors.danger),
    ],
    classify: (v) => v < HealthRanges.minDiastolic
        ? 0
        : v <= HealthRanges.maxDiastolic
        ? 1
        : v < 100
        ? 2
        : 3,
  );

  static final spo2 = GaugeSpec(
    caption: 'SpO2',
    unit: '%',
    min: 85,
    max: 100,
    normalText: 'Normal ≥ ${HealthRanges.minOxygen}%',
    ticks: const [95, 90],
    zones: const [
      GaugeZone(85, 90, 'Rendah', ZoneColors.danger),
      GaugeZone(90, 95, 'Rendah', ZoneColors.watch),
      GaugeZone(95, 100, 'Normal', ZoneColors.good),
    ],
    // Normal bila ≥ 95 (HealthRanges.oxygenNormal); < 90 warna lebih tegas.
    classify: (v) => v < 90
        ? 0
        : v < HealthRanges.minOxygen
        ? 1
        : 2,
  );

  static final heartRate = GaugeSpec(
    caption: 'Nadi',
    unit: 'bpm',
    min: 40,
    max: 140,
    normalText: 'Normal ${HealthRanges.heartRateRange}',
    ticks: const [60, 100],
    zones: const [
      GaugeZone(40, 60, 'Lambat', ZoneColors.watch),
      GaugeZone(60, 100, 'Normal', ZoneColors.good),
      GaugeZone(100, 140, 'Cepat', ZoneColors.high),
    ],
    classify: (v) => v < HealthRanges.minHeartRate
        ? 0
        : v <= HealthRanges.maxHeartRate
        ? 1
        : 2,
  );

  static final temperature = GaugeSpec(
    caption: 'Suhu',
    unit: '°C',
    min: 34.5,
    max: 39.5,
    decimals: 1,
    normalText: 'Normal ${HealthRanges.temperatureRange}',
    ticks: const [36.5, 37.5],
    // Kemenkes: normal 36,5–37,5 °C, demam > 37,5 °C.
    zones: const [
      GaugeZone(34.5, 36.5, 'Di bawah normal', ZoneColors.watch),
      GaugeZone(36.5, 37.5, 'Normal', ZoneColors.good),
      GaugeZone(37.5, 39.5, 'Demam', ZoneColors.danger),
    ],
    classify: (v) => v < HealthRanges.minTemperature
        ? 0
        : v <= HealthRanges.maxTemperature
        ? 1
        : 2,
  );

  /// Kategori IMT Kemenkes RI.
  static final bmi = GaugeSpec(
    caption: 'IMT',
    unit: '',
    min: 14,
    max: 32,
    decimals: 1,
    normalText: 'Normal ${HealthRanges.bmiRange}',
    ticks: const [18.5, 25, 17, 27],
    zones: const [
      GaugeZone(14, 17, 'Sangat kurus', ZoneColors.danger),
      GaugeZone(17, 18.5, 'Kurus', ZoneColors.watch),
      GaugeZone(18.5, 25, 'Normal', ZoneColors.good),
      GaugeZone(25, 27, 'Gemuk', ZoneColors.high),
      GaugeZone(27, 32, 'Obesitas', ZoneColors.danger),
    ],
    classify: (v) => v < 17
        ? 0
        : v < HealthRanges.minBmi
        ? 1
        : v <= HealthRanges.maxBmi
        ? 2
        : v <= 27
        ? 3
        : 4,
  );

  /// Kekuatan genggam terbaik. Belum ada batas normal resmi Kemenkes RI,
  /// jadi hanya skala tanpa penilaian (sama untuk L/P).
  static GaugeSpec grip(Gender? g) => GaugeSpec(
    caption: 'Genggam terbaik',
    unit: 'kg',
    min: 0,
    max: 50,
    decimals: 1,
    normalText: 'Tanpa batas resmi',
    ticks: const [10, 20, 30, 40],
    zones: const [GaugeZone(0, 50, 'Hasil', ZoneColors.neutral)],
    classify: (_) => 0,
  );
}
