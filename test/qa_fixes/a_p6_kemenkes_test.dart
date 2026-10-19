// QA persona 6 — kepatuhan Kemenkes RI (regresi P6-2/3/5/6/7/8).
// Nilai dinilai dari angka yang tampil (dibulatkan).
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/utils/health_analysis.dart';
import 'package:health_station_lite/utils/health_ranges.dart';
import 'package:health_station_lite/utils/health_zones.dart';

HealthRecord rec(
  AllMeasurements m, {
  int? age = 68,
  Gender? g = Gender.female,
}) => HealthRecord(
  id: 'X',
  createdAt: DateTime(2026, 10, 19),
  profile: PersonProfile(name: 'A', gender: g, age: age),
  measurements: m,
);

Finding one(AllMeasurements m, String label) =>
    analyze(rec(m)).singleWhere((f) => f.label == label);

Finding bp(int s, int d) => one(
  AllMeasurements(
    tensimeter: TensimeterData(systolic: s, diastolic: d),
  ),
  'Tekanan darah',
);
Finding temp(double t) => one(
  AllMeasurements(thermometer: ThermometerData(temperature: t)),
  'Suhu tubuh',
);
Finding spo2(double v) =>
    one(AllMeasurements(pulseOximeter: PulseOximeterData(spo2: v)), 'SpO2');
Finding bmi(double v) =>
    one(AllMeasurements(weightScale: WeightScaleData(bmi: v)), 'IMT');
Finding hr(int v) => one(
  AllMeasurements(pulseOximeter: PulseOximeterData(heartRate: v)),
  'Denyut nadi',
);

String z(GaugeSpec s, double v) => s.zoneOf(v).label;

