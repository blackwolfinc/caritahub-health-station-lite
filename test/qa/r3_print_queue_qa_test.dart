// QA round 3 — PrintQueue state when the receipt printed but saving printCount failed.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/printing/print_queue.dart';
import 'package:health_station_lite/printing/printer_service.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> idle(PrintQueue q) async {
  for (var i = 0; i < 400 && q.pending > 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('id_ID'));

  test('BUG: printed OK + printCount save fails -> job "failed" -> retry prints a duplicate', () async {
    final dir = await Directory.systemTemp.createTemp('qa_pq');
    RecordStore.directoryProvider = () async => dir;
    await RecordStore.instance.load();
    await RecordStore.instance.add(HealthRecord(
      id: 'R1', createdAt: DateTime(2026, 10, 18, 9),
      profile: const PersonProfile(name: 'Siti'),
      measurements: const AllMeasurements(thermometer: ThermometerData(temperature: 36.5)),
    ));
    var physicalPrints = 0;
    final q = PrintQueue.instance
      ..printer = (Uint8List png) async {
        physicalPrints++;
        return const PrintResult(true, 'Struk dicetak');
      };
    // Storage becomes unwritable (full disk / removed dir) after the record was saved.
    await dir.delete(recursive: true);

    q.enqueue('R1', 'Siti');
    await idle(q);
    final job = q.jobs.single;
    print('after 1st run: status=${job.status} msg=${job.message} prints=$physicalPrints');
    q.retryFailed();
    await idle(q);
    print('after retry: status=${q.jobs.single.status} prints=$physicalPrints '
        'printCount=${RecordStore.instance.byId('R1')!.printCount}');
    expect(physicalPrints, 1, reason: 'receipt already came out; retry must not print again');
  });
}
