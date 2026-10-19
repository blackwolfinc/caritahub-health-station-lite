// Screenshot layar & struk dengan font asli (Lexend + Material Icons).
// Jalankan: flutter test test/visual_test.dart --update-goldens
// Hasil: test/goldens/*.png

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/motion.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/ble/health_device_models.dart';
import 'package:health_station_lite/ble/measurement_session.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/data/device_registry_store.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/main.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/printing/receipt_content.dart';
import 'package:health_station_lite/printing/receipt_renderer.dart';
import 'package:health_station_lite/screens/measurement_screen.dart';
import 'package:health_station_lite/screens/result_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ByteData> _font(String path) async =>
    ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);

Future<void> _loadFonts() async {
  final lexend = FontLoader('Lexend');
  for (final w in [400, 500, 600, 700]) {
    lexend.addFont(_font('assets/fonts/Lexend-$w.ttf'));
  }
  await lexend.load();
  final root =
      Platform.environment['FLUTTER_ROOT'] ?? '/home/claude/toolchain/flutter';
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      _font(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    );
  await icons.load();
}

const _fullMeasurements = AllMeasurements(
  tensimeter: TensimeterData(systolic: 145, diastolic: 88, pulse: 76),
  pulseOximeter: PulseOximeterData(spo2: 97, heartRate: 75),
  thermometer: ThermometerData(temperature: 36.6),
  weightScale: WeightScaleData(
    weight: 58.4,
    bmi: 23.4,
    bodyScore: 78,
    bmr: 1180,
    bodyFatPercent: 31.2,
    bodyWaterPercent: 48.6,
    musclePercent: 36.9,
    boneMineralPercent: 4.1,
    proteinPercent: 15.8,
    visceralFatRate: 7,
    bodyType: 'Sedikit gemuk',
  ),
  gripStrength: GripStrengthData(
    gripLeft1: 18.2,
    gripLeft2: 19.5,
    gripLeft3: 18.9,
    gripRight1: 21.0,
    gripRight2: 22.4,
  ),
  others: OthersMeasurementData(height: 158, calfCircumference: 31.5),
);

HealthRecord _record(
  String id,
  String name,
  DateTime at,
  AllMeasurements m, {
  int printed = 0,
}) => HealthRecord(
  id: id,
  createdAt: at,
  profile: PersonProfile(name: name, gender: Gender.female, age: 68),
  measurements: m,
  printCount: printed,
  lastPrintedAt: printed > 0 ? at.add(const Duration(minutes: 1)) : null,
);

