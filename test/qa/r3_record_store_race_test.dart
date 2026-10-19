// QA round 3 — RecordStore concurrent commits (scratch).
// ignore_for_file: avoid_print
// _commit() is not serialized: two in-flight commits share the same "<file>.tmp",
// and a failed commit restores a stale snapshot that discards the other commit.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';

HealthRecord mk(String id, {int pc = 0}) => HealthRecord(
      id: id,
      createdAt: DateTime(2026, 10, 18, 9),
      profile: PersonProfile(name: 'N$id'),
      measurements: const AllMeasurements(thermometer: ThermometerData(temperature: 36.5)),
      printCount: pc,
    );

void main() {
  test('BUG: concurrent add + update (e.g. save next person while print queue bumps printCount)', () async {
    final dir = await Directory.systemTemp.createTemp('qa_race');
    RecordStore.directoryProvider = () async => dir;
    final store = RecordStore.instance;
    await store.load();
    // Pad the file so a write takes a few ms (a real station accumulates thousands of records).
    for (var i = 0; i < 300; i++) {
      await store.add(mk('PAD-$i'));
    }
    final file = File('${dir.path}/health_records_v1.json');
    var failures = 0, diverged = 0, lostFromMemory = 0;
    final errors = <String>{};
    final reportedSaved = <String>[];
    for (var i = 0; i < 40; i++) {
      final target = store.records.first;
      final f1 = store.update(target.copyWith(printCount: target.printCount + 1)); // print queue
      final f2 = store.add(mk('NEW-$i')); // operator saves the next person
      final res = await Future.wait<String?>([
        f1.then<String?>((_) => null, onError: (Object e) => '$e'),
        f2.then<String?>((_) => null, onError: (Object e) => '$e'),
      ]);
      for (final r in res) {
        if (r != null) {
          failures++;
          errors.add(r.split('\n').first);
        }
      }
      final onDisk = (jsonDecode(await file.readAsString()) as List).map((m) => m['id']).toSet();
      final inMem = store.records.map((r) => r.id).toSet();
      if (onDisk.length != inMem.length || !onDisk.containsAll(inMem)) diverged++;
      if (res[1] == null) reportedSaved.add('NEW-$i');
      if (res[1] == null && store.byId('NEW-$i') == null) lostFromMemory++;
    }
    print('iterations=40 failedCommits=$failures memory!=file=$diverged '
        'successfulAddMissingFromMemory=$lostFromMemory');
    print('errors: $errors');
    await store.add(mk('LAST')); // any later sequential save rewrites the file from memory
    final finalDisk = (jsonDecode(await file.readAsString()) as List).map((m) => m['id']).toSet();
    final lost = reportedSaved.where((id) => !finalDisk.contains(id)).toList();
    print('add() reported success for ${reportedSaved.length}; permanently missing from file: ${lost.length} $lost');
    expect(lost, isEmpty, reason: 'a save reported as successful must never disappear');
    expect(failures, 0, reason: 'independent commits must not fail each other');
    expect(diverged, 0, reason: 'memory and file must agree');
  });
}
