import 'package:intl/intl.dart';

import '../models/health_record.dart';
import '../models/measurements.dart';
import '../utils/health_analysis.dart';
import '../utils/health_ranges.dart';

class ReceiptLine {
  final String label;
  final String value;

  /// Di luar rentang normal → diberi tanda * di struk.
  final bool flagged;
  const ReceiptLine(this.label, this.value, {this.flagged = false});
}

class ReceiptSection {
  final String title;
  final List<ReceiptLine> lines;
  const ReceiptSection(this.title, this.lines);
}

/// Isi struk yang sudah diformat — dipakai renderer gambar dan ekspor CSV.
class ReceiptContent {
  final String title;
  final String? locationName;
  final List<ReceiptLine> identity;
  final List<ReceiptSection> sections;
  final bool hasFlagged;
  final String recordId;
  final int printNumber;

  const ReceiptContent({
    required this.title,
    required this.locationName,
    required this.identity,
    required this.sections,
    required this.hasFlagged,
    required this.recordId,
    required this.printNumber,
  });

  bool get isEmpty => sections.isEmpty;
}

// Tanpa pemisah ribuan supaya angka bisa diedit ulang tanpa salah baca
// ("1.250" bisa terbaca 1,25). Desimal memakai koma (format Indonesia).
final NumberFormat _one = NumberFormat('0.0', 'id_ID');
final NumberFormat _int = NumberFormat('0', 'id_ID');

String fmt1(num? v) => v == null ? '—' : _one.format(v);
String fmt0(num? v) => v == null ? '—' : _int.format(v);
String formatDateTime(DateTime t) =>
    DateFormat('d MMM yyyy, HH.mm', 'id_ID').format(t);

