// QA persona 10 (perbaikan D) — aksesibilitas layar petugas di iMin Falcon2
// (1920×1158 px @1,75 → ±1097×662 dp), skala teks 1,0 dan 1,3.
// Pemeriksaan per layar: tanpa overflow/galat, target sentuh ≥48 dp
// (androidTapTargetGuideline), kontras teks (textContrastGuideline),
// ukuran huruf minimum, dan teks Inggris yang bocor.
// ignore_for_file: invalid_use_of_visible_for_testing_member, avoid_print

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/motion.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/ble/measurement_session.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:health_station_lite/data/device_registry_store.dart';
import 'package:health_station_lite/data/member_store.dart';
import 'package:health_station_lite/data/record_store.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/screens/history_screen.dart';
import 'package:health_station_lite/screens/home_screen.dart';
import 'package:health_station_lite/screens/measurement_screen.dart';
import 'package:health_station_lite/screens/members_screen.dart';
import 'package:health_station_lite/screens/nfc_screen.dart';
import 'package:health_station_lite/screens/result_screen.dart';
import 'package:health_station_lite/screens/settings_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _size = Size(1920, 1158);
const _dpr = 1.75;
const _nik = '3201015203580001';
const _uid = '0E5E171105C65D';

/// Kata Inggris yang tidak boleh tampil di UI (nama produk/merek dikecualikan).
final _english = RegExp(
  r'\b(the|and|Hand grip|grip|Loading|Error|Cancel|OK|Save|Settings|Back|'
  r'Next|Done|Retry|Delete|Search|Close|Device|Connected|Connecting|Battery|'
  r'Unknown|Failed|Print|Select|Tap|Scan|Body|Weight|Height|Skip|Start|Stop|'
  r'Waiting|Ready|Show|Hide|Menu|Dismiss|BMR)\b',
);

enum Scr {
  homeCard,
  homeForm,
  members,
  memberForm,
  measure,
  result,
  history,
  settings,
  nfc,
}

/// Layar yang dilihat lansia langsung → huruf minimum 14 dp; layar petugas 12.
const _elderly = {Scr.homeCard, Scr.homeForm, Scr.measure, Scr.result};

/// Layar yang diperbaiki di batch D (Riwayat, Pengaturan, Pembaca NFC).
const _mine = [Scr.history, Scr.settings, Scr.nfc];

Future<void> _seed(Directory dir, {bool keyboard = true}) async {
  SharedPreferences.setMockInitialValues({
    'settings_onscreen_keyboard': keyboard,
    'settings_location_name': 'Posyandu Lansia Melati',
    'settings_ss_org_id': '10000004',
    'settings_ss_location_id': 'ef011065-38c9-46f8-9c35-d1fe68966a3e',
    'settings_ss_practitioner_id': 'N10000001',
    'device_registry_v1':
        '[{"type":"tensimeter","remoteId":"A","name":"Yuwell BP-YE670D"},'
        '{"type":"pulseOximeter","remoteId":"B","name":"KS M6100P"},'
        '{"type":"thermometer","remoteId":"C","name":"Yuwell HT-YHW"},'
        '{"type":"weightScale","remoteId":"D","name":"IF_B8B"},'
        '{"type":"gripStrength","remoteId":"E","name":"weixin-nini"}]',
  });
  final rec = Directory('${dir.path}/rec')..createSync(recursive: true);
  final mem = Directory('${dir.path}/mem')..createSync(recursive: true);
  for (final d in [rec, mem]) {
    for (final f in d.listSync()) {
      f.deleteSync(recursive: true);
    }
  }
  RecordStore.directoryProvider = () async => rec;
  MemberStore.directoryProvider = () async => mem;
  RecordStore.instance.debugReset();
  MemberStore.instance.debugReset();
  await AppSettings.instance.load();
  await DeviceRegistryStore.instance.load();
  await RecordStore.instance.load();
  await MemberStore.instance.load();
  final day = DateTime.now();
  for (var i = 0; i < 4; i++) {
    final at = DateTime(
      day.year,
      day.month,
      day.day,
      8 + i,
      10,
    ).subtract(Duration(days: 30 * i));
    await RecordStore.instance.add(
      HealthRecord(
        id: 'R$i',
        createdAt: at,
        startedAt: at.subtract(const Duration(seconds: 220)),
        profile: const PersonProfile(
          name: 'Siti Aminah Binti Abdurrahman Wahid',
          gender: Gender.female,
          age: 68,
          heightCm: 158,
          nik: _nik,
        ),
        measurements: AllMeasurements(
          tensimeter: TensimeterData(
            systolic: 128 + i * 4,
            diastolic: 82 + i,
            pulse: 74,
          ),
          pulseOximeter: const PulseOximeterData(spo2: 97, heartRate: 75),
          thermometer: const ThermometerData(temperature: 36.6),
          weightScale: WeightScaleData(
            weight: 58.4 + i * 0.3,
            bmi: 23.4,
            bodyFatPercent: 31.2,
          ),
          gripStrength: const GripStrengthData(
            gripLeft1: 19.5,
            gripRight1: 22.4,
          ),
          others: const OthersMeasurementData(height: 158),
        ),
      ),
    );
  }
  final now = DateTime.now();
  await MemberStore.instance.add(
    Member(
      uid: _uid,
      profile: const PersonProfile(
        name: 'Siti Aminah Binti Abdurrahman Wahid',
        gender: Gender.female,
        age: 68,
        heightCm: 158,
        nik: _nik,
      ),
      createdAt: now,
      updatedAt: now,
    ),
  );
}

