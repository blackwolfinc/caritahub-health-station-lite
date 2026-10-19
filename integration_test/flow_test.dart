// Uji alur lengkap di perangkat/simulator sungguhan:
//   fvm flutter test integration_test/flow_test.dart -d <device>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/main.dart' as app;
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/printing/print_queue.dart';
import 'package:integration_test/integration_test.dart';

Future<void> _settle(WidgetTester tester, [int n = 30]) async {
  // Hindari pumpAndSettle tanpa batas: indikator progres bisa terus beranimasi.
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('nama → Enter → isi suhu manual → selesai → kembali ke beranda',
      (tester) async {
    await app.main();
    await _settle(tester);

    const name = 'Uji Integrasi Lansia';
    const nik = '3201015203580001'; // perempuan, lahir 12-03-1958
    // Sisa data uji dari run sebelumnya.
    for (final r in RecordStore.instance.records.where((r) => r.profile.name == name).toList()) {
      await RecordStore.instance.delete(r.id);
    }
    final before = RecordStore.instance.records.length;

    // NIK (opsional) mengisi L/P & umur otomatis; nama lalu Enter memulai.
    await tester.tap(find.byKey(const Key('ktp_switch')));
    await _settle(tester, 2);
    await tester.enterText(find.byKey(const Key('nik_field')), nik);
    await _settle(tester, 5);
    await tester.enterText(find.byKey(const Key('name_field')), name);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await _settle(tester);
    expect(find.text(name), findsWidgets);
    expect(find.byKey(const Key('tile_thermometer')), findsOneWidget);

    // Isi suhu manual dari kotak Suhu (tanpa menghalangi kotak lain).
    final manual = find.byKey(const Key('manual_thermometer'));
    await tester.ensureVisible(manual);
    await tester.tap(manual);
    await _settle(tester);
    await tester.tap(find.byKey(const Key('measurement_field_Suhu tubuh')));
    await _settle(tester);
    await tester.enterText(find.byKey(const Key('field_dialog_input')), '36,7');
    await tester.tap(find.byKey(const Key('field_dialog_save')));
    await _settle(tester);
    // Tutup lembar isian.
    await tester.tapAt(const Offset(20, 80));
    await _settle(tester);
    expect(find.text('36,7'), findsWidgets);
    expect(find.text('Selesai'), findsWidgets);

    // Selesai → tersimpan → kembali ke beranda, siap lansia berikutnya.
    await tester.tap(find.byKey(const Key('save_button')));
    await _settle(tester, 10);
    // Alat lain belum selesai → ketuk sekali lagi untuk simpan sebagian.
    if (find.byKey(const Key('save_button')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('save_button')));
    }
    await _settle(tester, 40);
    expect(find.byKey(const Key('name_field')), findsOneWidget);
    expect(find.textContaining('$name tersimpan'), findsOneWidget);

    expect(RecordStore.instance.records.length, before + 1);
    final saved = RecordStore.instance.records.first;
    expect(saved.profile.name, name);
    expect(saved.measurements.thermometer.temperature, closeTo(36.7, 1e-9));
    expect(saved.profile.nik, nik);
    expect(saved.profile.gender, Gender.female);
    expect(saved.profile.birthDate, DateTime(1958, 3, 12));
    expect(saved.durationSeconds, isNotNull);

    // Bersihkan data uji.
    await RecordStore.instance.delete(saved.id);
    PrintQueue.instance.dismissFailed();
  });
}
