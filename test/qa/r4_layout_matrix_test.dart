// QA putaran 4 — matriks tata letak: semua layar × 5 ukuran iMin × 2 skala
// teks. Gagal bila ada overflow ("RenderFlex overflowed"), galat render, atau
// tombol utama lebih kecil dari 48 dp.
// ignore_for_file: invalid_use_of_visible_for_testing_member

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
import 'package:health_station_lite/screens/home_screen.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/screens/history_screen.dart';
import 'package:health_station_lite/screens/measurement_screen.dart';
import 'package:health_station_lite/screens/result_screen.dart';
import 'package:health_station_lite/screens/settings_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sizes = <(String, Size, double)>[
  ('swift2', Size(720, 1600), 2.0), // iMin Swift 2 (6,5")
  ('m2pro', Size(720, 1440), 2.0), // iMin M2 Pro (5,5")
  ('d1', Size(1024, 600), 1.0), // meja 7–10"
  ('falcon', Size(1366, 768), 1.0), // meja 15,6" lama
  ('d4', Size(1920, 1080), 1.5), // iMin D4 / Falcon 2
  // iMin Falcon2 I24T02 (diukur 19 Okt 2026): 1920×1200, 280 dpi, tanpa
  // bilah status & navigasi tersisa 1920×1158 → ±1097×662 dp.
  ('falcon2', Size(1920, 1158), 1.75),
];

const _nik = '3201015203580001';

Future<void> _seed(Directory dir) async {
  SharedPreferences.setMockInitialValues({
    'settings_location_name': 'Posyandu Lansia Melati',
    'settings_ss_org_id': '10000004',
    'settings_ss_location_id': 'ef011065-38c9-46f8-9c35-d1fe68966a3e',
    'settings_ss_practitioner_id': 'N10000001',
    'device_registry_v1':
        '[{"type":"tensimeter","remoteId":"A","name":"Yuwell BP-YE670D"},'
            '{"type":"pulseOximeter","remoteId":"B","name":"KS M6100P"},'
            '{"type":"thermometer","remoteId":"C","name":"Yuwell HT-YHW"},'
            '{"type":"weightScale","remoteId":"D","name":"IF_B8B"},'
            '{"type":"gripStrength","remoteId":"E","name":"weixin-nini"}]',
  });
  RecordStore.directoryProvider = () async => dir;
  final f = File('${dir.path}/health_records_v1.json');
  if (f.existsSync()) f.deleteSync();
  RecordStore.instance.debugReset();
  await AppSettings.instance.load();
  await DeviceRegistryStore.instance.load();
  await RecordStore.instance.load();
  final day = DateTime.now();
  for (var i = 0; i < 4; i++) {
    final at = DateTime(day.year, day.month, day.day, 8 + i, 10).subtract(Duration(days: 30 * i));
    await RecordStore.instance.add(HealthRecord(
      id: 'R$i',
      createdAt: at,
      startedAt: at.subtract(const Duration(seconds: 220)),
      profile: const PersonProfile(
          name: 'Siti Aminah Binti Abdurrahman Wahid',
          gender: Gender.female,
          age: 68,
          heightCm: 158,
          nik: _nik),
      measurements: AllMeasurements(
        tensimeter: TensimeterData(systolic: 128 + i * 4, diastolic: 82 + i, pulse: 74),
        pulseOximeter: const PulseOximeterData(spo2: 97, heartRate: 75),
        thermometer: const ThermometerData(temperature: 36.6),
        weightScale: WeightScaleData(weight: 58.4 + i * 0.3, bmi: 23.4, bodyFatPercent: 31.2),
        gripStrength: const GripStrengthData(gripLeft1: 19.5, gripRight1: 22.4),
        others: const OthersMeasurementData(height: 158),
      ),
    ));
  }
}

