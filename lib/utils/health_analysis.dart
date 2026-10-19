// Analisa hasil terhadap batas normal menurut regulasi / pedoman Kemenkes RI.
//
// Hanya parameter yang punya batas resmi di Indonesia yang dinilai:
// - Tekanan darah: PNPK Tata Laksana Hipertensi Dewasa
//   (KMK HK.01.07/MENKES/4634/2021). Kategori sama untuk semua umur dewasa,
//   termasuk lansia: optimal < 120/80, normal 120–129/80–84, normal-tinggi
//   130–139/85–89, hipertensi derajat 1 140–159/90–99, derajat 2 ≥ 160/100.
//   Hipotensi < 90/60 (Kemenkes).
// - Nadi, SpO2, suhu: [HealthRanges].
// - IMT: klasifikasi Kemenkes RI (P2PTM).
// Komposisi tubuh, kekuatan genggam, dan lingkar betis belum punya batas
// resmi Kemenkes — ditampilkan angkanya saja, tidak dinilai.
//
// Nilai dinilai dari angka yang tampil/tercetak (dibulatkan), dan nadi
// hanya satu nilai ([pulseOf]) — sama di analisa, struk, dan gauge.
//
// Hasil analisa adalah alat bantu baca, bukan diagnosis.

import '../models/health_record.dart';
import '../models/measurements.dart';
import 'health_ranges.dart';

enum FindingLevel { low, normal, high }

/// Satu hasil yang dianalisa.
class Finding {
  final String label;
  final String value;
  final FindingLevel level;

  /// Mis. "Normal", "Tinggi · derajat 1", "Rendah".
  final String status;

  /// Batas normal yang dipakai, mis. "90–139/60–89".
  final String normal;

  const Finding(this.label, this.value, this.level, this.status, this.normal);

  bool get abnormal => level != FindingLevel.normal;
}

String _n(num v, [int decimals = 0]) =>
    v.toStringAsFixed(decimals).replaceAll('.', ',');

/// Satu nilai nadi untuk analisa, struk, dan gauge: oksimeter bila ada,
/// selain itu tensimeter. 0 = tidak terukur.
int? pulseOf(AllMeasurements m) =>
    HealthRanges.validPulse(m.pulseOximeter.heartRate) ??
    HealthRanges.validPulse(m.tensimeter.pulse);

/// Kategori tekanan darah PNPK Hipertensi 2021 (yang lebih berat dari
/// sistolik/diastolik dipakai).
(FindingLevel, String) bloodPressureCategory(int sys, int dia) {
  if (sys >= 160 || dia >= 100) {
    return (FindingLevel.high, 'Tinggi · derajat 2');
  }
  if (sys >= 140 || dia >= 90) return (FindingLevel.high, 'Tinggi · derajat 1');
  if (sys < HealthRanges.minSystolic || dia < HealthRanges.minDiastolic) {
    return (FindingLevel.low, 'Rendah');
  }
  if (sys >= 130 || dia >= 85) return (FindingLevel.normal, 'Normal-tinggi');
  if (sys >= 120 || dia >= 80) return (FindingLevel.normal, 'Normal');
  return (FindingLevel.normal, 'Optimal');
}

/// Analisa hasil pada [r] yang punya batas resmi Kemenkes RI.
List<Finding> analyze(HealthRecord r) {
  final m = r.measurements;
  final out = <Finding>[];

  final t = m.tensimeter;
  if (t.systolic != null && t.diastolic != null) {
    final (level, status) = bloodPressureCategory(t.systolic!, t.diastolic!);
    out.add(
      Finding(
        'Tekanan darah',
        '${t.systolic}/${t.diastolic} mmHg',
        level,
        status,
        '${HealthRanges.systolicRange}/${HealthRanges.diastolicRange}',
      ),
    );
  }

  final hr = pulseOf(m);
  if (hr != null) {
    final level = hr < HealthRanges.minHeartRate
        ? FindingLevel.low
        : hr > HealthRanges.maxHeartRate
        ? FindingLevel.high
        : FindingLevel.normal;
    out.add(
      Finding('Denyut nadi', '$hr bpm', level, switch (level) {
        FindingLevel.low => 'Lambat',
        FindingLevel.high => 'Cepat',
        FindingLevel.normal => 'Normal',
      }, HealthRanges.heartRateRange),
    );
  }

  // Dinilai dari angka yang tertulis (bulat): 94,6 → "95 %" Normal.
  final rawSpo2 = m.pulseOximeter.spo2;
  final spo2 = rawSpo2 == null ? null : HealthRanges.roundOxygen(rawSpo2);
  if (spo2 != null) {
    final ok = HealthRanges.oxygenNormal(spo2)!;
    out.add(
      Finding(
        'SpO2',
        '${_n(spo2)} %',
        ok ? FindingLevel.normal : FindingLevel.low,
        ok ? 'Normal' : 'Rendah',
        '${HealthRanges.oxygenRange} %',
      ),
    );
  }

  // Dinilai dari angka yang tertulis (1 desimal): 37,53 → "37,5 °C" Normal.
  final rawTemp = m.thermometer.temperature;
  final temp = rawTemp == null ? null : HealthRanges.round1(rawTemp);
  if (temp != null) {
    final level = temp < HealthRanges.minTemperature
        ? FindingLevel.low
        : temp > HealthRanges.maxTemperature
        ? FindingLevel.high
        : FindingLevel.normal;
    out.add(
      Finding('Suhu tubuh', '${_n(temp, 1)} °C', level, switch (level) {
        FindingLevel.low => 'Di bawah normal',
        FindingLevel.high => 'Demam',
        FindingLevel.normal => 'Normal',
      }, '${HealthRanges.temperatureRange} °C'),
    );
  }

  // Dinilai dari angka yang tercetak (1 desimal), supaya "25,0" tidak
  // terbaca normal padahal ditandai gemuk.
  final rawBmi = m.weightScale.bmi;
  final bmi = rawBmi == null ? null : HealthRanges.round1(rawBmi);
  if (bmi != null) {
    final level = bmi < HealthRanges.minBmi
        ? FindingLevel.low
        : bmi > HealthRanges.maxBmi
        ? FindingLevel.high
        : FindingLevel.normal;
    out.add(
      Finding(
        'IMT',
        _n(bmi, 1),
        level,
        bmi < 17
            ? 'Sangat kurus'
            : bmi < 18.5
            ? 'Kurus'
            : bmi <= 25
            ? 'Normal'
            : bmi <= 27
            ? 'Gemuk'
            : 'Obesitas',
        HealthRanges.bmiRange,
      ),
    );
  }
  return out;
}

/// "Semua hasil dalam batas normal" / "2 dari 5 hasil perlu perhatian".
String analysisSummary(List<Finding> f) {
  final bad = f.where((e) => e.abnormal).length;
  if (f.isEmpty) return 'Belum ada hasil untuk dianalisa';
  return bad == 0
      ? 'Semua hasil dalam batas normal'
      : '$bad dari ${f.length} hasil perlu perhatian';
}
