// QA persona 6/8/10 — layar hasil: gauge, kartu analisa, pita tren normal,
// jumlah cetak saat layar ditutup, kontras & ukuran huruf status.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/motion.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/printing/printer_service.dart';
import 'package:health_station_lite/screens/result_screen.dart';
import 'package:health_station_lite/utils/health_analysis.dart';
import 'package:health_station_lite/utils/health_ranges.dart';
import 'package:health_station_lite/utils/health_zones.dart';
import 'package:health_station_lite/widgets/analysis_card.dart';
import 'package:health_station_lite/widgets/charts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

double ratio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Semua teks yang dirender di bawah [of] berukuran ≥ 14.
/// [skip]: teks dari widget bersama (SectionCard di common.dart).
void expectMinFont(
  WidgetTester tester,
  Finder of, {
  Set<String> skip = const {},
}) {
  for (final t in tester.widgetList<RichText>(
    find.descendant(of: of, matching: find.byType(RichText)),
  )) {
    void visit(InlineSpan span, double? inherited) {
      final size = span.style?.fontSize ?? inherited;
      if (span is TextSpan) {
        if ((span.text ?? '').trim().isNotEmpty && !skip.contains(span.text)) {
          expect(
            size,
            greaterThanOrEqualTo(14),
            reason: '"${span.text}" $size dp',
          );
        }
        for (final c in span.children ?? const <InlineSpan>[]) {
          visit(c, size);
        }
      }
    }

    visit(t.text, null);
  }
}

const _p = PersonProfile(name: 'Siti Aminah', gender: Gender.female, age: 68);

