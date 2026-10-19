// QA putaran 6 — 40 lansia berturut-turut di satu stasiun, seperti hari
// posyandu yang ramai: sesi ukur (paket BLE mentah, gerbang lepas-alat,
// timer timbangan) → simpan → cetak → muat ulang dari disk → ekspor CSV &
// SATUSEHAT. Setiap orang punya nilai unik, jadi nilai yang "bocor" dari
// orang sebelumnya langsung ketahuan.
// ignore_for_file: invalid_use_of_visible_for_testing_member, depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/ble/health_device_models.dart';
import 'package:health_station_lite/ble/measurement_session.dart';
import 'package:health_station_lite/data/csv_export.dart';
import 'package:health_station_lite/data/device_registry_store.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/printing/print_queue.dart';
import 'package:health_station_lite/printing/printer_service.dart';
import 'package:health_station_lite/satusehat/satusehat_export.dart';
import 'package:health_station_lite/utils/nik.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const people = 40;

List<int> ox(int spo2, int hr) => [0, 0, 0, hr, spo2]; // KS M6100P
List<int> bp(int sys, int dia, int pulse) {
  final v = List<int>.filled(16, 0);
  v[0] = 0x04;
  v[1] = sys & 0xFF;
  v[2] = (sys >> 8) & 0xFF;
  v[3] = dia & 0xFF;
  v[4] = (dia >> 8) & 0xFF;
  v[14] = pulse;
  return v;
}

List<int> temp(double c) {
  final raw = (c * 100).round();
  return [0, raw & 0xFF, (raw >> 8) & 0xFF]; // Yuwell HT-YHW
}