Future<void> _settle(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _screen(Scr s) => switch (s) {
  Scr.homeCard || Scr.homeForm => const HomeScreen(),
  Scr.members => const MembersScreen(),
  Scr.memberForm => const MemberFormScreen(uid: '0101021229A23EE02'),
  Scr.measure => const MeasurementScreen(
    profile: PersonProfile(
      name: 'Siti Aminah Binti Abdurrahman Wahid',
      gender: Gender.female,
      age: 68,
      heightCm: 158,
    ),
  ),
  Scr.result => const ResultScreen(recordId: 'R0', justSaved: true),
  Scr.history => const HistoryScreen(),
  Scr.settings => const SettingsScreen(),
  Scr.nfc => const NfcScreen(),
};

/// Semua RenderParagraph yang terlihat (ukuran > 0, di dalam layar).
List<(String, double)> _paragraphs(WidgetTester tester) {
  final out = <(String, double)>[];
  final screen = Offset.zero & (_size / _dpr);
  void visit(RenderObject o) {
    if (o is RenderParagraph && o.hasSize && o.size.height > 0) {
      final box = MatrixUtils.transformRect(
        o.getTransformTo(null),
        Offset.zero & o.size,
      );
      if (box.overlaps(screen)) {
        double? min;
        o.text.visitChildren((span) {
          final fs = span.style?.fontSize;
          if (fs != null && span.toPlainText().trim().isNotEmpty) {
            min = min == null ? fs : (fs < min! ? fs : min);
          }
          return true;
        });
        final txt = o.text.toPlainText().trim();
        if (txt.isNotEmpty) out.add((txt, min ?? o.text.style?.fontSize ?? 14));
      }
    }
    o.visitChildren(visit);
  }

  visit(tester.binding.renderViews.first);
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Motion.enabled = false;
    Future<ByteData> font(String path) async =>
        ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);
    final lexend = FontLoader('Lexend');
    for (final w in [400, 500, 600, 700]) {
      lexend.addFont(font('assets/fonts/Lexend-$w.ttf'));
    }
    await lexend.load();
    await (FontLoader('MaterialIcons')..addFont(
          font(
            '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
        ))
        .load();
    await initializeDateFormatting('id_ID');
    Intl.defaultLocale = 'id_ID';
    dir = await Directory.systemTemp.createTemp('qa_p10');
  });

  void mockChannels() {
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
    messenger.setMockMethodCallHandler(
      const MethodChannel('imin_printer'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('caritahub/kiosk'),
      (_) async => true,
    );
  }

  Future<void> pumpScr(WidgetTester tester, Scr s, double scale) async {
    mockChannels();
    await tester.runAsync(() => _seed(dir, keyboard: s != Scr.homeCard));
    MeasurementSession.debugResetCarryOver();
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = _dpr;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('id', 'ID'),
        supportedLocales: const [Locale('id', 'ID'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: _screen(s),
      ),
    );
    await _settle(tester);
    if (s == Scr.homeForm) {
      await tester.tap(find.byKey(const Key('type_name_button')));
      await _settle(tester, 3);
      await tester.enterText(
        find.byKey(const Key('name_field')),
        'Siti Aminah Binti Abdurrahman',
      );
      await _settle(tester, 3);
    }
    if (s == Scr.measure) {
      final ses = debugLastMeasurementSession!;
      for (final t in DeviceType.values) {
        ses.debugSetStatus(t, DeviceStatus.connected);
      }
      await _settle(tester, 3);
    }
  }

  for (final s in _mine) {
    for (final scale in [1.0, 1.3]) {
      final tag = '${s.name} x$scale';

      testWidgets('layout tanpa overflow/galat · $tag', (tester) async {
        final errors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) =>
            errors.add(d.exceptionAsString().split('\n').first);
        addTearDown(() => FlutterError.onError = prev);
        await pumpScr(tester, s, scale);
        FlutterError.onError = prev;
        final e = tester.takeException();
        if (e != null) errors.add('$e'.split('\n').first);
        if (errors.isNotEmpty) {
          print('[LAYOUT $tag] ${errors.toSet().join(' | ')}');
        }
        expect(errors, isEmpty, reason: tag);
      });

      testWidgets('target sentuh ≥48 dp · $tag', (tester) async {
        final h = tester.ensureSemantics();
        await pumpScr(tester, s, scale);
        final r = await androidTapTargetGuideline.evaluate(tester);
        if (!r.passed) print('[TAP48 $tag] ${r.reason}');
        h.dispose();
        tester.takeException();
        expect(r.passed, isTrue, reason: r.reason);
      });

      testWidgets('kontras teks WCAG AA · $tag', (tester) async {
        final h = tester.ensureSemantics();
        await pumpScr(tester, s, scale);
        final r = await textContrastGuideline.evaluate(tester);
        if (!r.passed) print('[CONTRAST $tag] ${r.reason}');
        h.dispose();
        tester.takeException();
        expect(r.passed, isTrue, reason: r.reason);
      });

      if (scale == 1.0) {
        testWidgets('ukuran huruf minimum · $tag', (tester) async {
          await pumpScr(tester, s, scale);
          tester.takeException();
          final min = _elderly.contains(s) ? 14.0 : 12.0;
          final small = _paragraphs(tester).where((p) => p.$2 < min).toList();
          if (small.isNotEmpty) {
            print(
              '[FONT<$min $tag] ${small.map((p) => '"${p.$1.replaceAll('\n', ' ')}"=${p.$2}').toSet().join(', ')}',
            );
          }
          expect(small, isEmpty, reason: '${small.length} teks < $min dp');
        });

        testWidgets('tanpa teks Inggris · $tag', (tester) async {
          await pumpScr(tester, s, scale);
          tester.takeException();
          final eng = _paragraphs(
            tester,
          ).map((p) => p.$1).where((t) => _english.hasMatch(t)).toSet();
          if (eng.isNotEmpty) print('[ENGLISH $tag] $eng');
          expect(eng, isEmpty);
        });
      }
    }
  }

  testWidgets(
    'pengaturan: teks simpan otomatis sesuai perilaku (3 / 15 detik)',
    (tester) async {
      await pumpScr(tester, Scr.settings, 1.0);
      tester.takeException();
      // measurement_screen.dart _startCountdown: 15 detik bila masih ada alat
      // terdaftar yang belum tersambung, selain itu 3 detik.
      expect(find.textContaining('Jeda 3 detik'), findsOneWidget);
      expect(
        find.textContaining(
          '15 detik bila masih ada alat terdaftar yang belum '
          'tersambung',
        ),
        findsOneWidget,
      );
    },
  );
}
