import '../models/health_record.dart';

/// NIK (Nomor Induk Kependudukan) 16 digit:
///   PP KK CC  DD MM YY  NNNN
///   prov kab kec  tgl lahir (perempuan +40)  nomor urut
///
/// SATUSEHAT mencari pasien (IHS number) dengan NIK, jadi NIK wajib bila
/// hasil akan dikirim ke SATUSEHAT. Selain itu tetap opsional.
class Nik {
  Nik._();

  static const system = 'https://fhir.kemkes.go.id/id/nik';

  static String normalize(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Pesan kesalahan, atau null bila kosong/valid.
  static String? validate(String? raw, {DateTime? now}) {
    final v = normalize(raw ?? '');
    if (v.isEmpty) return null;
    if (v.length != 16) return 'NIK harus 16 angka (sekarang ${v.length})';
    final prov = int.parse(v.substring(0, 2));
    if (prov < 11 || prov > 96) return 'Kode provinsi NIK tidak dikenal';
    final day = int.parse(v.substring(6, 8));
    final month = int.parse(v.substring(8, 10));
    final d = day > 40 ? day - 40 : day;
    if (d < 1 || d > 31) return 'Tanggal lahir di NIK tidak valid';
    if (month < 1 || month > 12) return 'Bulan lahir di NIK tidak valid';
    if (v.substring(12) == '0000') return 'Nomor urut NIK tidak valid';
    // Tanggal yang tidak ada (31/04, 29/02 bukan kabisat) = salah ketik.
    if (_birth(v, now ?? DateTime.now()) == null) {
      return 'Tanggal lahir di NIK tidak ada di kalender';
    }
    return null;
  }

  static bool isValid(String? raw) {
    final v = normalize(raw ?? '');
    return v.length == 16 && validate(v) == null;
  }

  /// Tanggal lahir dari digit 7–12; null bila tanggal tidak ada.
  /// Abad ditebak: tanggal yang jatuh di masa depan dianggap 19xx.
  static DateTime? _birth(String v, DateTime today) {
    var day = int.parse(v.substring(6, 8));
    final month = int.parse(v.substring(8, 10));
    final yy = int.parse(v.substring(10, 12));
    if (day > 40) day -= 40;
    var year = 2000 + yy;
    var birth = DateTime(year, month, day);
    if (birth.isAfter(DateTime(today.year, today.month, today.day))) {
      year -= 100;
      birth = DateTime(year, month, day);
    }
    if (birth.year != year || birth.month != month || birth.day != day) {
      return null;
    }
    return birth;
  }

  /// Jenis kelamin & tanggal lahir dari NIK (tanggal > 40 = perempuan).
  static ({Gender gender, DateTime birthDate})? decode(
    String raw, {
    DateTime? now,
  }) {
    final v = normalize(raw);
    final today = now ?? DateTime.now();
    if (v.length != 16 || validate(v, now: today) != null) return null;
    final birth = _birth(v, today);
    if (birth == null) return null;
    final gender = int.parse(v.substring(6, 8)) > 40
        ? Gender.female
        : Gender.male;
    return (gender: gender, birthDate: birth);
  }

  static int ageOn(DateTime birth, DateTime on) {
    var age = on.year - birth.year;
    if (on.month < birth.month ||
        (on.month == birth.month && on.day < birth.day)) {
      age--;
    }
    return age;
  }

  /// Untuk tampilan & struk: 3201********0001.
  static String mask(String nik) {
    final v = normalize(nik);
    if (v.length < 8) return v;
    return '${v.substring(0, 4)}${'*' * (v.length - 8)}${v.substring(v.length - 4)}';
  }
}
