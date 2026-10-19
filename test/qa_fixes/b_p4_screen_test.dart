// QA persona 4 — layar pengukuran: tombol "Selesai", hitung mundur,
// "Simpan sekarang". Ukuran Falcon2 1920×1158 @1.75. Test gagal = bug.
// Disalin dari qa_tests/p4_screen_test.dart; P4-S02 disesuaikan (ketuk
// pertama kini langsung "Belum ada hasil", bukan banner konfirmasi), plus
// tampilan tombol Selesai & kontras banner (P10-3).
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/motion.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/ble/health_device_models.dart';
import 'package:health_station_lite/ble/measurement_session.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/data/device_registry_store.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/screens/measurement_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<int> ox(int spo2, int hr) => [0, 0, 0, hr, spo2]; // KS M6100P
List<int> temp(double c) {
  final raw = (c * 100).round();
  return [0, raw & 0xFF, (raw >> 8) & 0xFF];
}

List<int> scaleMain(double kg, {required bool locked}) {
  final raw = (kg * 100).round();
  final v = List<int>.filled(12, 0);
  v[0] = 0x33;
  v[1] = 0xCC;
  v[6] = locked ? 0x81 : 0x80;
  v[10] = (raw >> 8) & 0xFF;
  v[11] = raw & 0xFF;
  return v;
}