Future<void> _pump(WidgetTester tester, AllMeasurements m) async {
  tester.view.physicalSize = const Size(1920, 1158);
  tester.view.devicePixelRatio = 1.75;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('qa_p6');
    RecordStore.directoryProvider = () async => dir;
    RecordStore.instance.debugReset();
    await AppSettings.instance.load();
    await RecordStore.instance.load();
    await RecordStore.instance.add(
      HealthRecord(
        id: 'R0',
        createdAt: DateTime(2026, 9, 1, 9),
        profile: _p,
        measurements: const AllMeasurements(
          tensimeter: TensimeterData(systolic: 95, diastolic: 62),
        ),
      ),
    );
    await RecordStore.instance.add(
      HealthRecord(
        id: 'R1',
        createdAt: DateTime(2026, 10, 18, 9),
        profile: _p,
        measurements: m,
      ),
    );
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: const ResultScreen(recordId: 'R1'),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    Motion.enabled = false;
    Future<ByteData> font(String path) async =>
        ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);
    final lexend = FontLoader('Lexend');
    for (final w in [400, 500, 600, 700]) {
      lexend.addFont(font('assets/fonts/Lexend-$w.ttf'));
    }
    await lexend.load();
    final root = '${Directory.current.path}/.fvm/flutter_sdk';
    await (FontLoader('MaterialIcons')..addFont(
          font(
            '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
        ))
        .load();
    await initializeDateFormatting('id_ID');
    Intl.defaultLocale = 'id_ID';
    SharedPreferences.setMockInitialValues({'settings_paper_mm': 80});
  });

  testWidgets('pita "Rentang normal" tren TD = Kemenkes 90–139 / 60–89', (
    tester,
  ) async {
    await _pump(
      tester,
      const AllMeasurements(
        tensimeter: TensimeterData(systolic: 128, diastolic: 82, pulse: 70),
      ),
    );
    final chart = tester.widgetList<TrendChart>(find.byType(TrendChart)).first;
    expect(chart.normalBands, [
      (
        HealthRanges.minSystolic.toDouble(),
        HealthRanges.maxSystolic.toDouble(),
      ),
      (
        HealthRanges.minDiastolic.toDouble(),
        HealthRanges.maxDiastolic.toDouble(),
      ),
    ]);
  });

  testWidgets(
    'kartu analisa tampil + ringkasan visual tanpa penilaian genggam',
    (tester) async {
      await _pump(
        tester,
        const AllMeasurements(
          tensimeter: TensimeterData(systolic: 140, diastolic: 90, pulse: 70),
          gripStrength: GripStrengthData(gripLeft1: 9, gripRight1: 10),
          weightScale: WeightScaleData(weight: 60, bmi: 22, bodyFatPercent: 40),
        ),
      );
      expect(find.byKey(const Key('analysis_card')), findsOneWidget);
      expect(find.text('Tinggi · derajat 1'), findsWidgets);
      expect(find.textContaining('Lemah'), findsNothing);
      expect(find.textContaining('Sarkopenia'), findsNothing);
    },
  );

  testWidgets('suhu 37,53: layar tidak boleh "37,5 °C" sekaligus "Demam"', (
    tester,
  ) async {
    await _pump(
      tester,
      const AllMeasurements(thermometer: ThermometerData(temperature: 37.53)),
    );
    expect(find.textContaining('37,5'), findsWidgets);
    expect(
      find.text('Demam'),
      findsNothing,
      reason: 'angka tertulis 37,5 (normal Kemenkes) tapi diberi label Demam',
    );
  });

  testWidgets('AnalysisCard: tanpa temuan → tidak dirender', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalysisCard(
            record: HealthRecord(
              id: 'Z',
              createdAt: DateTime(2026),
              profile: _p,
              measurements: const AllMeasurements(
                gripStrength: GripStrengthData(gripLeft1: 5),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('analysis_card')), findsNothing);
  });

  testWidgets('ringkasan visual: nadi = nadi oksimeter (sama dengan analisa)', (
    tester,
  ) async {
    await _pump(
      tester,
      const AllMeasurements(
        tensimeter: TensimeterData(systolic: 120, diastolic: 78, pulse: 72),
        pulseOximeter: PulseOximeterData(spo2: 97, heartRate: 120),
      ),
    );
    final gauges = tester.widgetList<RangeGauge>(find.byType(RangeGauge));
    final hr = gauges.singleWhere((g) => g.spec == HealthZones.heartRate);
    expect(hr.value, 120);
    expect(hr.valueText, '120 bpm');
  });

  testWidgets('P8-1: keluar saat mencetak → jumlah cetak tetap tercatat', (
    tester,
  ) async {
    final done = Completer<PrintResult>();
    PrinterService.instance.debugPrintOverride = (_) => done.future;
    addTearDown(() => PrinterService.instance.debugPrintOverride = null);
    await _pump(
      tester,
      const AllMeasurements(
        tensimeter: TensimeterData(systolic: 128, diastolic: 82),
      ),
    );
    await tester.tap(find.byKey(const Key('print_button')));
    await tester.pump();
    expect(find.text('Mencetak…'), findsOneWidget);
    // Petugas meninggalkan layar hasil sebelum printer selesai.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(() async {
      done.complete(const PrintResult(true, 'Catatan tes kesehatan dicetak'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(RecordStore.instance.byId('R1')!.printCount, 1);
    expect(RecordStore.instance.byId('R1')!.lastPrintedAt, isNotNull);
  });

  group('P10-2: kontras teks status ≥ 4,5:1', () {
    for (final level in FindingLevel.values) {
      test('chip ${level.name}', () {
        final (bg, fg) = StatusInk.chip(level);
        expect(ratio(fg, bg), greaterThanOrEqualTo(4.5));
      });
    }
    test('status di latar putih & abu (layar hasil)', () {
      for (final c in [StatusInk.good, StatusInk.low, StatusInk.high]) {
        expect(ratio(c, AppColors.surface), greaterThanOrEqualTo(4.5));
        expect(ratio(c, AppColors.background), greaterThanOrEqualTo(4.5));
      }
      expect(
        ratio(StatusInk.high, AppColors.redSoft),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  testWidgets(
    'P10-2/6: kartu analisa & gauge — huruf ≥ 14, label zona kontras',
    (tester) async {
      await _pump(
        tester,
        const AllMeasurements(
          tensimeter: TensimeterData(systolic: 165, diastolic: 100, pulse: 70),
          pulseOximeter: PulseOximeterData(spo2: 93),
          thermometer: ThermometerData(temperature: 36.0),
          weightScale: WeightScaleData(weight: 60, bmi: 26),
        ),
      );
      expectMinFont(
        tester,
        find.byKey(const Key('analysis_card')),
        skip: {'Batas normal pedoman Kemenkes RI'},
      );
      expectMinFont(tester, find.byType(RangeGauge));
      expectMinFont(tester, find.byType(TrendChart));
      // Label zona (teks berwarna) di kartu putih.
      for (final label in [
        'Tinggi · derajat 2',
        'Rendah',
        'Di bawah normal',
        'Gemuk',
      ]) {
        final texts = tester.widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('summary_card')),
            matching: find.text(label),
          ),
        );
        expect(texts, isNotEmpty, reason: label);
        for (final t in texts) {
          expect(
            ratio(t.style!.color!, AppColors.surface),
            greaterThanOrEqualTo(4.5),
            reason: label,
          );
        }
      }
      // Chip status kartu analisa memakai warna StatusInk.
      final chip = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('analysis_card')),
          matching: find.text('Tinggi · derajat 2'),
        ),
      );
      expect(chip.style!.color, StatusInk.high);
      tester.takeException();
    },
  );
}
