import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/motion.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/ble/health_device_models.dart';
import 'package:health_station_lite/data/device_registry_store.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/screens/measurement_screen.dart';
import 'package:health_station_lite/utils/health_ranges.dart';
import 'package:health_station_lite/utils/health_zones.dart';
import 'package:health_station_lite/widgets/avatar3d.dart';
import 'package:health_station_lite/widgets/charts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Motion.enabled = false);

  group('zona sejalan dengan HealthRanges (tanda * di struk)', () {
    // PNPK Hipertensi 2021 (Kemenkes): hipertensi ≥ 140/90, hipotensi < 90/60.
    test('tensi', () {
      final s = HealthZones.systolic;
      expect(s.zoneOf(89).label, 'Rendah');
      expect(s.zoneOf(90).label, 'Normal');
      expect(s.zoneOf(139).label, 'Normal');
      expect(s.zoneOf(140).label, 'Tinggi');
      expect(s.zoneOf(160).label, 'Tinggi · derajat 2');
      for (var v = 80; v <= 180; v++) {
        final normal = HealthZones.systolic.zoneOf(v.toDouble()).label == 'Normal' &&
            HealthZones.diastolic.zoneOf(80).label == 'Normal';
        expect(normal, HealthRanges.bloodPressureNormal(v, 80), reason: 'sistolik $v');
      }
    });

    test('SpO2 normal bila ≥ 95 (Kemenkes)', () {
      expect(HealthZones.spo2.zoneOf(94).label, 'Rendah');
      expect(HealthZones.spo2.zoneOf(95).label, 'Normal');
      expect(HealthZones.spo2.zoneOf(89).label, 'Rendah');
    });

    test('suhu: normal 36,5–37,5, demam > 37,5 (Kemenkes)', () {
      expect(HealthZones.temperature.zoneOf(36.5).label, 'Normal');
      expect(HealthZones.temperature.zoneOf(37.5).label, 'Normal');
      expect(HealthZones.temperature.zoneOf(37.6).label, 'Demam');
      expect(HealthZones.temperature.zoneOf(36.4).label, 'Di bawah normal');
    });

    test('BMI Kemenkes; genggam tanpa batas resmi', () {
      expect(HealthZones.bmi.zoneOf(18.4).label, 'Kurus');
      expect(HealthZones.bmi.zoneOf(25.0).label, 'Normal');
      expect(HealthZones.bmi.zoneOf(25.1).label, 'Gemuk');
      expect(HealthZones.bmi.zoneOf(27.1).label, 'Obesitas');
      for (final g in [Gender.female, Gender.male, null]) {
        expect(HealthZones.grip(g).zones.length, 1);
      }
    });
  });

  testWidgets('avatar 3D: semua pose & sorotan tergambar tanpa galat', (tester) async {
    for (final phase in AvatarPhase.values) {
      for (final g in [Gender.female, Gender.male, null]) {
        await tester.pumpWidget(MaterialApp(
          home: Center(
            child: SizedBox(
              width: 220,
              height: 260,
              child: ElderAvatar3D(
                phase: phase,
                gender: g,
                gripSide: GripSide.right,
                spots: {for (final t in DeviceType.values) t: AvatarSpot.values[t.index % 4]},
                devicesOn: DeviceType.values.toSet(),
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    }
    // Ganti pose di tengah jalan + geser untuk memutar.
    await tester.drag(find.byType(ElderAvatar3D), const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('grafik: data kosong / satu titik tetap aman', (tester) async {
    final live = ValueNotifier<double>(0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          const SizedBox(height: 40, child: Sparkline(values: [], color: Colors.red)),
          const SizedBox(height: 40, child: Sparkline(values: [70], color: Colors.red)),
          TrendChart(series: [
            TrendSeries('A', Colors.red, [(DateTime(2026, 10, 18), 120)]),
          ]),
          const HourlyBars(counts: {}),
          const HourlyBars(counts: {6: 2, 21: 5}, currentHour: 21),
          RangeGauge(spec: HealthZones.systolic, value: null),
          RangeGauge(spec: HealthZones.systolic, value: 250),
          RangeGauge(spec: HealthZones.bmi, value: 2, compact: true),
          LiveForceChart(source: live, cutoff: 18),
        ]),
      ),
    ));
    for (final v in [0.0, 5.0, 22.0, 3.0]) {
      live.value = v;
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('kotak alat bisa diketuk: lembar pilihan dengan tombol besar', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await DeviceRegistryStore.instance.load();
    await DeviceRegistryStore.instance.register(const RegisteredDevice(
        type: DeviceType.thermometer, remoteId: 'C', name: 'Yuwell HT-YHW'));
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const MeasurementScreen(
        profile: PersonProfile(name: 'Uji', gender: Gender.male, age: 70, heightCm: 165),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    final s = debugLastMeasurementSession!;
    // Belum tersambung → kotak di bawah, redup, langkah menunggu alat.
    expect(find.byKey(const Key('idle_thermometer')), findsOneWidget);
    expect(find.text('Menunggu alat'), findsWidgets);
    s.debugSetStatus(DeviceType.thermometer, DeviceStatus.connected);
    await tester.pump();
    expect(find.byKey(const Key('idle_thermometer')), findsNothing);
    expect(find.byKey(const Key('avatar3d')), findsOneWidget);
    // Hanya termometer (tanpa timbangan) → satu langkah: duduk.
    expect(find.text('Duduk tenang'), findsWidgets);
    expect(find.text('Langkah 1 dari 1'), findsOneWidget);

    // Tombol di kotak cukup besar (≥ 48 dp).
    final manual = tester.getSize(find.byKey(const Key('manual_thermometer')));
    expect(manual.height, greaterThanOrEqualTo(48));

    await tester.tap(find.byKey(const Key('tile_tap_thermometer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final skip = find.byKey(const Key('sheet_skip_thermometer'));
    expect(skip, findsOneWidget);
    expect(tester.getSize(skip).height, greaterThanOrEqualTo(56));
    await tester.tap(skip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(s.stepOf(DeviceType.thermometer), MeasureStep.skipped);

    // Bacaan suhu masuk setelah batal lewati → kotak selesai.
    await tester.tap(find.byKey(const Key('unskip_thermometer')));
    await tester.pump();
    s.debugInjectPacket(const [0, 0x4C, 0x0E], BleDeviceModel.Yuwell_HT_YHW);
    await tester.pump();
    expect(s.stepOf(DeviceType.thermometer), MeasureStep.done);
    expect(find.text('36,6'), findsOneWidget);
  });
}
