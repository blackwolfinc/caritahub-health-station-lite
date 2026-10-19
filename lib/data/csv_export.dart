import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/health_record.dart';
import '../utils/nik.dart';

/// Ekspor semua hasil ke CSV (pemisah titik koma, desimal koma — langsung
/// terbaca benar di Excel berbahasa Indonesia).
class CsvExport {
  CsvExport._();

  static const _sep = ';';

  static String _cell(Object? v) {
    if (v == null) return '';
    var s = v is double
        ? v.toStringAsFixed(1).replaceAll('.', ',')
        : v.toString();
    // Cegah "CSV injection": teks isian yang diawali = + - @ dibaca Excel
    // sebagai rumus.
    if (v is String && s.isNotEmpty && '=+-@'.contains(s[0])) s = "'$s";
    if (s.contains(_sep) || s.contains('"') || s.contains('\n')) {
      s = '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String build(List<HealthRecord> records) {
    const header = [
      'No',
      'Tanggal',
      'Jam',
      'Nama',
      'NIK',
      'Jenis kelamin',
      'Umur',
      'Sistolik (mmHg)',
      'Diastolik (mmHg)',
      'Nadi tensimeter (bpm)',
      'SpO2 (%)',
      'Nadi oksimeter (bpm)',
      'Suhu (°C)',
      'Berat (kg)',
      'IMT',
      'Skor tubuh',
      'Lemak (%)',
      'Air (%)',
      'Otot (%)',
      'Mineral tulang (%)',
      'Protein (%)',
      'Lemak viseral',
      'BMR (kkal)',
      'Genggam kiri 1',
      'Genggam kiri 2',
      'Genggam kiri 3',
      'Genggam kiri terbaik',
      'Genggam kanan 1',
      'Genggam kanan 2',
      'Genggam kanan 3',
      'Genggam kanan terbaik',
      'Tinggi (cm)',
      'Lingkar betis (cm)',
      'Jumlah cetak',
      'Durasi (detik)',
    ];
    final b = StringBuffer()..writeln(header.join(_sep));
    final d = DateFormat('yyyy-MM-dd');
    final t = DateFormat('HH:mm');
    for (final r in records) {
      final m = r.measurements;
      final row = <Object?>[
        r.id, d.format(r.createdAt), t.format(r.createdAt), r.profile.name,
        // UU PDP 27/2022: NIK disamarkan (3201********0001) karena file
        // dibagikan lewat share sheet. Ekspor SATUSEHAT terpisah.
        r.profile.nik == null ? null : Nik.mask(r.profile.nik!),
        r.profile.gender?.label, r.profile.age,
        m.tensimeter.systolic, m.tensimeter.diastolic, m.tensimeter.pulse,
        m.pulseOximeter.spo2?.round(), m.pulseOximeter.heartRate,
        m.thermometer.temperature,
        m.weightScale.weight,
        m.weightScale.bmi,
        m.weightScale.bodyScore?.round(),
        m.weightScale.bodyFatPercent, m.weightScale.bodyWaterPercent,
        m.weightScale.musclePercent, m.weightScale.boneMineralPercent,
        m.weightScale.proteinPercent, m.weightScale.visceralFatRate?.round(),
        // Tipe tubuh timbangan tidak diekspor: penilaian non-Kemenkes.
        m.weightScale.bmr,
        m.gripStrength.gripLeft1,
        m.gripStrength.gripLeft2,
        m.gripStrength.gripLeft3,
        m.gripStrength.gripLeft,
        m.gripStrength.gripRight1,
        m.gripStrength.gripRight2,
        m.gripStrength.gripRight3,
        m.gripStrength.gripRight,
        m.others.height, m.others.calfCircumference, r.printCount,
        r.durationSeconds,
      ];
      b.writeln(row.map(_cell).join(_sep));
    }
    return b.toString();
  }

  /// Tulis ke file sementara dan kembalikan path-nya.
  static Future<File> writeFile(List<HealthRecord> records) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final file = File('${dir.path}/health_station_$stamp.csv');
    // BOM supaya Excel membaca UTF-8 (°, nama beraksen) dengan benar.
    await file.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(build(records))]);
    return file;
  }
}
