// QA persona 7 — isi & render struk (regresi P7-1…P7-7).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/printing/printer_service.dart';
import 'package:health_station_lite/printing/receipt_content.dart';
import 'package:health_station_lite/printing/receipt_renderer.dart';
import 'package:intl/date_symbol_data_local.dart';

const _nik = '3201015203580001';

HealthRecord rec(
  AllMeasurements m, {
  String name = 'Siti Aminah',
  String? nik = _nik,
  int printCount = 0,
}) => HealthRecord(
  id: 'HS-20261019-ABCD',
  createdAt: DateTime(2026, 10, 19, 9, 5),
  profile: PersonProfile(
    name: name,
    gender: Gender.female,
    age: 68,
    heightCm: 152,
    nik: nik,
  ),
  measurements: m,
  printCount: printCount,
);

Iterable<ReceiptLine> allLines(ReceiptContent c) => [
  ...c.identity,
  for (final s in c.sections) ...s.lines,
];
List<ReceiptLine> measured(ReceiptContent c) => [
  for (final s in c.sections)
    if (!s.title.startsWith('Analisa')) ...s.lines,
];
ReceiptSection analysis(ReceiptContent c) =>
    c.sections.singleWhere((s) => s.title.startsWith('Analisa'));

const _full = AllMeasurements(
  tensimeter: TensimeterData(systolic: 128, diastolic: 82, pulse: 72),
  pulseOximeter: PulseOximeterData(spo2: 97, heartRate: 75),
  thermometer: ThermometerData(temperature: 36.6),
  weightScale: WeightScaleData(
    weight: 58.4,
    bmi: 23.4,
    bodyScore: 78,
    bodyFatPercent: 31.2,
    musclePercent: 36.9,
    bmr: 1180,
    bodyType: 'Normal',
  ),
  gripStrength: GripStrengthData(
    gripLeft1: 18.2,
    gripLeft2: 19.0,
    gripRight1: 21.4,
  ),
  others: OthersMeasurementData(height: 152, calfCircumference: 31.5),
);

