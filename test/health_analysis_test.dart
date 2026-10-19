import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/utils/health_analysis.dart';

HealthRecord rec(AllMeasurements m, {int age = 68}) => HealthRecord(
  id: 'X',
  createdAt: DateTime(2026, 10, 19),
  profile: PersonProfile(name: 'A', gender: Gender.female, age: age),
  measurements: m,
);

void main() {
  // PNPK Tata Laksana Hipertensi Dewasa (KMK HK.01.07/MENKES/4634/2021).
  test('kategori tekanan darah PNPK, sama untuk semua umur', () {
    expect(bloodPressureCategory(115, 75).$2, 'Optimal');
    expect(bloodPressureCategory(125, 82).$2, 'Normal');
    expect(bloodPressureCategory(135, 86).$2, 'Normal-tinggi');
    expect(bloodPressureCategory(145, 80).$2, 'Tinggi · derajat 1');
    expect(bloodPressureCategory(130, 92).$2, 'Tinggi · derajat 1');
    expect(bloodPressureCategory(165, 85).$2, 'Tinggi · derajat 2');
    expect(bloodPressureCategory(85, 55).$2, 'Rendah');
    expect(bloodPressureCategory(135, 86).$1, FindingLevel.normal);
    expect(bloodPressureCategory(145, 80).$1, FindingLevel.high);
    // Lansia tidak punya batas berbeda.
    for (final age in [40, 68, 85]) {
      final f = analyze(
        rec(
          const AllMeasurements(
            tensimeter: TensimeterData(systolic: 145, diastolic: 80),
          ),
          age: age,
        ),
      );
      expect(f.single.abnormal, isTrue, reason: 'umur $age');
    }
  });

  test('hanya parameter dengan batas resmi yang dinilai', () {
    final f = analyze(
      rec(
        const AllMeasurements(
          tensimeter: TensimeterData(systolic: 128, diastolic: 82, pulse: 76),
          pulseOximeter: PulseOximeterData(spo2: 95, heartRate: 75),
          thermometer: ThermometerData(temperature: 37.8),
          weightScale: WeightScaleData(
            weight: 60,
            bmi: 26.1,
            bodyFatPercent: 40,
          ),
          gripStrength: GripStrengthData(gripLeft1: 12),
          others: OthersMeasurementData(calfCircumference: 29),
        ),
      ),
    );
    expect(f.map((e) => e.label), [
      'Tekanan darah',
      'Denyut nadi',
      'SpO2',
      'Suhu tubuh',
      'IMT',
    ]);
    expect(f[2].status, 'Normal'); // SpO2 95 % normal (≥ 95)
    expect(f[3].status, 'Demam'); // > 37,5 °C
    expect(f[4].status, 'Gemuk'); // > 25,0–27,0
    expect(analysisSummary(f), '2 dari 5 hasil perlu perhatian');
  });
}
