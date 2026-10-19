// QA persona 10 (perbaikan D) — kontras token tema (grey4, hint), label
// bilah status alat, teks simpan otomatis, dan tombol dialog setelah simpan.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/data/device_registry_store.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/widgets/after_save_dialogs.dart';
import 'package:health_station_lite/widgets/device_status_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

double ratio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Lexend asli supaya lebar teks realistis (bukan font tes Ahem).
    Future<ByteData> font(String path) async =>
        ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);
    final lexend = FontLoader('Lexend');
    for (final w in [400, 500, 600, 700]) {
      lexend.addFont(font('assets/fonts/Lexend-$w.ttf'));
    }
    await lexend.load();
  });

  group('kontras token tema', () {
    // (nama, teks, latar, minimum)
    final pairs = <(String, Color, Color, double)>[
      ('P10-5 grey4 di putih', AppColors.grey4, AppColors.surface, 4.5),
      ('P10-5 grey4 di background', AppColors.grey4, AppColors.background, 4.5),
      ('P10-5 grey4 di lightGrey', AppColors.grey4, AppColors.lightGrey, 4.5),
      (
        'P10-5 grey4 di primarySoft',
        AppColors.grey4,
        AppColors.primarySoft,
        4.5,
      ),
      ('P10-5 grey4 di greenSoft', AppColors.grey4, AppColors.greenSoft, 4.5),
      (
        'P10-5 grey4 di orangeActionBg',
        AppColors.grey4,
        AppColors.orangeActionBg,
        4.5,
      ),
      // Placeholder: WCAG non-teks/placeholder ≥3:1.
      ('P10-4 hint di lightGrey', AppColors.hint, AppColors.lightGrey, 3.0),
      ('P10-4 hint di putih', AppColors.hint, AppColors.surface, 3.0),
      ('Teks utama charcoal/putih', AppColors.charcoal, AppColors.surface, 4.5),
      ('Tombol primer putih/primary', Colors.white, AppColors.primary, 4.5),
    ];
    for (final (name, fg, bg, min) in pairs) {
      test(name, () {
        final r = ratio(fg, bg);
        expect(
          r,
          greaterThanOrEqualTo(min),
          reason: '$name → ${r.toStringAsFixed(2)}:1',
        );
      });
    }

    test('P10-4 hint tetap jelas lebih muda dari teks isian', () {
      final theme = buildAppTheme();
      final hint = theme.inputDecorationTheme.hintStyle!.color!;
      final fill = theme.inputDecorationTheme.fillColor!;
      expect(hint, AppColors.hint);
      expect(ratio(hint, fill), greaterThanOrEqualTo(3.0));
      // Isian charcoal jauh lebih gelap dari hint (beda ≥2× kontras).
      expect(
        ratio(AppColors.charcoal, fill) / ratio(hint, fill),
        greaterThan(2),
      );
      // Hint lebih muda dari teks sekunder grey4.
      expect(
        hint.computeLuminance(),
        greaterThan(AppColors.grey4.computeLuminance()),
      );
    });

    test('P10-5 grey4 tetap lebih muda dari grey1 (hierarki teks)', () {
      expect(
        AppColors.grey4.computeLuminance(),
        greaterThan(AppColors.grey1.computeLuminance()),
      );
    });
  });

  group('bilah status alat (header beranda)', () {
    Future<void> pumpBar(WidgetTester tester, String registry) async {
      SharedPreferences.setMockInitialValues({'device_registry_v1': registry});
      await tester.runAsync(DeviceRegistryStore.instance.load);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: DeviceStatusBar(onManage: () {}),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('angka bertuliskan "terdaftar", bukan hanya "2/5"', (
      tester,
    ) async {
      await pumpBar(
        tester,
        '[{"type":"tensimeter","remoteId":"A","name":"Yuwell"},'
        '{"type":"weightScale","remoteId":"D","name":"IF_B8B"}]',
      );
      final n = DeviceType.values.length;
      expect(find.text('2/$n'), findsOneWidget);
      expect(find.text('terdaftar'), findsOneWidget);
      final h = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('2 dari $n alat terdaftar')),
        findsOneWidget,
      );
      h.dispose();
      // Tooltip per alat: "terdaftar" / "belum terdaftar".
      final tips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(tips, contains('${DeviceType.tensimeter.label} terdaftar'));
      expect(tips, contains('${DeviceType.thermometer.label} belum terdaftar'));
      expect(tips.where((m) => m!.contains('terpasang')), isEmpty);
    });

    testWidgets('tetap ringkas: muat di header Falcon2 tanpa overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1158);
      tester.view.devicePixelRatio = 1.75;
      addTearDown(tester.view.reset);
      await pumpBar(tester, '[]');
      expect(tester.takeException(), isNull);
      final s = tester.getSize(find.byKey(const Key('device_status_bar')));
      // Dulu ±280 dp ('0/5'); label 2 baris menambah ±40 dp saja.
      expect(s.width, lessThan(330), reason: 'lebar ${s.width} dp');
      expect(s.height, greaterThanOrEqualTo(48));
    });
  });

  group('dialog setelah simpan', () {
    testWidgets('"Cetak catatan" & "Lanjut ukur" ≥48 dp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAfterSaveDialog(context, name: 'Siti'),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('buka'));
      await tester.pumpAndSettle();
      expect(find.text('Cetak catatan'), findsOneWidget);
      for (final k in ['after_save_print', 'after_save_next']) {
        final s = tester.getSize(find.byKey(Key(k)));
        expect(s.height, greaterThanOrEqualTo(48), reason: k);
      }
    });
  });
}
