// QA round 2 — MeasurementScreen scratch tests. Each asserts the CORRECT
// behaviour; a failure proves the defect.
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
import 'package:health_station_lite/widgets/avatar3d.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _temp366 = [0, 0x4C, 0x0E]; // Yuwell HT-YHW 36.6 °C

MeasurementOutcome? outcome;
bool popped = false;

class _Launcher extends StatelessWidget {
  const _Launcher();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('go'),
            onPressed: () async {
              outcome = await Navigator.of(context).push<MeasurementOutcome>(
                MaterialPageRoute(
                  builder: (_) => const MeasurementScreen(
                    profile: PersonProfile(name: 'Uji', heightCm: 160),
                  ),
                ),
              );
              popped = true;
            },
            child: const Text('go'),
          ),
        ),
      );
}

Future<void> _register(List<DeviceType> types) async {
  const names = {
    DeviceType.tensimeter: ('A', 'Yuwell BP-YE670D'),
    DeviceType.pulseOximeter: ('B', 'KS M6100P'),
    DeviceType.thermometer: ('C', 'Yuwell HT-YHW'),
    DeviceType.weightScale: ('D', 'IF_B8B'),
    DeviceType.gripStrength: ('E', 'weixin-nini'),
  };
  for (final t in DeviceType.values) {
    await DeviceRegistryStore.instance.unregister(t);
  }
  for (final t in types) {
    final (id, name) = names[t]!;
    await DeviceRegistryStore.instance
        .register(RegisteredDevice(type: t, remoteId: id, name: name));
  }
}

/// Let real file IO of RecordStore complete inside testWidgets.
Future<void> _drainIo(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
  }
}

Future<MeasurementSession> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const _Launcher()));
  await tester.tap(find.byKey(const Key('go')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return debugLastMeasurementSession!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Motion.enabled = false);

  late Directory dir;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'settings_auto_print': false});
    MeasurementSession.debugResetCarryOver();
    await AppSettings.instance.load();
    await DeviceRegistryStore.instance.load();
    dir = Directory.systemTemp.createTempSync('hs_qa_r2');
    RecordStore.directoryProvider = () async => dir;
    RecordStore.instance.debugReset();
    await RecordStore.instance.load();
    outcome = null;
    popped = false;
  });

  testWidgets(
      'QA-AUTO-MODAL: auto-finish while the manual sheet is open must close '
      'the measurement screen (not just the sheet)', (tester) async {
    await tester.runAsync(() => _register([DeviceType.thermometer]));
    final s = await _open(tester);
    final before = RecordStore.instance.records.length;

    // Thermometer broken (not connected → idle tile) → nurse taps the tile,
    // picks "Isi manual" and types the value in the manual sheet.
    await tester.tap(find.byKey(const Key('idle_thermometer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('sheet_manual_thermometer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('measurement_field_Suhu tubuh')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const Key('field_dialog_input')), '36,5');
    await tester.tap(find.byKey(const Key('field_dialog_save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.stepOf(DeviceType.thermometer), MeasureStep.done);
    expect(s.allRequiredDone, isTrue);

    // Hitung mundur DIJEDA selama lembar isian masih terbuka (petugas sedang
    // mengetik) — tidak menyimpan & tidak menutup lembar di bawah tangannya.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await _drainIo(tester);
    expect(RecordStore.instance.records.length, before);
    expect(find.byType(MeasurementScreen), findsOneWidget);

    // Lembar ditutup → hitung mundur berlanjut → tersimpan & layar ukur tertutup.
    await tester.tapAt(const Offset(20, 80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await _drainIo(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(RecordStore.instance.records.length, before + 1,
        reason: 'record was saved');
    // Setelah simpan: pilih cetak atau lanjut. Lanjut → layar ukur tertutup.
    expect(find.byKey(const Key('after_save_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('after_save_next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MeasurementScreen), findsNothing);
    expect(outcome, isNotNull);
  });

  testWidgets(
      'QA-AUTO-DIALOG: auto-finish while the "Buang hasil?" dialog is open',
      (tester) async {
    await tester.runAsync(() => _register([DeviceType.thermometer]));
    final s = await _open(tester);
    s.debugInjectPacket(_temp366, BleDeviceModel.Yuwell_HT_YHW);
    await tester.pump();
    expect(find.byKey(const Key('auto_finish_banner')), findsOneWidget);
    // Nurse presses back during the countdown → confirm dialog opens.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Buang hasil pengukuran?'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await _drainIo(tester);
    final err = tester.takeException();
    expect(err, isNull, reason: 'exception: $err');
    // Dialog tetap terbuka, belum ada yang disimpan — petugas yang memutuskan.
    expect(find.text('Buang hasil pengukuran?'), findsOneWidget);
    expect(RecordStore.instance.records, isEmpty);

    // "Batal" → kembali ke layar ukur → hitung mundur berlanjut → tersimpan.
    await tester.tap(find.text('Batal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await _drainIo(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(RecordStore.instance.records.length, 1);
    await tester.tap(find.byKey(const Key('after_save_next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MeasurementScreen), findsNothing);
  });

  testWidgets(
      'QA-PARTIAL: "simpan tanpa Oksigen" must not store the unstable SpO2',
      (tester) async {
    await tester.runAsync(
        () => _register([DeviceType.pulseOximeter, DeviceType.thermometer]));
    final s = await _open(tester);
    s.debugInjectPacket(_temp366, BleDeviceModel.Yuwell_HT_YHW);
    s.debugInjectPacket([0, 0, 0, 88, 91], BleDeviceModel.KS_M6100P); // settling
    s.debugInjectPacket([0, 0, 0, 84, 93], BleDeviceModel.KS_M6100P);
    await tester.pump();
    expect(s.stepOf(DeviceType.pulseOximeter), MeasureStep.measuring);

    await tester.tap(find.byKey(const Key('save_button')));
    await tester.pump();
    expect(find.text('Ketuk lagi untuk simpan tanpa Oksigen'), findsOneWidget);
    await tester.tap(find.byKey(const Key('save_button')));
    await tester.pump();
    await _drainIo(tester);
    final rec = RecordStore.instance.records.first;
    expect(rec.measurements.pulseOximeter.spo2, isNull,
        reason: 'nurse confirmed "without Oksigen" but unstable SpO2 '
            '${rec.measurements.pulseOximeter.spo2} % was saved/printed');
  });

  testWidgets('QA-AVATAR-UNREG: avatar must not show unregistered devices',
      (tester) async {
    await tester.runAsync(() => _register([DeviceType.thermometer]));
    final s = await _open(tester);
    final avatar = tester.widget<ElderAvatar3D>(find.byKey(const Key('avatar3d')));
    expect(avatar.devicesOn.difference(s.requiredDevices), isEmpty,
        reason: 'phase=${avatar.phase} devicesOn=${avatar.devicesOn} '
            'spots=${avatar.spots}');
  });

  testWidgets(
      'QA-FINISHED-HINT: guide must not claim "Hasil disimpan dan struk '
      'dicetak" when nothing was saved', (tester) async {
    await tester.runAsync(() => _register([DeviceType.thermometer]));
    final s = await _open(tester);
    s.skip(DeviceType.thermometer); // all required skipped → no auto-save
    await tester.pump();
    expect(s.allRequiredDone, isFalse);
    expect(find.byKey(const Key('auto_finish_banner')), findsNothing);
    expect(find.text('Semua alat selesai. Hasil disimpan dan struk dicetak.'),
        findsNothing,
        reason: 'guide claims saved+printed; records='
            '${RecordStore.instance.records.length}, autoPrint=false');
  });
}
