// QA round 3 — one malformed record hides the whole history and the next save overwrites the file.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';

void main() {
  test('one bad element -> all records dropped from memory; next add() rewrites file with 1 record', () async {
    final dir = await Directory.systemTemp.createTemp('qa_load');
    final good = List.generate(3, (i) => HealthRecord(
          id: 'G$i', createdAt: DateTime(2026, 10, 18, 9, i),
          profile: const PersonProfile(name: 'x'), measurements: const AllMeasurements()).toJson());
    File('${dir.path}/health_records_v1.json')
        .writeAsStringSync(jsonEncode([...good, {'id': 7, 'createdAt': '2026-10-18T10:00:00'}]));
    RecordStore.directoryProvider = () async => dir;
    await RecordStore.instance.load();
    // ignore: avoid_print
    print('loaded=${RecordStore.instance.records.length} (3 good records on disk); '
        'backups=${dir.listSync().where((f) => f.path.contains('corrupt')).length}');
    await RecordStore.instance.add(HealthRecord(
        id: 'NEW', createdAt: DateTime(2026, 10, 18, 11),
        profile: const PersonProfile(name: 'y'), measurements: const AllMeasurements()));
    final disk = jsonDecode(File('${dir.path}/health_records_v1.json').readAsStringSync()) as List;
    // ignore: avoid_print
    print('main file now has ${disk.length} record(s)');
    expect(RecordStore.instance.records.length, 4, reason: 'good records should survive one bad row');
  });
}
