/// Batas nilai yang masuk akal secara fisiologis. Di luar batas ini hampir
/// pasti salah baca alat (mis. SFLOAT NaN 2047) atau salah ketik ("365" untuk
/// 36,5) — tidak disimpan dari alat, ditolak di isian manual, dan tidak
/// diekspor ke SATUSEHAT.
class Plausible {
  Plausible._();

  static const systolic = (50.0, 260.0);
  static const diastolic = (30.0, 160.0);
  static const heartRate = (30.0, 220.0);
  static const spo2 = (50.0, 100.0);
  static const temperature = (30.0, 45.0);
  static const weight = (10.0, 300.0);
  static const height = (50.0, 250.0);
  static const bmi = (8.0, 80.0);
  static const bodyFat = (1.0, 75.0);
  static const bodyWater = (20.0, 80.0);
  static const muscle = (10.0, 90.0);
  static const bone = (0.5, 20.0);
  static const protein = (5.0, 40.0);
  static const visceral = (1.0, 59.0);
  static const bmr = (500.0, 4000.0);
  static const grip = (0.5, 100.0);
  static const calf = (10.0, 80.0);

  static bool ok(num? v, (double, double) range) =>
      v != null && v.isFinite && v >= range.$1 && v <= range.$2;

  /// Nilai bila wajar, selain itu null.
  static double? keep(double? v, (double, double) range) =>
      ok(v, range) ? v : null;

  static String rangeText((double, double) r) {
    String f(double x) => x == x.roundToDouble()
        ? x.round().toString()
        : x.toString().replaceAll('.', ',');
    return '${f(r.$1)}–${f(r.$2)}';
  }
}