List<int> scale(double kg, {required bool locked}) {
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
const _bpM = BleDeviceModel.Yuwell_BP_YE670D;
const _tM = BleDeviceModel.Yuwell_HT_YHW;
const _wM = BleDeviceModel.IF_B8B;

/// Satu lansia dengan nilai yang unik per orang.
class Person {
  final int i;
  Person(this.i);

  bool get female => i.isOdd;
  bool get hasNik => i % 10 != 9; // 4 orang tanpa NIK
  bool get hasHeight => i % 7 != 3; // 6 orang tanpa tinggi → tanpa BMI
  bool get skipThermo => i % 8 == 5; // termometer dilewati
  bool get partialGrip => i % 6 == 2; // hanya 2 remasan lalu simpan

  String get name => 'Lansia ${(i + 1).toString().padLeft(2, '0')}';
  int get sys => 105 + i * 2; // 105..183
  int get dia => 65 + i % 25;
  int get pulse => 58 + i;
  int get spo2 => 92 + i % 8;
  int get hr => 60 + i;
  double get temperature => 35.8 + (i % 15) / 10;
  double get weight => 42.0 + i * 0.85;
  double get height => 145.0 + i % 25;
  List<double> get grips => [for (var k = 0; k < 6; k++) 12.0 + i * 0.3 + k];

  String? get nik {
    if (!hasNik) return null;
    final day = 1 + i % 28 + (female ? 40 : 0);
    final month = 1 + i % 12;
    final yy = 40 + i % 25; // 1940–1964
    String two(int v) => v.toString().padLeft(2, '0');
    return '320101${two(day)}${two(month)}${two(yy)}${(i + 1).toString().padLeft(4, '0')}';
  }

  PersonProfile get profile => PersonProfile(
    name: name,
    gender: female ? Gender.female : Gender.male,
    age: 62 + i % 30,
    heightCm: hasHeight ? height : null,
    nik: nik,
  );
}

/// Jalankan satu sesi ukur dengan waktu tiruan (timer timbangan 6 detik).
AllMeasurements runSession(Person p, Person? prev) {
  late AllMeasurements out;
  fakeAsync((fa) {
    final s = MeasurementSession(profile: p.profile);
    if (prev != null) {
      // Lansia sebelumnya masih menjepit oksimeter & berdiri di timbangan.
      s.debugInjectPacket(ox(prev.spo2, prev.hr), _oxM);
      s.debugInjectPacket(scale(prev.weight, locked: true), _wM);
      expect(
        s.measurements.pulseOximeter.spo2,
        isNull,
        reason: '${p.name}: SpO2 ${prev.name} bocor',
      );
      expect(
        s.measurements.weightScale.weight,
        isNull,
        reason: '${p.name}: berat ${prev.name} bocor',
      );
      // Jari dilepas, turun dari timbangan → gerbang terbuka.
      s.debugInjectPacket(ox(0, 0), _oxM);
      s.debugInjectPacket(scale(0, locked: false), _wM);
    }
    expect(s.oxArmed, isTrue);
    expect(s.scaleArmed, isTrue);

    // Semua alat jalan bersamaan (urutan paket diselang-seling).
    s.debugInjectPacket(scale(p.weight - 0.6, locked: false), _wM);
    s.debugInjectPacket(ox(p.spo2, p.hr), _oxM);
    s.debugInjectGrip(5);
    s.debugInjectGrip(p.grips[0]);
    s.debugInjectGrip(0.5);
    s.debugInjectPacket(scale(p.weight, locked: true), _wM);
    for (var k = 0; k < 4; k++) {
      s.debugInjectPacket(ox(p.spo2, p.hr), _oxM);
    }
    if (p.skipThermo) {
      s.skip(DeviceType.thermometer);
    } else {
      s.debugInjectPacket(temp(p.temperature), _tM);
    }
    final squeezes = p.partialGrip ? 2 : 6;
    for (var k = 1; k < squeezes; k++) {
      s.debugInjectGrip(5);
      s.debugInjectGrip(p.grips[k]);
      s.debugInjectGrip(0.5);
    }
    s.debugInjectPacket(bp(p.sys, p.dia, p.pulse), _bpM);
    fa.elapse(const Duration(seconds: 7)); // kunci timbangan
    fa.flushMicrotasks();

    expect(s.stepOf(DeviceType.weightScale), MeasureStep.done, reason: p.name);
    expect(
      s.stepOf(DeviceType.pulseOximeter),
      MeasureStep.done,
      reason: p.name,
    );
    expect(s.stepOf(DeviceType.tensimeter), MeasureStep.done, reason: p.name);
    expect(s.allRequiredDone, !p.partialGrip, reason: p.name);
    out = s.measurementsForSave();
    s.dispose();
  });
  return out;
}

void expectRecordMatches(HealthRecord r, Person p) {
  final m = r.measurements;
  final why = '${p.name} (${r.id})';
  expect(r.profile.name, p.name, reason: why);
  expect(r.profile.nik, p.nik, reason: why);
  expect(m.tensimeter.systolic, p.sys, reason: why);
  expect(m.tensimeter.diastolic, p.dia, reason: why);
  expect(m.tensimeter.pulse, p.pulse, reason: why);
  expect(m.pulseOximeter.spo2, p.spo2, reason: why);
  expect(m.pulseOximeter.heartRate, p.hr, reason: why);
  if (p.skipThermo) {
    expect(m.thermometer.temperature, isNull, reason: why);
  } else {
    expect(
      m.thermometer.temperature,
      closeTo(p.temperature, 0.001),
      reason: why,
    );
  }
  expect(m.weightScale.weight, closeTo(p.weight, 0.001), reason: why);
  if (p.hasHeight) {
    final hm = p.height / 100;
    expect(m.weightScale.bmi, closeTo(p.weight / (hm * hm), 1e-6), reason: why);
  } else {
    expect(m.weightScale.bmi, isNull, reason: '$why: BMI tanpa tinggi');
  }
  final g = m.gripStrength;
  final left = [
    g.gripLeft1,
    g.gripLeft2,
    g.gripLeft3,
  ].whereType<double>().toList();
  final right = [
    g.gripRight1,
    g.gripRight2,
    g.gripRight3,
  ].whereType<double>().toList();
  final n = p.partialGrip ? 2 : 6;
  expect(left.length + right.length, n, reason: why);
  final all = [...left, ...right]..sort();
  final want = p.grips.take(n).toList()..sort();
  for (var k = 0; k < n; k++) {
    expect(all[k], closeTo(want[k], 0.01), reason: why);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'R6: 40 lansia berturut-turut — ukur, simpan, cetak, muat ulang, ekspor',
    () async {
      await initializeDateFormatting('id_ID');
      final watch = Stopwatch()..start();
      SharedPreferences.setMockInitialValues({
        'device_registry_v1':
            '[{"type":"tensimeter","remoteId":"A","name":"Yuwell BP-YE670D"},'
            '{"type":"pulseOximeter","remoteId":"B","name":"KS M6100P"},'
            '{"type":"thermometer","remoteId":"C","name":"Yuwell HT-YHW"},'
            '{"type":"weightScale","remoteId":"D","name":"IF_B8B"},'
            '{"type":"gripStrength","remoteId":"E","name":"weixin-nini"}]',
      });
      await DeviceRegistryStore.instance.load();
      MeasurementSession.debugResetCarryOver();

      final dir = await Directory.systemTemp.createTemp('qa_r6');
      RecordStore.directoryProvider = () async => dir;
      final store = RecordStore.instance..debugReset();
      await store.load();

      var prints = 0;
      final printedPng = <int>[];
      final q = PrintQueue.instance
        ..printer = (Uint8List png) async {
          prints++;
          printedPng.add(png.length);
          return const PrintResult(true, 'Struk dicetak');
        };

      final ps = [for (var i = 0; i < people; i++) Person(i)];
      for (final p in ps) {
        expect(
          p.nik == null || Nik.isValid(p.nik),
          isTrue,
          reason: '${p.name} NIK ${p.nik}',
        );
      }
      final idOf = <int, String>{};
      for (final p in ps) {
        final m = runSession(p, p.i == 0 ? null : ps[p.i - 1]);
        final now = DateTime.now();
        var id = HealthRecord.newId(now);
        while (store.byId(id) != null) {
          id = HealthRecord.newId(now);
        }
        await store.add(
          HealthRecord(
            id: id,
            createdAt: now,
            startedAt: now.subtract(Duration(seconds: 150 + p.i)),
            profile: p.profile,
            measurements: m,
          ),
        );
        idOf[p.i] = id;
        q.enqueue(id, p.name); // cetak sambil lansia berikutnya diukur
      }
      for (var k = 0; k < 2000 && q.pending > 0; k++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final tUkur = watch.elapsedMilliseconds;

      // 1) Tersimpan, id unik, nilai tiap orang benar (tidak tertukar/bocor).
      expect(store.records.length, people);
      expect(idOf.values.toSet().length, people);
      for (final p in ps) {
        expectRecordMatches(store.byId(idOf[p.i]!)!, p);
      }

      // 2) Cetak: tepat satu struk per orang, printCount tersimpan.
      expect(q.failed, isEmpty);
      expect(prints, people);
      expect(printedPng.every((b) => b > 1000), isTrue);
      for (final p in ps) {
        expect(store.byId(idOf[p.i]!)!.printCount, 1, reason: p.name);
      }

      // 3) Muat ulang dari disk (aplikasi ditutup/dibuka).
      final before = {
        for (final r in store.records) r.id: jsonEncode(r.toJson()),
      };
      // Tunggu tulisan jumlah cetak terakhir benar-benar sampai di file.
      await store.flush();
      store.debugReset();
      await store.load();
      expect(store.skippedOnLoad, 0);
      expect(store.records.length, people);
      for (final r in store.records) {
        expect(
          jsonEncode(r.toJson()),
          before[r.id],
          reason: 'muat ulang ${r.id}',
        );
      }

      // 4) CSV: satu baris per orang, NIK disamarkan (UU PDP).
      final csv = CsvExport.build(store.records);
      final rows = csv.trim().split(RegExp(r'\r?\n'));
      expect(rows.length, people + 1);
      expect(csv, isNot(contains(ps[0].nik!)));

      // 5) SATUSEHAT: semua yang ber-NIK jadi Bundle, sisanya dilewati + alasan.
      const cfg = SatusehatConfig(
        orgId: '10000004',
        locationId: 'ef011065-38c9-46f8-9c35-d1fe68966a3e',
        locationName: 'Posyandu Lansia Melati',
        practitionerId: 'N10000001',
        practitionerName: 'Ns. Rina',
      );
      final batch = SatusehatExport.batch(store.records, cfg);
      final noNik = ps.where((p) => !p.hasNik).length;
      expect(batch.bundles.length, people - noNik);
      expect(batch.skipped.length, noNik);
      for (final reasons in batch.skipped.values) {
        expect(reasons.join(' '), contains('NIK'));
      }
      final encIds = <String>{};
      for (final b in batch.bundles) {
        final entries = (b['entry'] as List).cast<Map<String, dynamic>>();
        final enc = entries.first['resource'] as Map<String, dynamic>;
        encIds.add((enc['identifier'] as List).first['value'] as String);
        final nik = (enc['subject'] as Map)['identifier']['value'] as String;
        final p = ps.firstWhere((x) => x.nik == nik);
        final obs = entries
            .map((e) => e['resource'] as Map<String, dynamic>)
            .where((r) => r['resourceType'] == 'Observation')
            .toList();
        num? valueOf(String loinc) {
          for (final o in obs) {
            final codes = (o['code']['coding'] as List).map((c) => c['code']);
            if (codes.contains(loinc)) {
              return o['valueQuantity']['value'] as num;
            }
          }
          return null;
        }

        expect(valueOf('8480-6'), p.sys, reason: p.name);
        expect(valueOf('8462-4'), p.dia, reason: p.name);
        expect(valueOf('59408-5'), p.spo2, reason: p.name);
        expect(
          valueOf('29463-7'),
          closeTo(p.weight, 0.051),
          reason: p.name,
        ); // dibulatkan 1 desimal
        expect(
          valueOf('8310-5'),
          p.skipThermo ? isNull : closeTo(p.temperature, 0.051),
          reason: p.name,
        );
        expect(
          valueOf('39156-5') != null,
          p.hasHeight,
          reason: '${p.name} BMI',
        );
        expect(
          valueOf('8302-2') != null,
          p.hasHeight,
          reason: '${p.name} tinggi',
        );
        expect(
          valueOf('83173-5') != null || valueOf('83174-3') != null,
          isTrue,
          reason: '${p.name} genggam',
        );
      }
      expect(
        encIds.length,
        batch.bundles.length,
        reason: 'identifier Encounter ganda',
      );

      final out = Directory('build/satusehat_samples')
        ..createSync(recursive: true);
      File(
        '${out.path}/stress40.ndjson',
      ).writeAsStringSync('${batch.ndjson}\n');

      // 6) Tandai terekspor → ekspor "belum diekspor" berikutnya kosong.
      final ids = store.records
          .where((r) => !batch.skipped.containsKey(r.id))
          .map((r) => r.id)
          .toSet();
      await store.markSatusehatExported(ids, DateTime.now());
      final fresh = store.records
          .where((r) => r.satusehatExportedAt == null)
          .toList();
      expect(SatusehatExport.batch(fresh, cfg).bundles, isEmpty);

      // ignore: avoid_print
      print(
        'R6: $people lansia · ${batch.bundles.length} Bundle SATUSEHAT · '
        '${batch.skipped.length} dilewati (tanpa NIK) · $prints struk · '
        'sesi+simpan+cetak $tUkur ms · total ${watch.elapsedMilliseconds} ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
