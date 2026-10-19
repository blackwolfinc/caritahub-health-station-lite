// ignore_for_file: invalid_use_of_visible_for_testing_member
// Tampilan alur v1.3 untuk dokumentasi (bukan bagian dari `flutter test` biasa).
// Jalankan:
//   flutter test test_showcase/showcase_test.dart --update-goldens
// Hasil: test_showcase/screens/*.png

import 'dart:async';
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
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/printing/print_queue.dart';
import 'package:health_station_lite/printing/printer_service.dart';
import 'package:health_station_lite/printing/receipt_content.dart';
import 'package:health_station_lite/printing/receipt_renderer.dart';
import 'package:health_station_lite/screens/measurement_screen.dart';
import 'package:health_station_lite/screens/history_screen.dart';
import 'package:health_station_lite/screens/result_screen.dart';
import 'package:health_station_lite/screens/settings_screen.dart';
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

Future<void> _settle(WidgetTester tester, {int rounds = 25}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ── Paket mentah seperti dari alat ──────────────────────────────────────────
List<int> _scale(double kg, {required bool locked}) {
  final raw = (kg * 100).round();
  final v = List<int>.filled(12, 0);
  v[0] = 0x33;
  v[1] = 0xCC;
  v[6] = locked ? 0x81 : 0x80;
  v[10] = (raw >> 8) & 0xFF;
  v[11] = raw & 0xFF;
  return v;
}

const _scaleFinal = [78, 7, 0x04, 0xB0, 0x03, 0x03, 0, 0];
const _temp366 = [0, 0x4C, 0x0E];
const _ox9775 = [0, 0, 0, 75, 97];
List<int> _ox(int hr) => [0, 0, 0, hr, 97];
const _hrs = [74, 77, 75, 76, 75];
List<int> _bp(int sys, int dia, int pulse) => List<int>.filled(16, 0)
  ..[0] = 0x04
  ..[1] = sys
  ..[3] = dia
  ..[14] = pulse;

void _squeeze(MeasurementSession s, double kg) {
  s.debugInjectGrip(4);
  s.debugInjectGrip(kg);
  s.debugInjectGrip(0.5);
}

void _allConnected(MeasurementSession s) {
  for (final t in DeviceType.values) {
    s.debugSetStatus(t, DeviceStatus.connected);
  }
}

HealthRecord _history(
  String id,
  String name,
  Gender g,
  int age,
  DateTime at,
  int seconds,
  AllMeasurements m, {
  String? nik,
  double? heightCm,
}) => HealthRecord(
  id: id,
  createdAt: at,
  startedAt: at.subtract(Duration(seconds: seconds)),
  profile: PersonProfile(
    name: name,
    gender: g,
    age: age,
    nik: nik,
    heightCm: heightCm,
  ),
  measurements: m,
  printCount: 1,
  lastPrintedAt: at.add(const Duration(seconds: 20)),
);

const _siti = PersonProfile(
  name: 'Siti Aminah',
  gender: Gender.female,
  age: 68,
  heightCm: 158,
  nik: '3201015203580001',
);

const _sitiMeasurements = AllMeasurements(
  tensimeter: TensimeterData(systolic: 128, diastolic: 82, pulse: 74),
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
    gripRight3: 21.7,
  ),
  others: OthersMeasurementData(height: 158),
);

/// testWidgets dengan bayangan asli (flutter_test default menggambar
/// bayangan sebagai garis hitam pekat).
void _shot(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}

void _setSize(WidgetTester tester, Size physical, double dpr) {
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = dpr;
}

const _desk = Size(1920, 1080); // iMin D4 / Falcon 2 (15,6")
const _hand = Size(720, 1600); // iMin Swift 2 (6,5")