ReceiptContent buildReceipt(
  HealthRecord record, {
  String locationName = '',
  int? printNumber,
}) {
  final p = record.profile;
  final m = record.measurements;

  final identity = <ReceiptLine>[
    ReceiptLine('Nama', p.name),
    if (p.gender != null) ReceiptLine('Jenis kelamin', p.gender!.label),
    if (p.age != null) ReceiptLine('Umur', '${p.age} tahun'),
    ReceiptLine('Tanggal', formatDateTime(record.createdAt)),
    ReceiptLine('No.', record.id),
  ];

  final sections = <ReceiptSection>[];
  void add(String title, List<ReceiptLine> lines) {
    if (lines.isNotEmpty) sections.add(ReceiptSection(title, lines));
  }

  // Nadi dicetak sekali, nilai yang sama dengan analisa: oksimeter bila
  // ada, selain itu tensimeter.
  final hr = pulseOf(m);
  final o = m.pulseOximeter;
  final hrFromOximeter = HealthRanges.validPulse(o.heartRate) != null;
  final hrLine = hr == null
      ? null
      : ReceiptLine(
          'Denyut nadi',
          '${fmt0(hr)} bpm',
          flagged: HealthRanges.heartRateNormal(hr) == false,
        );

  // Tekanan darah
  final t = m.tensimeter;
  final bpOk = HealthRanges.bloodPressureNormal(t.systolic, t.diastolic);
  add('Tekanan Darah', [
    if (t.systolic != null || t.diastolic != null)
      ReceiptLine(
        'Sistolik/Diastolik',
        '${fmt0(t.systolic)}/${fmt0(t.diastolic)} mmHg',
        flagged: bpOk == false,
      ),
    if (hrLine != null && !hrFromOximeter) hrLine,
  ]);

  // Oksimeter
  add('Saturasi Oksigen', [
    if (o.spo2 != null)
      ReceiptLine(
        'SpO2',
        '${fmt0(o.spo2)} %',
        flagged: HealthRanges.oxygenNormal(o.spo2) == false,
      ),
    if (hrLine != null && hrFromOximeter) hrLine,
  ]);

  // Suhu
  final th = m.thermometer;
  if (!th.isEmpty) {
    sections.add(
      ReceiptSection('Suhu Tubuh', [
        ReceiptLine(
          'Suhu',
          '${fmt1(th.temperature)} °C',
          flagged: HealthRanges.temperatureNormal(th.temperature) == false,
        ),
      ]),
    );
  }

  // Timbangan
  final w = m.weightScale;
  if (!w.isEmpty) {
    sections.add(
      ReceiptSection('Berat & Komposisi Tubuh', [
        if (w.weight != null)
          ReceiptLine('Berat badan', '${fmt1(w.weight)} kg'),
        if (w.bmi != null)
          ReceiptLine(
            'IMT (BMI)',
            fmt1(w.bmi),
            flagged: HealthRanges.bmiNormal(w.bmi) == false,
          ),
        // Skor tubuh & tipe tubuh dari timbangan tidak dicetak: penilaian
        // vendor, bukan pedoman Kemenkes RI (bisa bertentangan dengan IMT).
        if (w.bodyFatPercent != null)
          ReceiptLine('Lemak tubuh', '${fmt1(w.bodyFatPercent)} %'),
        if (w.bodyWaterPercent != null)
          ReceiptLine('Air tubuh', '${fmt1(w.bodyWaterPercent)} %'),
        if (w.musclePercent != null)
          ReceiptLine('Otot', '${fmt1(w.musclePercent)} %'),
        if (w.boneMineralPercent != null)
          ReceiptLine('Mineral tulang', '${fmt1(w.boneMineralPercent)} %'),
        if (w.proteinPercent != null)
          ReceiptLine('Protein', '${fmt1(w.proteinPercent)} %'),
        if (w.visceralFatRate != null)
          ReceiptLine('Lemak viseral', fmt0(w.visceralFatRate)),
        if (w.bmr != null) ReceiptLine('BMR', '${fmt0(w.bmr)} kkal'),
      ]),
    );
  }

  // Kekuatan genggam
  final g = m.gripStrength;
  if (!g.isEmpty) {
    String attempts(List<double?> v) =>
        v.whereType<double>().map(fmt1).join(' · ');
    sections.add(
      ReceiptSection('Kekuatan Genggam', [
        if (g.gripLeft != null)
          ReceiptLine('Kiri (terbaik)', '${fmt1(g.gripLeft)} kg'),
        if (g.gripLeft != null)
          ReceiptLine(
            '  percobaan',
            attempts([g.gripLeft1, g.gripLeft2, g.gripLeft3]),
          ),
        if (g.gripRight != null)
          ReceiptLine('Kanan (terbaik)', '${fmt1(g.gripRight)} kg'),
        if (g.gripRight != null)
          ReceiptLine(
            '  percobaan',
            attempts([g.gripRight1, g.gripRight2, g.gripRight3]),
          ),
      ]),
    );
  }

  // Lainnya
  final ot = m.others;
  if (!ot.isEmpty) {
    sections.add(
      ReceiptSection('Lainnya', [
        if (ot.height != null)
          ReceiptLine('Tinggi badan', '${fmt1(ot.height)} cm'),
        if (ot.calfCircumference != null)
          ReceiptLine('Lingkar betis', '${fmt1(ot.calfCircumference)} cm'),
      ]),
    );
  }

  // Analisa terhadap batas normal pedoman Kemenkes RI.
  final findings = analyze(record);
  if (findings.isNotEmpty) {
    sections.add(
      ReceiptSection('Analisa Hasil (Kemenkes RI)', [
        for (final f in findings)
          ReceiptLine(
            f.label,
            f.abnormal ? '${f.status} (N ${f.normal})' : f.status,
            flagged: f.abnormal,
          ),
        ReceiptLine('Kesimpulan', analysisSummary(findings)),
      ]),
    );
  }

  final hasFlagged = sections.any((s) => s.lines.any((l) => l.flagged));

  return ReceiptContent(
    title: 'Catatan Tes Kesehatan',
    locationName: locationName.trim().isEmpty ? null : locationName.trim(),
    identity: identity,
    sections: sections,
    hasFlagged: hasFlagged,
    recordId: record.id,
    printNumber: printNumber ?? record.printCount + 1,
  );
}

/// Ringkasan satu baris untuk daftar riwayat.
String summarize(AllMeasurements m) {
  final parts = <String>[
    if (m.tensimeter.systolic != null)
      'TD ${fmt0(m.tensimeter.systolic)}/${fmt0(m.tensimeter.diastolic)}',
    if (m.pulseOximeter.spo2 != null) 'SpO2 ${fmt0(m.pulseOximeter.spo2)}%',
    if (m.thermometer.temperature != null)
      '${fmt1(m.thermometer.temperature)}°C',
    if (m.weightScale.weight != null) '${fmt1(m.weightScale.weight)} kg',
    if (m.gripStrength.gripLeft != null || m.gripStrength.gripRight != null)
      'Genggam ${fmt1(m.gripStrength.gripLeft)}/${fmt1(m.gripStrength.gripRight)}',
  ];
  return parts.isEmpty ? 'Belum ada angka' : parts.join(' · ');
}
