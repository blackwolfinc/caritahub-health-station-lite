// Batas normal mengikuti regulasi / pedoman Kementerian Kesehatan RI:
// - Tekanan darah: PNPK Tata Laksana Hipertensi Dewasa
//   (KMK HK.01.07/MENKES/4634/2021) — hipertensi bila ≥ 140/90 mmHg, untuk
//   semua umur termasuk lansia; hipotensi < 90/60 mmHg (Kemenkes).
// - Nadi dewasa 60–100 kali/menit; SpO2 normal ≥ 95 % (pedoman Kemenkes);
//   suhu tubuh normal 36,5–37,5 °C, demam > 37,5 °C (Kemenkes).
// - IMT: klasifikasi Kemenkes RI (P2PTM) — normal 18,5–25,0.
// Nilai dinilai dari angka yang tampil/tercetak (suhu & IMT 1 desimal,
// SpO2 bulat), supaya "37,5 °C" tidak berstatus demam.
// Hanya parameter yang punya batas resmi di Indonesia yang dinilai; yang
// lain (komposisi tubuh, genggam, lingkar betis) ditampilkan angkanya saja.

class HealthRanges {
  HealthRanges._();

  static const int minSystolic = 90;
  static const int maxSystolic = 139;
  static const int minDiastolic = 60;
  static const int maxDiastolic = 89;
  static const int minHeartRate = 60;
  static const int maxHeartRate = 100;
  static const double minTemperature = 36.5;
  static const double maxTemperature = 37.5;
  static const int minOxygen = 95; // normal bila ≥ 95
  static const double minBmi = 18.5;
  static const double maxBmi = 25.0;

  /// Dibulatkan seperti yang tampil: suhu & IMT 1 desimal.
  static double round1(double v) => (v * 10).round() / 10;

  /// SpO2 tampil tanpa desimal.
  static double roundOxygen(double v) => v.roundToDouble();

  /// Nadi 0 = tidak terukur (isian manual / data lama).
  static int? validPulse(int? hr) => hr == null || hr <= 0 ? null : hr;

  static bool? bloodPressureNormal(int? sys, int? dia) {
    if (sys == null || dia == null) return null;
    return sys >= minSystolic &&
        sys <= maxSystolic &&
        dia >= minDiastolic &&
        dia <= maxDiastolic;
  }

  static bool? heartRateNormal(int? hr) {
    if (hr == null) return null;
    return hr >= minHeartRate && hr <= maxHeartRate;
  }

  static bool? temperatureNormal(double? t) {
    if (t == null) return null;
    final v = round1(t);
    return v >= minTemperature && v <= maxTemperature;
  }

  static bool? oxygenNormal(double? spo2) {
    if (spo2 == null) return null;
    return roundOxygen(spo2) >= minOxygen;
  }

  static bool? bmiNormal(double? bmi) {
    if (bmi == null) return null;
    final v = round1(bmi);
    return v >= minBmi && v <= maxBmi;
  }

  static const String systolicRange = '$minSystolic–$maxSystolic';
  static const String diastolicRange = '$minDiastolic–$maxDiastolic';
  static const String heartRateRange = '$minHeartRate–$maxHeartRate';
  static const String temperatureRange = '36,5–37,5';
  static const String oxygenRange = '≥ $minOxygen';
  static const String bmiRange = '18,5–25,0';
}
