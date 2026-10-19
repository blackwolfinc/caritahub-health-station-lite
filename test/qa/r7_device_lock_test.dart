// QA putaran 7 — kunci alat & alat pengganti.
//
// Kunci MATI: alat terdaftar dipakai; bila alat terdaftar tidak tersambung,
// pemancar alat baru sejenis ditawarkan (pakai → didaftarkan, tolak → diingat).
// Kunci NYALA: hanya alat terdaftar; pemancar lain diabaikan, pendaftaran
// tidak bisa diubah.
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
import 'package:health_station_lite/screens/settings_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _registry =
    '[{"type":"tensimeter","remoteId":"A","name":"Yuwell BP-YE670D"},'
    '{"type":"pulseOximeter","remoteId":"B","name":"KS M6100P"},'
    '{"type":"weightScale","remoteId":"D","name":"IF_B8B"}]';

Future<DeviceRegistryStore> _freshRegistry({bool locked = false}) async {
  SharedPreferences.setMockInitialValues({
    'device_registry_v1': _registry,
    'device_lock_v1': locked,
  });
  final reg = DeviceRegistryStore.instance..debugReset();
  await reg.load();
  return reg;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('id_ID'));
  setUp(() => MeasurementSession.offerGrace = Duration.zero);
  tearDown(() => MeasurementSession.offerGrace = const Duration(seconds: 8));

  group('sesi', () {
    test('kunci mati + alat terdaftar tidak tersambung → alat baru ditawarkan; '
        'Pakai → menggantikan & tersimpan', () async {
      final reg = await _freshRegistry();
      final s = MeasurementSession(profile: const PersonProfile(name: 'A'));
      s.debugScanResult('NEW-OX', 'KS M6100P');
      final o = s.newDeviceOffer;
      expect(o, isNotNull);
      expect(o!.type, DeviceType.pulseOximeter);
      expect(o.replaces.remoteId, 'B');
      await s.acceptNewDevice();
      expect(s.newDeviceOffer, isNull);
      expect(reg.of(DeviceType.pulseOximeter)!.remoteId, 'NEW-OX');
      // Tersimpan: dibaca ulang dari penyimpanan.
      reg.debugReset();
      await reg.load();
      expect(reg.of(DeviceType.pulseOximeter)!.remoteId, 'NEW-OX');
      expect(reg.of(DeviceType.tensimeter)!.remoteId, 'A');
      s.dispose();
    });

    test('Tolak → diingat, tidak ditawarkan lagi (juga di sesi berikutnya)',
        () async {
      final reg = await _freshRegistry();
      final s = MeasurementSession(profile: const PersonProfile(name: 'A'));
      s.debugScanResult('NEW-OX', 'KS M6100P');
      await s.rejectNewDevice();
      expect(s.newDeviceOffer, isNull);
      expect(reg.isIgnored('NEW-OX'), isTrue);
      expect(reg.of(DeviceType.pulseOximeter)!.remoteId, 'B');
      s.dispose();

      final s2 = MeasurementSession(profile: const PersonProfile(name: 'B'));
      s2.debugScanResult('NEW-OX', 'KS M6100P');
      expect(s2.newDeviceOffer, isNull);
      // Alat baru yang lain tetap boleh ditawarkan.
      s2.debugScanResult('NEW-OX-2', 'KS M6100P');
      expect(s2.newDeviceOffer?.remoteId, 'NEW-OX-2');
      // "Tawarkan lagi" di Pengaturan menghapus daftar tolak.
      await reg.clearIgnored();
      expect(reg.isIgnored('NEW-OX'), isFalse);
      s2.dispose();
    });

    test('alat terdaftar tersambung → pemancar alat lain diabaikan', () async {
      await _freshRegistry();
      final s = MeasurementSession(profile: const PersonProfile(name: 'A'));
      s.debugMarkLinked('B', BleDeviceModel.KS_M6100P);
      s.debugScanResult('NEIGHBOUR', 'KS M6100P');
      expect(s.newDeviceOffer, isNull);
      s.dispose();
    });

    test('kunci NYALA → tidak ada tawaran; daftar/ganti/hapus ditolak', () async {
      final reg = await _freshRegistry(locked: true);
      expect(reg.locked, isTrue);
      final s = MeasurementSession(profile: const PersonProfile(name: 'A'));
      expect(s.deviceLocked, isTrue);
      s.debugScanResult('NEW-OX', 'KS M6100P');
      expect(s.newDeviceOffer, isNull);
      await expectLater(
        reg.register(const RegisteredDevice(
            type: DeviceType.pulseOximeter, remoteId: 'NEW-OX', name: 'KS M6100P')),
        throwsStateError,
      );
      await expectLater(
        reg.register(const RegisteredDevice(
            type: DeviceType.thermometer, remoteId: 'T', name: 'Yuwell HT-YHW')),
        throwsStateError,
      );
      await expectLater(reg.unregister(DeviceType.tensimeter), throwsStateError);
      expect(reg.of(DeviceType.pulseOximeter)!.remoteId, 'B');
      expect(reg.of(DeviceType.thermometer), isNull);
      // Mendaftar ulang alat yang sama (tanpa perubahan) tetap boleh.
      await reg.register(const RegisteredDevice(
          type: DeviceType.pulseOximeter, remoteId: 'B', name: 'KS M6100P'));
      s.dispose();
    });

    test('menyalakan kunci saat tawaran tampil langsung menutup tawaran',
        () async {
      final reg = await _freshRegistry();
      final s = MeasurementSession(profile: const PersonProfile(name: 'A'));
      s.debugScanResult('NEW-OX', 'KS M6100P');
      expect(s.newDeviceOffer, isNotNull);
      await reg.setLocked(true);
      expect(s.newDeviceOffer, isNull);
      await s.acceptNewDevice(); // tidak berbuat apa-apa saat terkunci
      expect(reg.of(DeviceType.pulseOximeter)!.remoteId, 'B');
      s.dispose();
    });

    test('jenis yang tidak terdaftar & nama tak dikenal tidak ditawarkan',
        () async {
      await _freshRegistry();
      final s = MeasurementSession(profile: const PersonProfile(name: 'A'));
      s.debugScanResult('T1', 'Yuwell HT-YHW'); // termometer tidak terdaftar
      expect(s.newDeviceOffer, isNull);
      s.debugScanResult('X1', 'JBL Flip 5');
      expect(s.newDeviceOffer, isNull);
      s.debugScanResult('X2', '');
      expect(s.newDeviceOffer, isNull);
      s.dispose();
    });

    test('masa tunggu: alat terdaftar diberi waktu tersambung dulu', () async {
      await _freshRegistry();
      MeasurementSession.offerGrace = const Duration(hours: 1);
      final s = MeasurementSession(profile: const PersonProfile(name: 'A'));
      s.debugScanResult('NEW-OX', 'KS M6100P');
      expect(s.newDeviceOffer, isNull);
      s.dispose();
    });

    test('satu tawaran sekaligus; alat terdaftar kembali → tawaran hilang',
        () async {
      await _freshRegistry();
      final s = MeasurementSession(profile: const PersonProfile(name: 'A'));
      s.debugScanResult('NEW-OX', 'KS M6100P');
      s.debugScanResult('NEW-BP', 'Yuwell BP-YE670D');
      expect(s.newDeviceOffer?.remoteId, 'NEW-OX');
      s.debugMarkLinked('B', BleDeviceModel.KS_M6100P);
      expect(s.newDeviceOffer, isNull);
      s.dispose();
    });
  });

  group('layar', () {
    late Directory dir;
    setUpAll(() async {
      Motion.enabled = false;
      dir = await Directory.systemTemp.createTemp('qa_r7');
      RecordStore.directoryProvider = () async => dir;
    });

    Future<void> pump(WidgetTester tester, Widget home,
        {Size size = const Size(720, 1600), double dpr = 2, double scale = 1}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    for (final (label, size, dpr, scale) in [
      ('genggam x1.3', const Size(720, 1600), 2.0, 1.3),
      ('meja', const Size(1920, 1080), 1.5, 1.0),
    ]) {
      testWidgets('banner alat baru: tampil, Pakai → terdaftar ($label)', (tester) async {
        await tester.runAsync(() async {
          await _freshRegistry();
          await AppSettings.instance.load();
          RecordStore.instance.debugReset();
          await RecordStore.instance.load();
        });
        await pump(tester, const MeasurementScreen(profile: PersonProfile(name: 'Siti')),
            size: size, dpr: dpr, scale: scale);
        final s = debugLastMeasurementSession!;
        expect(find.byKey(const Key('new_device_banner')), findsNothing);
        s.debugScanResult('NEW-OX', 'KS M6100P');
        await tester.pump();
        expect(find.byKey(const Key('new_device_banner')), findsOneWidget);
        expect(find.textContaining('KS M6100P'), findsWidgets);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byKey(const Key('new_device_accept'))).height,
            greaterThanOrEqualTo(48));
        await tester.tap(find.byKey(const Key('new_device_accept')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        expect(find.byKey(const Key('new_device_banner')), findsNothing);
        expect(DeviceRegistryStore.instance.of(DeviceType.pulseOximeter)!.remoteId, 'NEW-OX');
      });
    }

    testWidgets('banner: Tolak → hilang & diingat; gembok tampil saat terkunci',
        (tester) async {
      await tester.runAsync(() async {
        await _freshRegistry();
        await AppSettings.instance.load();
      });
      await pump(tester, const MeasurementScreen(profile: PersonProfile(name: 'Siti')));
      final s = debugLastMeasurementSession!;
      expect(find.byKey(const Key('lock_indicator')), findsNothing);
      s.debugScanResult('NEW-OX', 'KS M6100P');
      await tester.pump();
      await tester.tap(find.byKey(const Key('new_device_reject')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.byKey(const Key('new_device_banner')), findsNothing);
      expect(DeviceRegistryStore.instance.isIgnored('NEW-OX'), isTrue);

      await tester.runAsync(() => DeviceRegistryStore.instance.setLocked(true));
      await tester.pump();
      expect(find.byKey(const Key('lock_indicator')), findsOneWidget);
    });

    testWidgets('Pengaturan: kunci dinyalakan langsung, dimatikan dengan konfirmasi',
        (tester) async {
      await tester.runAsync(() async {
        await _freshRegistry();
        await AppSettings.instance.load();
      });
      await pump(tester, const SettingsScreen());
      final sw = find.byKey(const Key('device_lock_switch'));
      await tester.ensureVisible(sw);
      await tester.tap(sw);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(DeviceRegistryStore.instance.locked, isTrue);
      final prefs = await tester.runAsync(SharedPreferences.getInstance);
      expect(prefs!.getBool('device_lock_v1'), isTrue);

      await tester.tap(sw);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Matikan kunci alat?'), findsOneWidget);
      await tester.tap(find.text('Matikan kunci'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(DeviceRegistryStore.instance.locked, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
