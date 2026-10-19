// QA persona 10 (P10-10) — layar ukur memakai "IMT" seperti hasil & struk.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/motion.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/ble/measurement_session.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/data/device_registry_store.dart';
import 'package:health_station_lite/data/member_store.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/screens/measurement_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('Falcon2 1920×1158 @1,75', () {
    late Directory dir;
    setUpAll(() async {
      Motion.enabled = false;
      await initializeDateFormatting('id_ID');
      dir = await Directory.systemTemp.createTemp('qa_p10b');
    });

    Future<void> settle(WidgetTester tester, [int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pump(
      WidgetTester tester,
      Widget home, {
      bool keyboard = false,
    }) async {
      messenger.setMockMethodCallHandler(const MethodChannel('caritahub/nfc'), (
        call,
      ) async {
        return switch (call.method) {
          'status' => {'available': true, 'enabled': true, 'model': 'I24T02'},
          _ => true,
        };
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('caritahub/nfc/tags'),
        (_) async => null,
      );
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({
          'settings_onscreen_keyboard': keyboard,
          'device_registry_v1':
              '[{"type":"tensimeter","remoteId":"A","name":"Yuwell BP-YE670D"},'
              '{"type":"weightScale","remoteId":"D","name":"IF_B8B"}]',
        });
        final rec = Directory('${dir.path}/r')..createSync(recursive: true);
        final mem = Directory('${dir.path}/m')..createSync(recursive: true);
        for (final f in [...rec.listSync(), ...mem.listSync()]) {
          f.deleteSync(recursive: true);
        }
        RecordStore.directoryProvider = () async => rec;
        MemberStore.directoryProvider = () async => mem;
        RecordStore.instance.debugReset();
        MemberStore.instance.debugReset();
        await AppSettings.instance.load();
        await DeviceRegistryStore.instance.load();
        await RecordStore.instance.load();
        await MemberStore.instance.load();
        final at = DateTime.now();
        await RecordStore.instance.add(
          HealthRecord(
            id: 'R0',
            createdAt: at,
            profile: const PersonProfile(name: 'Siti', age: 68),
            measurements: const AllMeasurements(
              tensimeter: TensimeterData(
                systolic: 150,
                diastolic: 95,
                pulse: 70,
              ),
              weightScale: WeightScaleData(weight: 58, bmi: 24),
            ),
          ),
        );
      });
      MeasurementSession.debugResetCarryOver();
      tester.view.physicalSize = const Size(1920, 1158);
      tester.view.devicePixelRatio = 1.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: home));
      await settle(tester);
    }

    testWidgets('layar ukur memakai "IMT" (Kemenkes), bukan "BMI"', (
      tester,
    ) async {
      await pump(
        tester,
        const MeasurementScreen(profile: PersonProfile(name: 'Siti', age: 68)),
      );
      tester.takeException();
      expect(
        find.text('BMI'),
        findsNothing,
        reason: 'hasil & struk memakai "IMT", layar ukur "BMI"',
      );
      expect(find.text('IMT'), findsWidgets);
    });
  });
}