void main() {
  late Directory dir;

  // Tiap test mulai dari data yang sama: 2 lansia sudah diperiksa pagi ini.
  Future<void> resetData() async {
    SharedPreferences.setMockInitialValues({
      'settings_location_name': 'Posyandu Lansia Melati',
      'settings_paper_mm': 58,
      'settings_ss_org_id': '10000004',
      'settings_ss_location_id': 'ef011065-38c9-46f8-9c35-d1fe68966a3e',
      'settings_ss_location_name': 'Posyandu Lansia Melati',
      'settings_ss_practitioner_id': 'N10000001',
      'settings_ss_practitioner_name': 'Ns. Rina Wulandari',
      'device_registry_v1':
          '[{"type":"tensimeter","remoteId":"A4:C1:38:11:22:33","name":"Yuwell BP-YE670D"},'
          '{"type":"pulseOximeter","remoteId":"C8:FD:19:44:55:66","name":"KS M6100P"},'
          '{"type":"thermometer","remoteId":"D0:1A:22:33:44:55","name":"Yuwell HT-YHW"},'
          '{"type":"weightScale","remoteId":"ED:67:37:77:88:99","name":"IF_B8B"},'
          '{"type":"gripStrength","remoteId":"F1:F2:F3:F4:F5:F6","name":"weixin-nini"}]',
    });
    final f = File('${dir.path}/health_records_v1.json');
    if (f.existsSync()) f.deleteSync();
    // Antrean tulis RecordStore dari test sebelumnya (zona waktu tiruan)
    // bisa tidak pernah selesai — mulai bersih.
    RecordStore.instance.debugReset();
    await AppSettings.instance.load();
    await DeviceRegistryStore.instance.load();
    await RecordStore.instance.load();
    for (final r in RecordStore.instance.records.toList()) {
      await RecordStore.instance.delete(r.id);
    }
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    await RecordStore.instance.add(
      _history(
        '261018-0812-K7P',
        'Sutrisno',
        Gender.male,
        74,
        day.add(const Duration(hours: 8, minutes: 12)),
        216,
        const AllMeasurements(
          tensimeter: TensimeterData(systolic: 132, diastolic: 84, pulse: 70),
          pulseOximeter: PulseOximeterData(spo2: 96, heartRate: 72),
          thermometer: ThermometerData(temperature: 36.4),
          weightScale: WeightScaleData(weight: 63.2, bmi: 22.9),
          gripStrength: GripStrengthData(gripLeft1: 24.1, gripRight1: 26.3),
        ),
      ),
    );
    // Kunjungan Siti bulan-bulan sebelumnya (untuk grafik tren).
    for (final (i, sys, dia, kg) in [
      (4, 146, 92, 59.8),
      (3, 141, 90, 59.4),
      (2, 136, 87, 59.0),
      (1, 132, 85, 58.7),
    ]) {
      final at = day
          .subtract(Duration(days: 30 * i))
          .add(const Duration(hours: 9, minutes: 20));
      await RecordStore.instance.add(
        _history(
          'S$i',
          'Siti Aminah',
          Gender.female,
          68,
          at,
          230,
          AllMeasurements(
            tensimeter: TensimeterData(
              systolic: sys,
              diastolic: dia,
              pulse: 76,
            ),
            pulseOximeter: const PulseOximeterData(spo2: 97, heartRate: 76),
            thermometer: const ThermometerData(temperature: 36.5),
            weightScale: WeightScaleData(weight: kg, bmi: kg / (1.58 * 1.58)),
          ),
          nik: _siti.nik,
          heightCm: 158,
        ),
      );
    }
    await RecordStore.instance.add(
      _history(
        '261018-0905-M2Q',
        'Wahyuni',
        Gender.female,
        71,
        day.add(const Duration(hours: 9, minutes: 5)),
        221,
        const AllMeasurements(
          tensimeter: TensimeterData(systolic: 138, diastolic: 86, pulse: 80),
          pulseOximeter: PulseOximeterData(spo2: 98, heartRate: 81),
          thermometer: ThermometerData(temperature: 36.5),
          weightScale: WeightScaleData(weight: 52.1, bmi: 21.7),
          gripStrength: GripStrengthData(gripLeft1: 16.8, gripRight1: 18.0),
        ),
        nik: '3201014507550002',
      ),
    );
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Motion.enabled = false;
    await _loadFonts();
    await initializeDateFormatting('id_ID');
    Intl.defaultLocale = 'id_ID';
    dir = await Directory.systemTemp.createTemp('hs_showcase');
    RecordStore.directoryProvider = () async => dir;
    await resetData();
  });

  for (final (name, size, dpr) in [
    ('desk', _desk, 1.5),
    ('hand', _hand, 2.0),
  ]) {
    Future<MeasurementSession> openMeasure(
      WidgetTester tester, {
      PersonProfile profile = _siti,
      bool resetGates = true,
    }) async {
      _setSize(tester, size, dpr);
      if (resetGates) MeasurementSession.debugResetCarryOver();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          home: MeasurementScreen(profile: profile),
        ),
      );
      await _settle(tester, rounds: 5);
      final s = debugLastMeasurementSession!;
      _allConnected(s);
      return s;
    }

    Future<void> shot(WidgetTester tester, String file) async {
      // Biarkan indikator putar mencapai bentuk busur yang jelas.
      await tester.pump(const Duration(milliseconds: 650));
      await expectLater(
        find.byType(MaterialApp).first,
        matchesGoldenFile('screens/${name}_$file.png'),
      );
    }

    _shot('1 beranda: ketik nama lalu Enter ($name)', (tester) async {
      await tester.runAsync(resetData);
      _setSize(tester, size, dpr);
      await tester.pumpWidget(const HealthStationLiteApp());
      await _settle(tester, rounds: 5);
      await tester.enterText(
        find.byKey(const Key('name_field')),
        'Siti Aminah',
      );
      // NIK mengisi jenis kelamin & umur otomatis (12-03-1958, perempuan).
      await tester.tap(find.byKey(const Key('ktp_switch')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('nik_field')),
        '3201015203580001',
      );
      await tester.enterText(find.byKey(const Key('height_field')), '158');
      await _settle(tester, rounds: 3);
      await shot(tester, '1_beranda');
    });

    _shot('2 berdiri: timbang + suhu + oksigen sekaligus ($name)', (
      tester,
    ) async {
      debugElapsedOffset = const Duration(seconds: 41);
      final s = await openMeasure(tester);
      s.debugInjectPacket(_scale(58.1, locked: false), BleDeviceModel.IF_B8B);
      s.debugInjectPacket(_temp366, BleDeviceModel.Yuwell_HT_YHW);
      for (final hr in [73, 76, 75]) {
        s.debugInjectPacket(_ox(hr), BleDeviceModel.KS_M6100P);
      }
      s.debugInjectPacket(_scale(58.3, locked: false), BleDeviceModel.IF_B8B);
      await _settle(tester, rounds: 3);
      await shot(tester, '2_berdiri');
      // Ketuk kotak Oksigen → lembar pilihan dengan tombol besar.
      await tester.tap(find.byKey(const Key('tile_tap_pulseOximeter')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await shot(tester, '2b_pilihan');
    });

    _shot('3 genggam terakhir ($name)', (tester) async {
      debugElapsedOffset = const Duration(seconds: 172);
      final s = await openMeasure(tester);
      s.debugInjectPacket(_scale(58.4, locked: true), BleDeviceModel.IF_B8B);
      s.debugInjectPacket(_scaleFinal, BleDeviceModel.IF_B8B);
      s.debugInjectPacket(_temp366, BleDeviceModel.Yuwell_HT_YHW);
      for (final hr in _hrs) {
        s.debugInjectPacket(_ox(hr), BleDeviceModel.KS_M6100P);
      }
      s.debugInjectPacket(_bp(128, 82, 74), BleDeviceModel.Yuwell_BP_YE670D);
      for (final kg in [18.2, 19.5, 18.9]) {
        _squeeze(s, kg);
      }
      await _settle(tester, rounds: 2);
      // Kurva remasan kanan ke-1 (selesai) lalu ke-2 (sedang berlangsung).
      for (final v in [
        0.4,
        0.5,
        2.5,
        7.0,
        12.5,
        17.0,
        19.8,
        21.0,
        20.6,
        18.0,
        12.0,
        6.0,
        2.2,
        0.6,
        0.5,
        0.4,
        0.5,
        3.0,
        8.5,
        13.0,
        15.6,
      ]) {
        s.debugInjectGrip(v);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _settle(tester, rounds: 2);
      await shot(tester, '3_genggam');
    });

    _shot('4 semua selesai: simpan & cetak otomatis ($name)', (tester) async {
      debugElapsedOffset = const Duration(seconds: 215);
      final s = await openMeasure(tester);
      s.debugInjectPacket(_scale(58.4, locked: true), BleDeviceModel.IF_B8B);
      s.debugInjectPacket(_scaleFinal, BleDeviceModel.IF_B8B);
      s.debugInjectPacket(_temp366, BleDeviceModel.Yuwell_HT_YHW);
      for (final hr in _hrs) {
        s.debugInjectPacket(_ox(hr), BleDeviceModel.KS_M6100P);
      }
      s.debugInjectPacket(_bp(128, 82, 74), BleDeviceModel.Yuwell_BP_YE670D);
      for (final kg in [18.2, 19.5, 18.9, 21.0, 22.4, 21.7]) {
        _squeeze(s, kg);
      }
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('auto_finish_banner')), findsOneWidget);
      await shot(tester, '4_selesai');
      await tester.tap(find.text('Batalkan'));
      await tester.pump();
    });

    _shot('5 kembali ke beranda, struk dicetak di latar ($name)', (
      tester,
    ) async {
      await tester.runAsync(resetData);
      debugElapsedOffset = Duration.zero;
      MeasurementSession.debugResetCarryOver();
      // Printer "sibuk" supaya terlihat status cetak di latar.
      final never = Completer<PrintResult>();
      PrintQueue.instance.printer = (_) => never.future;
      _setSize(tester, size, dpr);
      await tester.pumpWidget(const HealthStationLiteApp());
      await _settle(tester, rounds: 5);
      await tester.enterText(
        find.byKey(const Key('name_field')),
        'Siti Aminah',
      );
      // NIK mengisi jenis kelamin & umur otomatis (12-03-1958, perempuan).
      await tester.tap(find.byKey(const Key('ktp_switch')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('nik_field')),
        '3201015203580001',
      );
      await tester.enterText(find.byKey(const Key('height_field')), '158');
      await tester.ensureVisible(find.byKey(const Key('start_button')));
      await tester.tap(find.byKey(const Key('start_button')));
      await _settle(tester, rounds: 8);
      expect(find.byKey(const Key('save_button')), findsOneWidget);
      final s = debugLastMeasurementSession!;
      _allConnected(s);
      s.debugInjectPacket(_scale(58.4, locked: true), BleDeviceModel.IF_B8B);
      s.debugInjectPacket(_scaleFinal, BleDeviceModel.IF_B8B);
      s.debugInjectPacket(_temp366, BleDeviceModel.Yuwell_HT_YHW);
      for (final hr in _hrs) {
        s.debugInjectPacket(_ox(hr), BleDeviceModel.KS_M6100P);
      }
      s.debugInjectPacket(_bp(128, 82, 74), BleDeviceModel.Yuwell_BP_YE670D);
      for (final kg in [18.2, 19.5, 18.9, 21.0, 22.4, 21.7]) {
        _squeeze(s, kg);
      }
      // Hitung mundur 3 detik → simpan → kembali ke beranda.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
      }
      await _settle(tester, rounds: 12);
      expect(find.byKey(const Key('name_field')), findsOneWidget);
      // Durasi asli test hanya beberapa detik; samakan dengan alur nyata (3:35).
      final saved = RecordStore.instance.records.firstWhere(
        (r) => r.profile.name == 'Siti Aminah',
      );
      await tester.runAsync(
        () => RecordStore.instance.update(
          HealthRecord(
            id: saved.id,
            createdAt: saved.createdAt,
            startedAt: saved.createdAt.subtract(const Duration(seconds: 215)),
            profile: saved.profile,
            measurements: saved.measurements,
            printCount: saved.printCount,
            lastPrintedAt: saved.lastPrintedAt,
          ),
        ),
      );
      await _settle(tester, rounds: 4);
      expect(find.textContaining('Siti Aminah tersimpan'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 450));
      await shot(tester, '5_tersimpan');
      // Selesaikan cetak supaya test berikutnya mulai tanpa antrean.
      never.complete(const PrintResult(true, 'OK'));
      await _settle(tester, rounds: 10);
      await tester.pump(const Duration(seconds: 6));
      expect(PrintQueue.instance.pending, 0);
    });

    _shot('6 lansia berikutnya: gerbang "lepas dulu" ($name)', (tester) async {
      debugElapsedOffset = const Duration(seconds: 6);
      MeasurementSession.debugResetCarryOver();
      // Jari & kaki Siti masih di alat saat lansia berikutnya dimulai.
      final prev = MeasurementSession(profile: _siti);
      prev.debugInjectPacket(_ox9775, BleDeviceModel.KS_M6100P);
      prev.debugInjectPacket(_scale(58.4, locked: true), BleDeviceModel.IF_B8B);
      prev.dispose();
      final s = await openMeasure(
        tester,
        profile: const PersonProfile(
          name: 'Bambang Hartono',
          gender: Gender.male,
          age: 74,
          heightCm: 165,
        ),
        resetGates: false,
      );
      s.debugInjectPacket(_ox9775, BleDeviceModel.KS_M6100P);
      await _settle(tester, rounds: 3);
      expect(s.oxArmed, isFalse);
      await shot(tester, '6_gerbang');
    });
  }

  for (final (name, size, dpr) in [
    ('desk', _desk, 1.5),
    ('hand', _hand, 2.0),
  ]) {
    _shot('7 hasil: ringkasan visual & tren ($name)', (tester) async {
      await tester.runAsync(() async {
        await resetData();
        final now = DateTime.now();
        final at = DateTime(now.year, now.month, now.day, 9, 31);
        await RecordStore.instance.add(
          HealthRecord(
            id: '261018-0931-T8R',
            createdAt: at,
            startedAt: at.subtract(const Duration(seconds: 215)),
            profile: _siti,
            measurements: _sitiMeasurements,
            printCount: 1,
            lastPrintedAt: at.add(const Duration(seconds: 20)),
          ),
        );
      });
      _setSize(tester, size, dpr);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          home: const ResultScreen(recordId: '261018-0931-T8R'),
        ),
      );
      await _settle(tester, rounds: 20);
      expect(find.byKey(const Key('summary_card')), findsOneWidget);
      expect(find.byKey(const Key('trend_card')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byType(MaterialApp).first,
        matchesGoldenFile('screens/${name}_7_hasil.png'),
      );
      // Gulir ke grafik tren.
      await tester.scrollUntilVisible(
        find.byKey(const Key('trend_card')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await _settle(tester, rounds: 4);
      await expectLater(
        find.byType(MaterialApp).first,
        matchesGoldenFile('screens/${name}_7b_tren.png'),
      );
    });
  }

  for (final (name, size, dpr) in [
    ('desk', _desk, 1.5),
    ('hand', _hand, 2.0),
  ]) {
    _shot('9 SATUSEHAT: pengaturan & ekspor ($name)', (tester) async {
      await tester.runAsync(resetData);
      _setSize(tester, size, dpr);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          home: const SettingsScreen(),
        ),
      );
      await _settle(tester, rounds: 6);
      await tester.scrollUntilVisible(
        find.byKey(const Key('satusehat_card')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
      await _settle(tester, rounds: 3);
      await expectLater(
        find.byType(MaterialApp).first,
        matchesGoldenFile('screens/${name}_9_satusehat_pengaturan.png'),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          home: const HistoryScreen(),
        ),
      );
      await _settle(tester, rounds: 6);
      await tester.tap(find.byKey(const Key('export_menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(
        find.byType(MaterialApp).first,
        matchesGoldenFile('screens/${name}_9b_satusehat_ekspor.png'),
      );
    });
  }

  for (final (name, size, dpr) in [
    ('desk', _desk, 1.5),
    ('hand', _hand, 2.0),
  ]) {
    _shot('10 kunci alat: alat baru ditawarkan & pengaturan ($name)', (
      tester,
    ) async {
      await tester.runAsync(resetData);
      MeasurementSession.offerGrace = Duration.zero;
      addTearDown(
        () => MeasurementSession.offerGrace = const Duration(seconds: 8),
      );
      _setSize(tester, size, dpr);
      MeasurementSession.debugResetCarryOver();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          home: const MeasurementScreen(profile: _siti),
        ),
      );
      await _settle(tester, rounds: 5);
      final s = debugLastMeasurementSession!;
      for (final t in DeviceType.values) {
        s.debugSetStatus(
          t,
          t == DeviceType.pulseOximeter
              ? DeviceStatus.waiting
              : DeviceStatus.connected,
        );
      }
      s.debugScanResult('C8:FD:19:A7:3B:21', 'KS M6100P');
      await _settle(tester, rounds: 3);
      await expectLater(
        find.byType(MaterialApp).first,
        matchesGoldenFile('screens/${name}_10_alat_baru.png'),
      );

      await tester.runAsync(() => DeviceRegistryStore.instance.setLocked(true));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          home: const SettingsScreen(),
        ),
      );
      await _settle(tester, rounds: 6);
      await tester.scrollUntilVisible(
        find.byKey(const Key('device_lock_switch')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 220));
      await _settle(tester, rounds: 2);
      await expectLater(
        find.byType(MaterialApp).first,
        matchesGoldenFile('screens/${name}_10b_kunci_alat.png'),
      );
      await tester.runAsync(
        () => DeviceRegistryStore.instance.setLocked(false),
      );
    });
  }

  _shot('8 struk 58 mm', (tester) async {
    await tester.runAsync(() async {
      final now = DateTime.now();
      final at = DateTime(now.year, now.month, now.day, 9, 31);
      final r = HealthRecord(
        id: '261018-0931-T8R',
        createdAt: at,
        startedAt: at.subtract(const Duration(seconds: 215)),
        profile: _siti,
        measurements: _sitiMeasurements,
      );
      final c = buildReceipt(r, locationName: 'Posyandu Lansia Melati');
      final png = await ReceiptRenderer.renderPng(c, paper: PaperWidth.mm58);
      Directory('test_showcase/screens').createSync(recursive: true);
      await File('test_showcase/screens/8_struk_58mm.png').writeAsBytes(png);
    });
  });
}