Future<void> _settle(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _noError(WidgetTester tester, String reason) {
  final e = tester.takeException();
  if (e != null) {
    // ignore: avoid_print
    print('[$reason] ${e is FlutterError ? e.toStringDeep() : e}');
  }
  expect(e, isNull, reason: reason);
}

void _checkTargets(WidgetTester tester, String where) {
  for (final key in ['save_button', 'start_button']) {
    final f = find.byKey(Key(key));
    if (f.evaluate().isEmpty) continue;
    expect(tester.getSize(f).height, greaterThanOrEqualTo(48), reason: '$key @ $where');
  }
}

void main() {
  late Directory dir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Motion.enabled = false;
    // Font asli (Lexend) supaya lebar teks sama dengan di perangkat.
    Future<ByteData> font(String path) async =>
        ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);
    final lexend = FontLoader('Lexend');
    for (final w in [400, 500, 600, 700]) {
      lexend.addFont(font('assets/fonts/Lexend-$w.ttf'));
    }
    await lexend.load();
    final root = Platform.environment['FLUTTER_ROOT'] ?? '/home/claude/toolchain/flutter';
    await (FontLoader('MaterialIcons')
          ..addFont(font('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')))
        .load();
    await initializeDateFormatting('id_ID');
    Intl.defaultLocale = 'id_ID';
    dir = await Directory.systemTemp.createTemp('hs_r4');
  });

  for (final (name, size, dpr) in sizes) {
    for (final scale in [1.0, 1.3]) {
      final tag = '$name x$scale';

      Future<void> pumpApp(WidgetTester tester, Widget home) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(
            size: size / dpr,
            devicePixelRatio: dpr,
            textScaler: TextScaler.linear(scale),
          ),
          child: MaterialApp(
            theme: buildAppTheme(),
            debugShowCheckedModeBanner: false,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: home,
          ),
        ));
        await _settle(tester);
      }

      testWidgets('beranda $tag', (tester) async {
        await tester.runAsync(() => _seed(dir));
        await pumpApp(tester, const HomeScreen());
        await tester.enterText(find.byKey(const Key('name_field')), 'Siti Aminah Binti Abdurrahman');
        await tester.tap(find.byKey(const Key('ktp_switch')));
        await tester.pump();
        await tester.enterText(find.byKey(const Key('nik_field')), _nik);
        await _settle(tester, 2);
        _noError(tester, tag);
        _checkTargets(tester, tag);
      });

      testWidgets('pengukuran (berbagai keadaan) $tag', (tester) async {
        await tester.runAsync(() => _seed(dir));
        MeasurementSession.debugResetCarryOver();
        final prevOnError = FlutterError.onError;
        FlutterError.onError = (d) {
          // ignore: avoid_print
          print('[DETAIL $tag] ${d.toString().split('\n').where((l) => l.contains('file:///') || l.contains('overflowed')).join(' | ')}');
          prevOnError?.call(d);
        };
        addTearDown(() => FlutterError.onError = prevOnError);

        await pumpApp(
          tester,
          const MeasurementScreen(
            profile: PersonProfile(
                name: 'Siti Aminah Binti Abdurrahman Wahid',
                gender: Gender.female,
                age: 68,
                heightCm: 158),
          ),
        );
        final s = debugLastMeasurementSession!;
        for (final t in DeviceType.values) {
          s.debugSetStatus(t, DeviceStatus.connected);
        }
        // Campuran: timbang goyah, oksigen menstabilkan, genggam live.
        s.debugInjectPacket(const [0x33, 0xCC, 0, 0, 0, 0, 0x80, 0, 0, 0, 0x16, 0xC6],
            BleDeviceModel.IF_B8B);
        s.debugInjectPacket(const [0, 0, 0, 75, 97], BleDeviceModel.KS_M6100P);
        s.debugInjectPacket(const [0, 0, 0, 77, 97], BleDeviceModel.KS_M6100P);
        s.debugInjectGrip(8);
        await _settle(tester, 2);
        _noError(tester, 'campuran $tag');
        _checkTargets(tester, tag);

        // Lembar pilihan.
        await tester.tap(find.byKey(const Key('tile_tap_pulseOximeter')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        _noError(tester, 'lembar pilihan $tag');
        await tester.tapAt(const Offset(10, 10));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Semua selesai → banner hitung mundur.
        s.debugInjectGrip(0.2);
        s.debugInjectPacket(const [0, 0x4C, 0x0E], BleDeviceModel.Yuwell_HT_YHW);
        for (var i = 0; i < 5; i++) {
          s.debugInjectPacket(const [0, 0, 0, 75, 97], BleDeviceModel.KS_M6100P);
        }
        s.debugInjectPacket(
            List<int>.filled(16, 0)
              ..[0] = 0x04
              ..[1] = 128
              ..[3] = 82
              ..[14] = 74,
            BleDeviceModel.Yuwell_BP_YE670D);
        s.updateWeightScale(const WeightScaleData(weight: 58.4));
        s.acceptNow(DeviceType.weightScale);
        s.acceptNow(DeviceType.gripStrength);
        await _settle(tester, 2);
        _noError(tester, 'selesai $tag');
        await tester.tap(find.text('Batalkan'));
        await tester.pump();
      });

      testWidgets('hasil + tren $tag', (tester) async {
        await tester.runAsync(() => _seed(dir));
        await pumpApp(tester, const ResultScreen(recordId: 'R0'));
        await _settle(tester, 10);
        _noError(tester, tag);
        expect(find.byKey(const Key('satusehat_status')), findsOneWidget);
      });

      testWidgets('riwayat & pengaturan $tag', (tester) async {
        await tester.runAsync(() => _seed(dir));
        await pumpApp(tester, const HistoryScreen());
        _noError(tester, 'riwayat $tag');
        await tester.tap(find.byKey(const Key('export_menu')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        _noError(tester, 'menu ekspor $tag');
        await pumpApp(tester, const SettingsScreen());
        _noError(tester, 'pengaturan $tag');
        expect(find.byKey(const Key('satusehat_card')), findsOneWidget);
      });
    }
  }
}
