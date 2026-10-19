// QA round 3 — ResultScreen writes back a stale HealthRecord snapshot.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/screens/result_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    Intl.defaultLocale = 'id_ID';
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('BUG: NIK dialog save reverts printCount written by PrintQueue meanwhile', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('qa_rs');
      RecordStore.directoryProvider = () async => dir;
      await RecordStore.instance.load();
      await RecordStore.instance.add(HealthRecord(
        id: 'R1', createdAt: DateTime(2026, 10, 18, 9),
        profile: const PersonProfile(name: 'Siti Aminah'),
        measurements: const AllMeasurements(
            tensimeter: TensimeterData(systolic: 120, diastolic: 80, pulse: 70)),
      ));
    });
    await tester.pumpWidget(const MaterialApp(home: ResultScreen(recordId: 'R1')));
    await tester.pump(const Duration(milliseconds: 100));

    // Operator opens "Isi / ubah NIK" right after saving (auto-print still running in the queue).
    await tester.tap(find.byType(PopupMenuButton<String>));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Isi / ubah NIK'), findsOneWidget);
    await tester.tap(find.text('Isi / ubah NIK'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byKey(const Key('nik_dialog_field')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('nik_dialog_field')), '3201015203580001');

    // Background PrintQueue finishes the receipt and bumps printCount (print_queue.dart:90-94).
    await tester.runAsync(() async {
      final latest = RecordStore.instance.byId('R1')!;
      await RecordStore.instance.update(
          latest.copyWith(printCount: latest.printCount + 1, lastPrintedAt: DateTime.now()));
    });
    expect(RecordStore.instance.byId('R1')!.printCount, 1);

    await tester.tap(find.byKey(const Key('nik_dialog_save')));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    final r = RecordStore.instance.byId('R1')!;
    final disk = jsonDecode(await tester.runAsync(
        () => File('${dir.path}/health_records_v1.json').readAsString()) as String) as List;
    // ignore: avoid_print
    print('after NIK save: nik=${r.profile.nik} printCount=${r.printCount} '
        'lastPrintedAt=${r.lastPrintedAt} disk.printCount=${disk.first['printCount']}');
    expect(r.profile.nik, '3201015203580001');
    expect(r.printCount, 1, reason: 'stale snapshot r (captured before dialog) overwrote printCount');
  });
}