void main() {
  group('Tekanan darah PNPK KMK 4634/2021 — batas tepat', () {
    test('139/89 normal (normal-tinggi)', () {
      expect(bp(139, 89).level, FindingLevel.normal);
      expect(bp(139, 89).status, 'Normal-tinggi');
    });
    test('140/90, 140/89, 139/90 → hipertensi derajat 1', () {
      for (final (s, d) in [(140, 90), (140, 89), (139, 90), (159, 99)]) {
        expect(bp(s, d).level, FindingLevel.high, reason: '$s/$d');
        expect(bp(s, d).status, 'Tinggi · derajat 1', reason: '$s/$d');
      }
    });
    test('160/100, 160/80, 120/100 → derajat 2', () {
      for (final (s, d) in [(160, 100), (160, 80), (120, 100)]) {
        expect(bp(s, d).status, 'Tinggi · derajat 2', reason: '$s/$d');
      }
    });
    test('hipotensi < 90/60: 89/59, 89/70, 100/59 rendah; 90/60 normal', () {
      for (final (s, d) in [(89, 59), (89, 70), (100, 59)]) {
        expect(bp(s, d).level, FindingLevel.low, reason: '$s/$d');
      }
      expect(bp(90, 60).level, FindingLevel.normal);
      expect(bp(90, 60).status, 'Optimal');
    });
    test('kategori sama untuk semua umur (20–100) dan tanpa umur', () {
      for (final age in [20, 45, 60, 75, 90, 100, null]) {
        final f = analyze(
          rec(
            const AllMeasurements(
              tensimeter: TensimeterData(systolic: 140, diastolic: 90),
            ),
            age: age,
          ),
        );
        expect(f.single.status, 'Tinggi · derajat 1', reason: 'umur $age');
      }
    });
    test(
      'HealthRanges.bloodPressureNormal == analisa normal (grid 60–220/30–140)',
      () {
        for (var s = 60; s <= 220; s++) {
          for (var d = 30; d <= 140; d++) {
            final normal =
                bloodPressureCategory(s, d).$1 == FindingLevel.normal;
            expect(
              HealthRanges.bloodPressureNormal(s, d),
              normal,
              reason: '$s/$d',
            );
          }
        }
      },
    );
  });

  group('SpO2 ≥ 95', () {
    test('94 rendah, 95 normal, 100 normal', () {
      expect(spo2(94).level, FindingLevel.low);
      expect(spo2(95).level, FindingLevel.normal);
      expect(spo2(100).level, FindingLevel.normal);
    });
    test(
      'nilai pecahan 94,6: tertulis "95 %" → dinilai Normal (angka yang tampil)',
      () {
        final f = spo2(94.6);
        expect(f.value, '95 %');
        expect(f.level, FindingLevel.normal);
        expect(spo2(94.4).value, '94 %');
        expect(spo2(94.4).status, 'Rendah');
        expect(HealthRanges.oxygenNormal(94.6), isTrue);
        expect(z(HealthZones.spo2, 94.6), 'Normal');
      },
    );
  });

  group('Suhu 36,5–37,5 °C', () {
    test('36,4 rendah; 36,5 & 37,5 normal; 37,6 demam', () {
      expect(temp(36.4).level, FindingLevel.low);
      expect(temp(36.5).level, FindingLevel.normal);
      expect(temp(37.5).level, FindingLevel.normal);
      expect(temp(37.6).level, FindingLevel.high);
      expect(temp(37.6).status, 'Demam');
    });
    // Yuwell HT-YHW mengirim raw/100 (2 desimal) — health_device_models.dart:163.
    test(
      '37,53 dari termometer: tertulis "37,5 °C" tidak boleh berstatus Demam',
      () {
        final f = temp(37.53);
        expect(f.value, '37,5 °C');
        expect(
          f.status,
          'Normal',
          reason: 'tertulis ${f.value} tapi ${f.status}',
        );
      },
    );
    test(
      '36,46 dari termometer: tertulis "36,5 °C" tidak boleh Di bawah normal',
      () {
        final f = temp(36.46);
        expect(f.value, '36,5 °C');
        expect(
          f.status,
          'Normal',
          reason: 'tertulis ${f.value} tapi ${f.status}',
        );
      },
    );
  });

  group('IMT Kemenkes P2PTM 18,5–25,0', () {
    test('batas tepat', () {
      expect(bmi(16.9).status, 'Sangat kurus');
      expect(bmi(17.0).status, 'Kurus');
      expect(bmi(18.4).status, 'Kurus');
      expect(bmi(18.4).level, FindingLevel.low);
      expect(bmi(18.5).status, 'Normal');
      expect(bmi(25.0).status, 'Normal');
      expect(bmi(25.0).level, FindingLevel.normal);
      expect(bmi(25.1).status, 'Gemuk');
      expect(bmi(25.1).level, FindingLevel.high);
      expect(bmi(27.0).status, 'Gemuk');
      expect(bmi(27.1).status, 'Obesitas');
    });
    test(
      'dibulatkan 1 desimal: 24,96 & 25,04 → 25,0 Normal; 18,45 → 18,5 Normal',
      () {
        expect(bmi(24.96).status, 'Normal');
        expect(bmi(25.04).status, 'Normal');
        expect(bmi(18.46).status, 'Normal');
      },
    );
  });

  group('Nadi 60–100', () {
    test('59 lambat, 60 & 100 normal, 101 cepat', () {
      expect(hr(59).status, 'Lambat');
      expect(hr(60).status, 'Normal');
      expect(hr(100).status, 'Normal');
      expect(hr(101).status, 'Cepat');
    });
    test(
      'nadi tensimeter 0 (isi manual) tidak boleh menyembunyikan nadi oksimeter',
      () {
        final f = analyze(
          rec(
            const AllMeasurements(
              tensimeter: TensimeterData(
                systolic: 120,
                diastolic: 80,
                pulse: 0,
              ),
              pulseOximeter: PulseOximeterData(spo2: 97, heartRate: 130),
            ),
          ),
        );
        expect(f.singleWhere((e) => e.label == 'Denyut nadi').value, '130 bpm');
      },
    );
    test('nadi tensimeter 0 tanpa oksimeter → tidak ada temuan nadi', () {
      final f = analyze(
        rec(
          const AllMeasurements(
            tensimeter: TensimeterData(systolic: 120, diastolic: 80, pulse: 0),
          ),
        ),
      );
      expect(f.where((e) => e.label == 'Denyut nadi'), isEmpty);
    });
    test('nadi oksimeter diutamakan, tensimeter bila oksimeter kosong', () {
      expect(
        pulseOf(
          const AllMeasurements(
            tensimeter: TensimeterData(pulse: 72),
            pulseOximeter: PulseOximeterData(heartRate: 120),
          ),
        ),
        120,
      );
      expect(
        pulseOf(
          const AllMeasurements(
            tensimeter: TensimeterData(pulse: 72),
            pulseOximeter: PulseOximeterData(spo2: 97, heartRate: 0),
          ),
        ),
        72,
      );
      expect(pulseOf(const AllMeasurements()), isNull);
    });
  });

  group('Tidak dinilai: komposisi tubuh, genggam, betis', () {
    test('analyze() tanpa temuan untuk komposisi/genggam/betis', () {
      final f = analyze(
        rec(
          const AllMeasurements(
            weightScale: WeightScaleData(
              weight: 60,
              bodyFatPercent: 45,
              musclePercent: 20,
              visceralFatRate: 20,
              bodyScore: 40,
              bodyType: 'Sedikit gemuk',
            ),
            gripStrength: GripStrengthData(gripLeft1: 8, gripRight1: 9),
            others: OthersMeasurementData(calfCircumference: 25),
          ),
        ),
      );
      expect(f, isEmpty);
    });
    test('gauge genggam: satu zona netral untuk L/P/null', () {
      for (final g in [Gender.male, Gender.female, null]) {
        final s = HealthZones.grip(g);
        for (final v in [0.0, 5.0, 17.9, 18.0, 28.0, 50.0]) {
          expect(s.zoneOf(v).color, ZoneColors.neutral);
          expect(s.zoneOf(v).label, 'Hasil');
        }
      }
    });
  });

  group('Zona gauge (layar ukur/hasil) sama dengan analisa', () {
    test('batas sistolik/diastolik/nadi/suhu/IMT', () {
      expect(z(HealthZones.systolic, 89), 'Rendah');
      expect(z(HealthZones.systolic, 90), 'Normal');
      expect(z(HealthZones.systolic, 139), 'Normal');
      expect(z(HealthZones.systolic, 140), 'Tinggi');
      expect(z(HealthZones.diastolic, 59), 'Rendah');
      expect(z(HealthZones.diastolic, 60), 'Normal');
      expect(z(HealthZones.diastolic, 89), 'Normal');
      expect(z(HealthZones.diastolic, 90), 'Tinggi');
      expect(z(HealthZones.heartRate, 59), 'Lambat');
      expect(z(HealthZones.heartRate, 101), 'Cepat');
      expect(z(HealthZones.temperature, 36.4), 'Di bawah normal');
      expect(z(HealthZones.temperature, 36.5), 'Normal');
      expect(z(HealthZones.temperature, 37.5), 'Normal');
      expect(z(HealthZones.temperature, 37.6), 'Demam');
      expect(z(HealthZones.bmi, 18.4), 'Kurus');
      expect(z(HealthZones.bmi, 18.5), 'Normal');
      expect(z(HealthZones.bmi, 25.0), 'Normal');
      expect(z(HealthZones.bmi, 25.1), 'Gemuk');
      expect(z(HealthZones.spo2, 95), 'Normal');
      expect(z(HealthZones.spo2, 94) == 'Normal', isFalse);
    });
    test('IMT 25,04 (tertulis 25,0): zona gauge = status analisa', () {
      expect(z(HealthZones.bmi, 25.04), bmi(25.04).status);
    });
    test('IMT 18,46 (tertulis 18,5): zona gauge = status analisa', () {
      expect(z(HealthZones.bmi, 18.46), bmi(18.46).status);
    });
    test('suhu 37,53 (tertulis 37,5): zona gauge tidak Demam', () {
      expect(z(HealthZones.temperature, 37.53), 'Normal');
      expect(z(HealthZones.temperature, 36.46), 'Normal');
      expect(HealthRanges.temperatureNormal(37.53), isTrue);
      expect(HealthRanges.temperatureNormal(37.56), isFalse);
    });
    test('suhu rendah: label gauge = analisa (Di bawah normal)', () {
      expect(z(HealthZones.temperature, 36.0), temp(36.0).status);
    });
    test('SpO2 89: label gauge = analisa (Rendah)', () {
      expect(z(HealthZones.spo2, 89), spo2(89).status);
    });
    test('diastolik 100: label gauge memakai istilah PNPK (derajat 2)', () {
      expect(z(HealthZones.diastolic, 100), bp(120, 100).status);
      expect(z(HealthZones.systolic, 165), bp(165, 80).status);
    });
    test('caption gauge IMT memakai "IMT", bukan "BMI"', () {
      expect(HealthZones.bmi.caption, 'IMT');
      expect(HealthZones.bmi.normalText, isNot(contains('BMI')));
    });
    test('SpO2 94: label gauge sama dengan analisa (Rendah)', () {
      expect(z(HealthZones.spo2, 94), spo2(94).status);
    });
    test('sistolik 160: label gauge memakai istilah PNPK (derajat 2)', () {
      expect(z(HealthZones.systolic, 160), contains('derajat 2'));
    });
  });

  test('ringkasan analisa', () {
    expect(analysisSummary(const []), 'Belum ada hasil untuk dianalisa');
    final f = analyze(
      rec(
        const AllMeasurements(
          tensimeter: TensimeterData(systolic: 150, diastolic: 95, pulse: 70),
          pulseOximeter: PulseOximeterData(spo2: 93),
          thermometer: ThermometerData(temperature: 36.8),
        ),
      ),
    );
    expect(analysisSummary(f), '2 dari 4 hasil perlu perhatian');
  });
}