const _oxM = BleDeviceModel.KS_M6100P;
const _tM = BleDeviceModel.Yuwell_HT_YHW;
const _wM = BleDeviceModel.IF_B8B;
const _reg =
    '[{"type":"pulseOximeter","remoteId":"B","name":"KS M6100P"},'
    '{"type":"thermometer","remoteId":"C","name":"Yuwell HT-YHW"},'
    '{"type":"weightScale","remoteId":"D","name":"IF_B8B"}]';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    Motion.enabled = false;
    await initializeDateFormatting('id_ID');
  });

  Future<void> settle(WidgetTester tester, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<MeasurementSession> pump(
    WidgetTester tester, {
    bool autoFinish = true,
  }) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({
        'device_registry_v1': _reg,
        if (!autoFinish) 'settings_auto_finish': false,
      });
      dir = await Directory.systemTemp.createTemp('qa_p4');
      RecordStore.directoryProvider = () async => dir;
      RecordStore.instance.debugReset();
      DeviceRegistryStore.instance.debugReset();
      MeasurementSession.debugResetCarryOver();
      await AppSettings.instance.load();
      await DeviceRegistryStore.instance.load();
      await RecordStore.instance.load();
    });
    tester.view.physicalSize = const Size(1920, 1158);
    tester.view.devicePixelRatio = 1.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const MeasurementScreen(
          profile: PersonProfile(
            name: 'Siti',
            heightCm: 158,
            gender: Gender.female,
          ),
        ),
      ),
    );
    await settle(tester);
    return debugLastMeasurementSession!;
  }

  Color? saveBg(WidgetTester tester) => tester
      .widget<ButtonStyleButton>(find.byKey(const Key('save_button')))
      .style
      ?.backgroundColor
      ?.resolve({});

  double ratio(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
  }

  Future<void> sec(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  testWidgets('P4-S01 Selesai tanpa hasil apa pun → pesan, tidak tersimpan', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('save_button')));
    await settle(tester);
    expect(find.textContaining('Belum ada hasil'), findsOneWidget);
    expect(RecordStore.instance.records, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'P4-S02 0 alat selesai, hanya SpO2 sementara → "Selesai" 2× tidak boleh '
    'menyimpan rekaman kosong',
    (tester) async {
      final s = await pump(tester);
      s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.connected);
      s.debugInjectPacket(ox(97, 0), _oxM); // jari baru dipasang
      await tester.pump();
      expect(s.doneCount, 0);
      // Nilai sementara tidak dihitung → tombol tampak sekunder.
      expect(saveBg(tester), AppColors.lightGrey);
      await tester.tap(find.byKey(const Key('save_button')));
      await tester.pump();
      expect(find.byKey(const Key('partial_banner')), findsNothing);
      expect(find.textContaining('Belum ada hasil'), findsOneWidget);
      await tester.tap(find.byKey(const Key('save_button')));
      await settle(tester);
      final saved = RecordStore.instance.records;
      expect(
        saved.where((r) => !r.measurements.hasAnyData),
        isEmpty,
        reason:
            'tersimpan ${saved.length} rekaman tanpa hasil alat: '
            '${saved.map((r) => r.measurements.toJson()).toList()}',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P4-S03 sama, berat belum terkunci → tidak boleh menyimpan rekaman kosong',
    (tester) async {
      final s = await pump(tester);
      s.debugSetStatus(DeviceType.weightScale, DeviceStatus.connected);
      s.debugInjectPacket(scaleMain(61.2, locked: false), _wM);
      await tester.pump();
      await tester.tap(find.byKey(const Key('save_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('save_button')));
      await settle(tester);
      expect(
        RecordStore.instance.records.where((r) => !r.measurements.hasAnyData),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P4-S04 ada alat idle → hitung mundur 15, "Simpan sekarang" tampil & menyimpan sekali '
    '(ketuk ganda)',
    (tester) async {
      final s = await pump(tester);
      s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
      s.debugInjectPacket(temp(36.6), _tM);
      await tester.pump();
      expect(find.byKey(const Key('auto_finish_banner')), findsOneWidget);
      expect(find.textContaining('simpan dalam 15'), findsOneWidget);
      await sec(tester, 2);
      expect(find.textContaining('simpan dalam 13'), findsOneWidget);
      final btn = find.byKey(const Key('save_now_button'));
      expect(btn, findsOneWidget);
      expect(tester.getSize(btn).height, greaterThanOrEqualTo(48));
      await tester.tap(btn);
      await tester.pump();
      if (btn.evaluate().isNotEmpty) await tester.tap(btn, warnIfMissed: false);
      await settle(tester);
      expect(RecordStore.instance.records, hasLength(1));
      expect(find.byKey(const Key('after_save_dialog')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P4-S05 semua alat terdaftar dipakai & selesai → hitung mundur 3, simpan otomatis 1×',
    (tester) async {
      final s = await pump(tester);
      for (final t in [
        DeviceType.thermometer,
        DeviceType.pulseOximeter,
        DeviceType.weightScale,
      ]) {
        s.debugSetStatus(t, DeviceStatus.connected);
      }
      s.debugInjectPacket(temp(36.6), _tM);
      for (var i = 0; i < 5; i++) {
        s.debugInjectPacket(ox(97, 72), _oxM);
      }
      s.skip(DeviceType.weightScale);
      await tester.pump();
      expect(find.textContaining('simpan dalam 3'), findsOneWidget);
      expect(find.byKey(const Key('save_now_button')), findsNothing);
      await sec(tester, 3);
      await settle(tester);
      expect(RecordStore.instance.records, hasLength(1));
      await sec(tester, 5);
      await settle(tester);
      expect(RecordStore.instance.records, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P4-S06 Batalkan → tidak simpan; pembaruan lain tidak memulai lagi; '
    'ukur ulang + selesai lagi → mulai lagi',
    (tester) async {
      final s = await pump(tester);
      s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
      s.debugInjectPacket(temp(36.6), _tM);
      await tester.pump();
      await tester.tap(find.text('Batalkan'));
      await tester.pump();
      expect(find.byKey(const Key('auto_finish_banner')), findsNothing);
      s.debugSetStatus(
        DeviceType.weightScale,
        DeviceStatus.waiting,
      ); // pembaruan lain
      await sec(tester, 20);
      await settle(tester);
      expect(RecordStore.instance.records, isEmpty);
      s.remeasure(DeviceType.thermometer);
      s.debugInjectPacket(temp(36.7), _tM);
      await tester.pump();
      expect(find.byKey(const Key('auto_finish_banner')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P4-S07 alat idle tersambung di tengah hitung mundur → hitung mundur batal',
    (tester) async {
      final s = await pump(tester);
      s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
      s.debugInjectPacket(temp(36.6), _tM);
      await tester.pump();
      await sec(tester, 5);
      s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.connected);
      await tester.pump();
      expect(find.byKey(const Key('auto_finish_banner')), findsNothing);
      await sec(tester, 20);
      await settle(tester);
      expect(RecordStore.instance.records, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P4-S08 oksimeter putus-sambung (connecting→waiting) berulang: simpan otomatis '
    'tidak boleh terjadi tanpa oksimeter',
    (tester) async {
      final s = await pump(tester);
      s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
      s.debugInjectPacket(temp(36.6), _tM);
      await tester.pump();
      // Lansia memasang jari → oksimeter menyala, GATT 133, coba lagi tiap ~8 dtk.
      for (var i = 0; i < 3; i++) {
        await sec(tester, 2);
        s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.connecting);
        await tester.pump();
        await sec(tester, 1);
        s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.waiting);
        await tester.pump();
      }
      await sec(tester, 16);
      await settle(tester);
      expect(
        RecordStore.instance.records,
        isEmpty,
        reason:
            'tersimpan otomatis tanpa oksimeter padahal oksimeter sempat tersambung',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('P4-S09 lembar isi manual terbuka → hitung mundur berhenti', (
    tester,
  ) async {
    final s = await pump(tester);
    s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
    s.debugInjectPacket(temp(36.6), _tM);
    await tester.pump();
    expect(find.byKey(const Key('auto_finish_banner')), findsOneWidget);
    // Buka sheet di atas layar ukur.
    final ctx = tester.element(find.byKey(const Key('save_button')));
    showModalBottomSheet<void>(
      context: ctx,
      builder: (_) => const SizedBox(height: 200),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await sec(tester, 20);
    await settle(tester);
    expect(RecordStore.instance.records, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'P4-S10 simpan otomatis dimatikan di pengaturan → tidak ada hitung mundur',
    (tester) async {
      final s = await pump(tester, autoFinish: false);
      s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
      s.debugInjectPacket(temp(36.6), _tM);
      await tester.pump();
      expect(AppSettings.instance.autoFinish, isFalse);
      expect(find.byKey(const Key('auto_finish_banner')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P4-S11 "Selesai" saat 1 dari 2 alat wajib selesai → konfirmasi, lalu simpan '
    'tanpa nilai oksimeter yang belum stabil',
    (tester) async {
      final s = await pump(tester);
      s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
      s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.connected);
      s.debugInjectPacket(temp(36.6), _tM);
      s.debugInjectPacket(ox(97, 72), _oxM);
      await tester.pump();
      await tester.tap(find.byKey(const Key('save_button')));
      await tester.pump();
      expect(find.byKey(const Key('partial_banner')), findsOneWidget);
      expect(RecordStore.instance.records, isEmpty);
      // Konfirmasi kedaluwarsa setelah 4 dtk.
      await sec(tester, 5);
      expect(find.byKey(const Key('partial_banner')), findsNothing);
      await tester.tap(find.byKey(const Key('save_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('save_button')));
      await settle(tester);
      final r = RecordStore.instance.records.single;
      expect(r.measurements.thermometer.temperature, closeTo(36.6, 1e-9));
      expect(r.measurements.pulseOximeter.isEmpty, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'B-S12 tombol Selesai: sekunder tanpa hasil, primer setelah ada hasil selesai',
    (tester) async {
      final s = await pump(tester);
      expect(saveBg(tester), AppColors.lightGrey);
      s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
      s.debugInjectPacket(temp(36.6), _tM);
      await tester.pump();
      expect(saveBg(tester), AppColors.primary);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'B-S13 P10-3 banner hitung mundur & "Simpan sekarang" kontras ≥4,5:1',
    (tester) async {
      final s = await pump(tester);
      s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
      s.debugInjectPacket(temp(36.6), _tM);
      await tester.pump();
      final banner = find.byKey(const Key('auto_finish_banner'));
      final bg = tester.widget<Container>(banner).color!;
      final txt = tester.widget<Text>(
        find.descendant(
          of: banner,
          matching: find.textContaining('simpan dalam'),
        ),
      );
      expect(ratio(txt.style!.color!, bg), greaterThanOrEqualTo(4.5));
      final btn = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('save_now_button')),
      );
      final label = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('save_now_button')),
          matching: find.byType(Text),
        ),
      );
      expect(
        ratio(label.style!.color!, btn.style!.backgroundColor!.resolve({})!),
        greaterThanOrEqualTo(4.5),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('B-S14 P10-3 "Ya, simpan" & banner konfirmasi kontras ≥4,5:1', (
    tester,
  ) async {
    final s = await pump(tester);
    s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
    s.debugSetStatus(DeviceType.pulseOximeter, DeviceStatus.connected);
    s.debugInjectPacket(temp(36.6), _tM);
    s.debugInjectPacket(ox(97, 72), _oxM);
    await tester.pump();
    await tester.tap(find.byKey(const Key('save_button')));
    await tester.pump();
    expect(find.text('Ya, simpan'), findsOneWidget);
    final banner = find.byKey(const Key('partial_banner'));
    final bTxt = tester.widget<Text>(
      find.descendant(of: banner, matching: find.byType(Text)),
    );
    expect(
      ratio(bTxt.style!.color!, tester.widget<Container>(banner).color!),
      greaterThanOrEqualTo(4.5),
    );
    final label = tester.widget<Text>(find.text('Ya, simpan'));
    expect(
      ratio(label.style!.color!, saveBg(tester)!),
      greaterThanOrEqualTo(4.5),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