Future<(int, int)> pngSize(List<int> png) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
  final img = (await codec.getNextFrame()).image;
  return (img.width, img.height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    Future<ByteData> font(String path) async =>
        ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);
    final lexend = FontLoader('Lexend');
    for (final w in [400, 500, 600, 700]) {
      lexend.addFont(font('assets/fonts/Lexend-$w.ttf'));
    }
    await lexend.load();
  });

  group('Komposisi tubuh tidak dinilai di struk', () {
    // measurement_session.dart:1469-1481 menurunkan bodyType dari IMT+lemak:
    // IMT 30,0 & lemak 22 % → 'Berotot'; IMT 26 & lemak 30 → 'Sedikit gemuk'.
    test('"Tipe tubuh" tidak dicetak (penilaian non-Kemenkes)', () {
      final c = buildReceipt(
        rec(
          const AllMeasurements(
            weightScale: WeightScaleData(
              weight: 81,
              bmi: 30.0,
              bodyFatPercent: 22,
              bodyType: 'Berotot',
            ),
          ),
        ),
      );
      expect(
        allLines(c).where((l) => l.label == 'Tipe tubuh'),
        isEmpty,
        reason:
            'tercetak: ${allLines(c).where((l) => l.label == 'Tipe tubuh').map((l) => l.value)}',
      );
    });
    test(
      'struk tidak boleh sekaligus "Obesitas" (IMT) dan "Berotot" (tipe tubuh)',
      () {
        final c = buildReceipt(
          rec(
            const AllMeasurements(
              weightScale: WeightScaleData(
                weight: 81,
                bmi: 30.0,
                bodyFatPercent: 22,
                bodyType: 'Berotot',
              ),
            ),
          ),
        );
        final values = allLines(c).map((l) => l.value).join(' | ');
        expect(
          values.contains('Obesitas') && values.contains('Berotot'),
          isFalse,
          reason: values,
        );
      },
    );
    test(
      'IMT 25,0 Normal tidak boleh disertai "Sedikit gemuk" (IMT mentah 25,04)',
      () {
        final c = buildReceipt(
          rec(
            const AllMeasurements(
              weightScale: WeightScaleData(
                weight: 57.8,
                bmi: 25.04,
                bodyFatPercent: 33,
                bodyType: 'Sedikit gemuk',
              ),
            ),
          ),
        );
        final values = allLines(c).map((l) => l.value).join(' | ');
        expect(values.contains('Sedikit gemuk'), isFalse, reason: values);
      },
    );
    test('"Skor tubuh" (skor vendor timbangan) tidak dicetak', () {
      final c = buildReceipt(rec(_full));
      expect(allLines(c).where((l) => l.label == 'Skor tubuh'), isEmpty);
    });
    test('komposisi/genggam/betis tidak pernah diberi tanda *', () {
      final c = buildReceipt(rec(_full));
      for (final s in c.sections) {
        if (s.title.contains('Komposisi') ||
            s.title.contains('Genggam') ||
            s.title == 'Lainnya') {
          expect(s.lines.where((l) => l.flagged), isEmpty, reason: s.title);
        }
      }
    });
  });

  group('Denyut nadi', () {
    test('baris "Denyut nadi" hasil ukur tercetak hanya sekali', () {
      final c = buildReceipt(rec(_full));
      final n = measured(c).where((l) => l.label == 'Denyut nadi').length;
      expect(n, 1, reason: 'Denyut nadi tercetak $n× di bagian hasil');
    });
    test('nadi dicetak sekali: oksimeter diutamakan, nilai = analisa', () {
      final c = buildReceipt(rec(_full));
      final l = measured(c).singleWhere((l) => l.label == 'Denyut nadi');
      expect(l.value, '75 bpm');
      final a = analysis(c).lines.singleWhere((l) => l.label == 'Denyut nadi');
      expect(a.flagged, l.flagged);
    });
    test(
      'tanpa oksimeter: nadi tensimeter dicetak di bagian Tekanan Darah',
      () {
        final c = buildReceipt(
          rec(
            const AllMeasurements(
              tensimeter: TensimeterData(
                systolic: 120,
                diastolic: 78,
                pulse: 72,
              ),
            ),
          ),
        );
        final bp = c.sections.singleWhere((s) => s.title == 'Tekanan Darah');
        expect(bp.lines.map((l) => l.value), contains('72 bpm'));
      },
    );
    test('nadi tensimeter 0 dianggap tidak ada → nadi oksimeter dicetak', () {
      final c = buildReceipt(
        rec(
          const AllMeasurements(
            tensimeter: TensimeterData(systolic: 120, diastolic: 80, pulse: 0),
            pulseOximeter: PulseOximeterData(spo2: 97, heartRate: 130),
          ),
        ),
      );
      final l = measured(c).singleWhere((l) => l.label == 'Denyut nadi');
      expect(l.value, '130 bpm');
      expect(l.flagged, isTrue);
      expect(measured(c).where((l) => l.value == '0 bpm'), isEmpty);
    });
    test(
      'nadi oksimeter 120* tidak boleh dianalisa "Normal" (nadi tensi 72)',
      () {
        final c = buildReceipt(
          rec(
            const AllMeasurements(
              tensimeter: TensimeterData(
                systolic: 120,
                diastolic: 78,
                pulse: 72,
              ),
              pulseOximeter: PulseOximeterData(spo2: 97, heartRate: 120),
            ),
          ),
        );
        final flaggedHr = measured(
          c,
        ).any((l) => l.label == 'Denyut nadi' && l.flagged);
        final a = analysis(
          c,
        ).lines.singleWhere((l) => l.label == 'Denyut nadi');
        expect(
          flaggedHr && !a.flagged,
          isFalse,
          reason: 'baris ukur bertanda * tapi analisa: ${a.value}',
        );
      },
    );
  });

  group('Tanda * & angka konsisten dengan analisa', () {
    ReceiptLine line(ReceiptContent c, String label) =>
        measured(c).singleWhere((l) => l.label == label);
    test('TD 139/89 tanpa *, 140/90 dengan *', () {
      expect(
        line(
          buildReceipt(
            rec(
              const AllMeasurements(
                tensimeter: TensimeterData(systolic: 139, diastolic: 89),
              ),
            ),
          ),
          'Sistolik/Diastolik',
        ).flagged,
        isFalse,
      );
      expect(
        line(
          buildReceipt(
            rec(
              const AllMeasurements(
                tensimeter: TensimeterData(systolic: 140, diastolic: 90),
              ),
            ),
          ),
          'Sistolik/Diastolik',
        ).flagged,
        isTrue,
      );
      expect(
        line(
          buildReceipt(
            rec(
              const AllMeasurements(
                tensimeter: TensimeterData(systolic: 89, diastolic: 59),
              ),
            ),
          ),
          'Sistolik/Diastolik',
        ).flagged,
        isTrue,
      );
    });
    test('SpO2 94 *, 95 tanpa *', () {
      expect(
        line(
          buildReceipt(
            rec(
              const AllMeasurements(pulseOximeter: PulseOximeterData(spo2: 94)),
            ),
          ),
          'SpO2',
        ).flagged,
        isTrue,
      );
      expect(
        line(
          buildReceipt(
            rec(
              const AllMeasurements(pulseOximeter: PulseOximeterData(spo2: 95)),
            ),
          ),
          'SpO2',
        ).flagged,
        isFalse,
      );
    });
    test('suhu 36,4 *, 36,5 & 37,5 tanpa *, 37,6 *', () {
      for (final (t, f) in [
        (36.4, true),
        (36.5, false),
        (37.5, false),
        (37.6, true),
      ]) {
        expect(
          line(
            buildReceipt(
              rec(
                AllMeasurements(thermometer: ThermometerData(temperature: t)),
              ),
            ),
            'Suhu',
          ).flagged,
          f,
          reason: '$t',
        );
      }
    });
    test('suhu 37,53 tercetak "37,5 °C" tidak boleh bertanda * / Demam', () {
      final c = buildReceipt(
        rec(
          const AllMeasurements(
            thermometer: ThermometerData(temperature: 37.53),
          ),
        ),
      );
      final l = line(c, 'Suhu');
      expect(l.value, '37,5 °C');
      expect(l.flagged, isFalse, reason: 'tercetak "37,5 °C *"');
    });
    test(
      'IMT 27,1 (Obesitas) — baris IMT ikut bertanda * seperti baris lain',
      () {
        final c = buildReceipt(
          rec(
            const AllMeasurements(
              weightScale: WeightScaleData(weight: 70, bmi: 27.1),
            ),
          ),
        );
        expect(line(c, 'IMT (BMI)').flagged, isTrue);
      },
    );
    test('IMT dibulatkan seperti tercetak: 25,04 tanpa *, 18,4 *, 25,1 *', () {
      for (final (b, f) in [
        (25.04, false),
        (18.46, false),
        (18.4, true),
        (25.1, true),
        (22.0, false),
      ]) {
        final c = buildReceipt(
          rec(
            AllMeasurements(weightScale: WeightScaleData(weight: 60, bmi: b)),
          ),
        );
        expect(line(c, 'IMT (BMI)').flagged, f, reason: '$b');
      }
    });
    test('SpO2 94,6 tercetak "95 %" tanpa *', () {
      final l = line(
        buildReceipt(
          rec(
            const AllMeasurements(pulseOximeter: PulseOximeterData(spo2: 94.6)),
          ),
        ),
        'SpO2',
      );
      expect(l.value, '95 %');
      expect(l.flagged, isFalse);
    });
  });

  group('Identitas & UU PDP 27/2022', () {
    test('NIK tidak tercetak (utuh maupun tersamar)', () {
      final c = buildReceipt(rec(_full));
      final all = allLines(c).map((l) => '${l.label} ${l.value}').join('\n');
      expect(all.contains(_nik), isFalse);
      expect(all.contains('NIK'), isFalse);
      expect(all.contains('3201'), isFalse);
    });
    test('nama lokasi di-trim; kosong → null', () {
      expect(buildReceipt(rec(_full), locationName: '  ').locationName, isNull);
      expect(
        buildReceipt(rec(_full), locationName: ' Posyandu ').locationName,
        'Posyandu',
      );
    });
    test('nomor cetak = printCount + 1', () {
      expect(buildReceipt(rec(_full, printCount: 2)).printNumber, 3);
      expect(buildReceipt(rec(_full), printNumber: 7).printNumber, 7);
    });
    test('tanpa hasil → isEmpty, ringkasan "Belum ada angka"', () {
      final c = buildReceipt(rec(const AllMeasurements()));
      expect(c.isEmpty, isTrue);
      expect(summarize(const AllMeasurements()), 'Belum ada angka');
    });
  });

  group('Render 58 vs 80 mm', () {
    testWidgets('lebar PNG = 384 / 576 titik, 80 mm lebih pendek', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final c = buildReceipt(
          rec(_full),
          locationName: 'Posyandu Lansia Melati',
        );
        final a = await pngSize(
          await ReceiptRenderer.renderPng(c, paper: PaperWidth.mm58),
        );
        final b = await pngSize(
          await ReceiptRenderer.renderPng(c, paper: PaperWidth.mm80),
        );
        expect(a.$1, 384);
        expect(b.$1, 576);
        expect(b.$2, lessThan(a.$2));
      });
    });
    testWidgets(
      'nama sangat panjang / tanpa spasi tidak galat, tetap selebar kertas',
      (tester) async {
        await tester.runAsync(() async {
          for (final name in [
            'Siti Aminah Binti Abdurrahman Wahid Hasyim Al-Banjari Nurhayati Kusumawardhani',
            'A' * 120,
          ]) {
            for (final p in PaperWidth.values) {
              final c = buildReceipt(
                rec(_full, name: name),
                locationName:
                    'Posyandu Lansia Melati RW 05 Kelurahan Sukamaju Kecamatan Cibeunying Kidul',
              );
              final s = await pngSize(
                await ReceiptRenderer.renderPng(c, paper: p),
              );
              expect(s.$1, p.dots);
            }
          }
        });
      },
    );
    testWidgets('struk kosong tetap dirender', (tester) async {
      await tester.runAsync(() async {
        final c = buildReceipt(rec(const AllMeasurements()));
        final s = await pngSize(
          await ReceiptRenderer.renderPng(c, paper: PaperWidth.mm58),
        );
        expect(s.$1, 384);
        expect(s.$2, greaterThan(100));
      });
    });
  });

  group('PrinterService', () {
    test('bukan Android → gagal dengan pesan Indonesia', () async {
      final r = await PrinterService.instance.printReceipt(Uint8List(0));
      expect(r.ok, isFalse);
      expect(r.message, contains('iMin'));
    });
    test('paperFromIminType', () {
      expect(paperFromIminType(80), PaperWidth.mm80);
      expect(paperFromIminType('58'), PaperWidth.mm58);
      expect(paperFromIminType(null), isNull);
      expect(paperFromIminType('abc'), isNull);
    });
    test('describeStatus(null) tidak menampilkan "null" ke petugas', () {
      expect(PrinterService.describeStatus(null), isNot(contains('null')));
    });
  });
}