Future<void> _settle(WidgetTester tester, {int rounds = 25}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

List<int> _scaleMain(double kg, {required bool locked}) {
  final raw = (kg * 100).round();
  final v = List<int>.filled(12, 0);
  v[0] = 0x33;
  v[1] = 0xCC;
  v[6] = locked ? 0x81 : 0x80;
  v[10] = (raw >> 8) & 0xFF;
  v[11] = raw & 0xFF;
  return v;
}

void _setSize(WidgetTester tester, Size physical, double dpr) {
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = dpr;
}

const _desk = Size(1920, 1080); // iMin D4 / Falcon 2 (15,6")
const _hand = Size(720, 1600); // iMin Swift 2 (6,5")

void main() {
  setUpAll(() async {
    // Golden dibuat di Linux (CI/build). Di macOS/Windows anti-aliasing huruf
    // berbeda 1–5 %, jadi di sana selisih ≤ 6 % dianggap sama.
    if (!Platform.isLinux && goldenFileComparator is LocalFileComparator) {
      goldenFileComparator = _TolerantComparator(
        (goldenFileComparator as LocalFileComparator).basedir.resolve(
          'visual_test.dart',
        ),
        0.06,
      );
    }
    TestWidgetsFlutterBinding.ensureInitialized();
    Motion.enabled = false;
    await _loadFonts();
    await initializeDateFormatting('id_ID');
    Intl.defaultLocale = 'id_ID';
    SharedPreferences.setMockInitialValues({
      'settings_location_name': 'Posyandu Lansia Melati',
      'settings_paper_mm': 58,
      'device_registry_v1':
          '[{"type":"tensimeter","remoteId":"A4:C1:38:11:22:33","name":"Yuwell BP-YE670D"},'
          '{"type":"pulseOximeter","remoteId":"C8:FD:19:44:55:66","name":"KS M6100P"},'
          '{"type":"thermometer","remoteId":"D0:1A:22:33:44:55","name":"Yuwell HT-YHW"},'
          '{"type":"weightScale","remoteId":"ED:67:37:77:88:99","name":"IF_B8B"},'
          '{"type":"gripStrength","remoteId":"F1:F2:F3:F4:F5:F6","name":"weixin-nini"}]',
    });
    final dir = await Directory.systemTemp.createTemp('hs_visual');
    RecordStore.directoryProvider = () async => dir;
    await AppSettings.instance.load();
    await DeviceRegistryStore.instance.load();
    await RecordStore.instance.load();
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    await RecordStore.instance.add(
      _record(
        '261018-0812-K7P',
        'Sutrisno',
        day.add(const Duration(hours: 8, minutes: 12)),
        const AllMeasurements(
          tensimeter: TensimeterData(systolic: 132, diastolic: 84, pulse: 70),
          thermometer: ThermometerData(temperature: 36.4),
        ),
        printed: 1,
      ),
    );
    await RecordStore.instance.add(
      _record(
        '261018-0905-M2Q',
        'Wahyuni',
        day.add(const Duration(hours: 9, minutes: 5)),
        const AllMeasurements(
          pulseOximeter: PulseOximeterData(spo2: 98, heartRate: 81),
          weightScale: WeightScaleData(weight: 52.1, bmi: 21.7),
        ),
        printed: 1,
      ),
    );
    await RecordStore.instance.add(
      _record(
        '261018-0931-T8R',
        'Siti Aminah',
        day.add(const Duration(hours: 9, minutes: 31)),
        _fullMeasurements,
      ),
    );
  });

  Future<void> receipt(PaperWidth paper, String file) async {
    final r = RecordStore.instance.byId('261018-0931-T8R')!;
    final c = buildReceipt(r, locationName: 'Posyandu Lansia Melati');
    final png = await ReceiptRenderer.renderPng(c, paper: paper);
    await File('test/goldens/$file').writeAsBytes(png);
  }

  testWidgets('struk 58 mm & 80 mm', (tester) async {
    await tester.runAsync(() async {
      Directory('test/goldens').createSync(recursive: true);
      await receipt(PaperWidth.mm58, 'receipt_58mm.png');
      await receipt(PaperWidth.mm80, 'receipt_80mm.png');
    });
  });

  for (final (name, size, dpr) in [
    ('desk', _desk, 1.5),
    ('hand', _hand, 2.0),
  ]) {
    testWidgets('beranda $name', (tester) async {
      _setSize(tester, size, dpr);
      await tester.pumpWidget(const HealthStationLiteApp());
      await _settle(tester, rounds: 5);
      if (name == 'hand') {
        await tester.enterText(
          find.byKey(const Key('name_field')),
          'Siti Aminah',
        );
        await tester.pumpAndSettle();
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_$name.png'),
      );
    });

    Future<MeasurementSession> openMeasure(WidgetTester tester) async {
      _setSize(tester, size, dpr);
      MeasurementSession.debugResetCarryOver();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          home: const MeasurementScreen(
            profile: PersonProfile(
              name: 'Siti Aminah',
              gender: Gender.female,
              age: 68,
              heightCm: 158,
            ),
          ),
        ),
      );
      await _settle(tester, rounds: 5);
      return debugLastMeasurementSession!;
    }

    testWidgets('pengukuran $name (campuran)', (tester) async {
      final s = await openMeasure(tester);
      // Berdiri: timbangan terkunci + suhu + oksimeter stabil; tensi belum;
      // genggam sedang berjalan (2 remasan).
      s.debugInjectPacket(
        _scaleMain(58.4, locked: true),
        BleDeviceModel.IF_B8B,
      );
      s.debugInjectPacket(const [
        78,
        7,
        0x04,
        0xB0,
        0x03,
        0x03,
        0,
        0,
      ], BleDeviceModel.IF_B8B);
      s.debugInjectPacket(const [0, 0x4C, 0x0E], BleDeviceModel.Yuwell_HT_YHW);
      for (var i = 0; i < 5; i++) {
        s.debugInjectPacket(const [0, 0, 0, 75, 97], BleDeviceModel.KS_M6100P);
      }
      for (final kg in [18.2, 19.5]) {
        s.debugInjectGrip(4);
        s.debugInjectGrip(kg);
        s.debugInjectGrip(0.5);
      }
      s.debugInjectGrip(12.0);
      await _settle(tester, rounds: 3);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/measure_$name.png'),
      );
    });

    testWidgets('pengukuran $name (semua selesai)', (tester) async {
      final s = await openMeasure(tester);
      s.debugInjectPacket(
        _scaleMain(58.4, locked: true),
        BleDeviceModel.IF_B8B,
      );
      s.debugInjectPacket(const [
        78,
        7,
        0x04,
        0xB0,
        0x03,
        0x03,
        0,
        0,
      ], BleDeviceModel.IF_B8B);
      s.debugInjectPacket(const [0, 0x4C, 0x0E], BleDeviceModel.Yuwell_HT_YHW);
      for (var i = 0; i < 5; i++) {
        s.debugInjectPacket(const [0, 0, 0, 75, 97], BleDeviceModel.KS_M6100P);
      }
      final bp = List<int>.filled(16, 0)
        ..[0] = 0x04
        ..[1] = 128
        ..[3] = 82
        ..[14] = 74;
      s.debugInjectPacket(bp, BleDeviceModel.Yuwell_BP_YE670D);
      for (final kg in [18.2, 19.5, 18.9, 21.0, 22.4, 21.7]) {
        s.debugInjectGrip(4);
        s.debugInjectGrip(kg);
        s.debugInjectGrip(0.5);
      }
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('auto_finish_banner')), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/measure_done_$name.png'),
      );
      // Batalkan supaya test tidak benar-benar menyimpan.
      await tester.tap(find.text('Batalkan'));
      await tester.pump();
    });

    testWidgets('hasil $name', (tester) async {
      _setSize(tester, size, dpr);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          home: const ResultScreen(
            recordId: '261018-0931-T8R',
            justSaved: true,
          ),
        ),
      );
      await _settle(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/result_$name.png'),
      );
    });
  }
}

class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile, this.tolerance);
  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
