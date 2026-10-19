// QA persona 5 — parser alat. Setiap test menegaskan perilaku yang BENAR;
// test gagal = bug. Disalin dari qa_tests/p5_parsers_test.dart + B-xx.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/ble/health_device_models.dart';
import 'package:health_station_lite/ble/measurement_session.dart';
import 'package:health_station_lite/ble/weight_scale_parser.dart';
import 'package:health_station_lite/data/device_registry_store.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bo = BleDeviceModel.Yuwell_BO_YX110;
const _ks = BleDeviceModel.KS_M6100P;
const _ht = BleDeviceModel.Yuwell_HT_YHW;
const _btbp = BleDeviceModel.Bluetooth_BP;
const _bp = BleDeviceModel.Yuwell_BP_YE670D;
const _ws = BleDeviceModel.IF_B8B;

List<int> fe55(int hr, int spo2) => [254, 10, 85, 0, hr, spo2, 23, 112, 11, 81];
const fe57 = [254, 10, 87, 10, 0, 0, 0, 0, 0, 95];

List<int> scaleMain(double kg, {required bool locked, int len = 12}) {
  final raw = (kg * 100).round();
  final v = List<int>.filled(len, 0);
  v[0] = 0x33;
  v[1] = 0xCC;
  v[6] = locked ? 0x81 : 0x80;
  final idx = len == 17 ? 8 : 10;
  v[idx] = (raw >> 8) & 0xFF;
  v[idx + 1] = raw & 0xFF;
  return v;
}

MeasurementSession session() => MeasurementSession(
  profile: const PersonProfile(
    name: 'QA',
    heightCm: 160,
    gender: Gender.female,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('id_ID'));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    MeasurementSession.debugResetCarryOver();
    WeightScaleParser.resetFloatBuffer();
    DeviceRegistryStore.instance.debugReset();
    await DeviceRegistryStore.instance.load();
  });

  group('BO-YX110 (FE len type …, 0x55 [4]=HR [5]=SpO2)', () {
    test(
      'P5-01 tiga frame digabung (57,55,55): frame 0x55 terakhir menang',
      () {
        final r = HealthParserUtils.parseOxymeter([
          ...fe57,
          ...fe55(70, 96),
          ...fe55(72, 97),
        ], _bo);
        expect(r.heartRate, 72);
        expect(r.oxygen, 97);
      },
    );

    test('P5-02 frame terpotong (< 6 byte) → tanpa nilai, tanpa crash', () {
      for (final v in [
        <int>[],
        [254],
        [254, 10],
        [254, 10, 85, 0, 76],
      ]) {
        final r = HealthParserUtils.parseOxymeter(v, _bo);
        expect(r.heartRate, isNull, reason: '$v');
        expect(r.oxygen, isNull, reason: '$v');
      }
    });

    test('P5-03 panjang frame 0 / <6 / 255 → tidak loop tak hingga', () {
      for (final n in [0, 1, 5, 255]) {
        final r = HealthParserUtils.parseOxymeter([
          254,
          n,
          85,
          0,
          70,
          96,
          0,
          0,
          0,
          0,
        ], _bo);
        // n<6 → berhenti; n=255 → frame pertama dibaca, lalu selesai.
        expect(r.heartRate == null || r.heartRate == 70, isTrue);
      }
    });

    test(
      'P5-04 frame 0x55 terpotong di tengah (6 byte dari 10) tidak crash',
      () {
        final r = HealthParserUtils.parseOxymeter([
          254,
          10,
          85,
          0,
          76,
          98,
        ], _bo);
        expect(r.heartRate, anyOf(isNull, 76));
      },
    );

    test(
      'P5-05 frame nol (jari dilepas) → 0/0, sesi tidak mencatat & gerbang terbuka',
      () {
        final r = HealthParserUtils.parseOxymeter(fe55(0, 0), _bo);
        expect(r.heartRate, 0);
        expect(r.oxygen, 0);
        final s = session();
        s.debugInjectPacket(fe55(0, 0), _bo);
        expect(s.measurements.pulseOximeter.spo2, isNull);
        expect(s.oxArmed, isTrue);
        s.dispose();
      },
    );

    test('P5-06 penanda tidak valid 127/255 tidak tercatat', () {
      final s = session();
      for (final (hr, o2) in [(127, 127), (255, 255), (255, 98), (76, 127)]) {
        s.debugInjectPacket(fe55(hr, o2), _bo);
      }
      expect(s.measurements.pulseOximeter.spo2, isNull);
      expect(s.measurements.pulseOximeter.heartRate, isNull);
      s.dispose();
    });

    test(
      'P5-07 SpO2 keluar dulu, nadi 0 → SpO2 tampil sementara, tidak "selesai"',
      () {
        final s = session();
        for (var i = 0; i < 8; i++) {
          s.debugInjectPacket(fe55(0, 97), _bo);
        }
        expect(s.measurements.pulseOximeter.spo2, 97);
        expect(s.stepOf(DeviceType.pulseOximeter), MeasureStep.measuring);
        s.dispose();
      },
    );

    test(
      'P5-08 5 frame 0x55 stabil → selesai; frame 0x57 di antaranya tidak mereset',
      () {
        final s = session();
        for (var i = 0; i < 5; i++) {
          s.debugInjectPacket([...fe57, ...fe55(76, 98)], _bo);
          s.debugInjectPacket(fe57, _bo);
        }
        expect(s.stepOf(DeviceType.pulseOximeter), MeasureStep.done);
        expect(s.measurements.pulseOximeter.spo2, 98);
        expect(s.measurements.pulseOximeter.heartRate, 76);
        s.dispose();
      },
    );

    test(
      'P5-09 aliran FE yang bergeser (frame mulai di byte 4) dibaca dari frame 0x55, '
      'bukan ditafsir format lama ([4]=0xFE sebagai nadi)',
      () {
        final r = HealthParserUtils.parseOxymeter([
          23,
          112,
          2,
          230,
          ...fe55(77, 97),
        ], _bo);
        expect(r.heartRate, 77, reason: 'nadi terbaca ${r.heartRate}');
        expect(r.oxygen, 97, reason: 'SpO2 terbaca ${r.oxygen}');
      },
    );

    test('P5-10 potongan paket bergeser tidak boleh mereset progres stabil', () {
      final s = session();
      for (var i = 0; i < 4; i++) {
        s.debugInjectPacket(fe55(76, 98), _bo);
      }
      expect(s.oxStableProgress, 4);
      s.debugInjectPacket([23, 112, 2, 230, ...fe55(76, 98)], _bo);
      s.debugInjectPacket(fe55(76, 98), _bo);
      expect(
        s.stepOf(DeviceType.pulseOximeter),
        MeasureStep.done,
        reason:
            'progres ${s.oxStableProgress}/5 — potongan paket dianggap jari lepas',
      );
      s.dispose();
    });
  });

  group('KS M6100P', () {
    test('P5-11 paket pendek → null; paket nol → 0/0 dan tidak tercatat', () {
      expect(
        HealthParserUtils.parseOxymeter([0, 0, 0, 70], _ks).heartRate,
        isNull,
      );
      final s = session();
      s.debugInjectPacket([0, 0, 0, 0, 0], _ks);
      s.debugInjectPacket([0, 0, 0, 255, 127], _ks);
      expect(s.measurements.pulseOximeter.spo2, isNull);
      s.dispose();
    });

    test('P5-12 SpO2 >100 atau nadi >220 ditolak', () {
      final s = session();
      s.debugInjectPacket([0, 0, 0, 70, 101], _ks);
      s.debugInjectPacket([0, 0, 0, 221, 97], _ks);
      expect(s.measurements.pulseOximeter.spo2, isNull);
      s.dispose();
    });
  });

  test('P5-13 Yuwell CM100 bisa didaftarkan sebagai oksimeter → parser harus '
      'menghasilkan nilai (kalau tidak, alat ini tidak boleh ditawarkan)', () {
    final offered = MeasurementSession.nameMatchesDeviceType(
      DeviceType.pulseOximeter,
      'Yuwell CM100',
    );
    final parsed = HealthParserUtils.parseOxymeter([
      254,
      10,
      85,
      0,
      76,
      98,
      0,
      0,
      0,
      0,
    ], BleDeviceModel.Yuwell_CM100);
    expect(
      !offered || parsed.oxygen != null,
      isTrue,
      reason: 'CM100 ditawarkan untuk Oksimeter tetapi tidak ada parsernya',
    );
  });

  group('Termometer', () {
    test('P5-14 HT-YHW FLOAT eksponen -2 (5 byte) → 36,6', () {
      expect(
        HealthParserUtils.parseTemperature([0x00, 0x4C, 0x0E, 0x00, 0xFE], _ht),
        closeTo(36.6, 1e-9),
      );
    });

    test(
      'P5-15 HT-YHW FLOAT eksponen -1 (366 × 10⁻¹) → 36,6 (spesifikasi 0x2A1C)',
      () {
        expect(
          HealthParserUtils.parseTemperature([
            0x00,
            0x6E,
            0x01,
            0x00,
            0xFF,
          ], _ht),
          closeTo(36.6, 1e-9),
        );
      },
    );

    test(
      'P5-16 HT-YHW flag Fahrenheit (98,6 °F) tidak boleh jadi °C salah',
      () {
        final t = HealthParserUtils.parseTemperature([
          0x01,
          0x84,
          0x26,
          0x00,
          0xFE,
        ], _ht);
        expect(t == null || (t - 37.0).abs() < 0.05, isTrue, reason: 't=$t');
      },
    );

    test('P5-17 HT-YHW pendek/nol → null; batas 34,0 & 42,0 diterima', () {
      expect(HealthParserUtils.parseTemperature([0x00, 0x4C], _ht), isNull);
      expect(HealthParserUtils.parseTemperature([0, 0, 0], _ht), isNull);
      expect(
        HealthParserUtils.parseTemperature([0, 0x48, 0x0D], _ht),
        closeTo(34.0, 1e-9),
      );
      expect(
        HealthParserUtils.parseTemperature([0, 0x68, 0x10], _ht),
        closeTo(42.0, 1e-9),
      );
      expect(HealthParserUtils.parseTemperature([0, 0x69, 0x10], _ht), isNull);
    });

    test('P5-18 "Bluetooth BP" ASCII sampah → sesi tidak mencatat', () {
      final s = session();
      s.debugInjectPacket(List.filled(9, 0x20), _btbp);
      s.debugInjectPacket(List.filled(9, 0x00), _btbp);
      s.debugInjectPacket([
        0,
        0,
        0,
        0,
        0,
        0x39,
        0x39,
        0x2E,
        0x39,
      ], _btbp); // 99.9
      expect(s.measurements.thermometer.temperature, isNull);
      s.dispose();
    });

    test('P5-19 satu bacaan valid → selesai; bacaan kedua tidak menimpa', () {
      final s = session();
      s.debugInjectPacket([0, 0x4C, 0x0E], _ht);
      s.debugInjectPacket([0, 0x14, 0x0F], _ht); // 38.6
      expect(s.measurements.thermometer.temperature, closeTo(36.6, 1e-9));
      expect(s.stepOf(DeviceType.thermometer), MeasureStep.done);
      s.dispose();
    });
  });

  group('Tensimeter 0x2A35', () {
    test(
      'P5-20 flag nadi TANPA cap waktu (0x04, 9 byte) → nadi di offset 7',
      () {
        final bp = HealthParserUtils.parseBloodPressure([
          0x04,
          128,
          0,
          82,
          0,
          95,
          0,
          76,
          0,
        ])!;
        expect(bp.systolic, 128);
        expect(bp.pulse, 76, reason: 'nadi diambil dari offset 14 tetap');
      },
    );

    test(
      'P5-21 flag 0x1E (cap waktu+nadi+user+status, 19 byte) → nadi di offset 14',
      () {
        final v = List<int>.filled(19, 0);
        v[0] = 0x1E;
        v[1] = 135;
        v[3] = 88;
        v[14] = 71;
        final bp = HealthParserUtils.parseBloodPressure(v)!;
        expect(bp.pulse, 71);
      },
    );

    test(
      'P5-22 NaN SFLOAT (0x07FF) & nol → sesi tidak mencatat / tidak selesai',
      () {
        final s = session();
        final nan = List<int>.filled(16, 0)
          ..[0] = 0x04
          ..[1] = 0xFF
          ..[2] = 0x07
          ..[3] = 0xFF
          ..[4] = 0x07;
        s.debugInjectPacket(nan, _bp);
        s.debugInjectPacket(List<int>.filled(16, 0), _bp);
        expect(s.measurements.tensimeter.systolic, isNull);
        expect(s.stepOf(DeviceType.tensimeter), MeasureStep.waiting);
        s.dispose();
      },
    );

    test('P5-23 satuan kPa (flag bit0) tidak boleh tersimpan sebagai mmHg', () {
      final s = session();
      // 17 kPa / 11 kPa (≈128/83 mmHg)
      s.debugInjectPacket([0x01, 17, 0, 11, 0, 14, 0], _bp);
      final t = s.measurements.tensimeter;
      expect(
        t.systolic == null || t.systolic! >= 100,
        isTrue,
        reason: '${t.systolic}',
      );
      s.dispose();
    });

    test('P5-24 hanya sistolik wajar → menunggu, belum selesai', () {
      final s = session();
      s.debugInjectPacket([0x00, 128, 0, 0xFF, 0x07, 0, 0], _bp);
      expect(s.measurements.tensimeter.systolic, 128);
      expect(s.stepOf(DeviceType.tensimeter), MeasureStep.measuring);
      s.dispose();
    });
  });

  group('Timbangan IF_B8B', () {
    test('P5-25 paket utama berat 0 → tidak tercatat, gerbang terbuka', () {
      final s = session();
      s.debugInjectPacket(scaleMain(0, locked: false), _ws);
      expect(s.measurements.weightScale.weight, isNull);
      expect(s.scaleArmed, isTrue);
      s.dispose();
    });

    test('P5-26 0xFFFF (655 kg) & paket 10/11 byte → tidak tercatat', () {
      final s = session();
      final v = scaleMain(0, locked: true)
        ..[10] = 0xFF
        ..[11] = 0xFF;
      s.debugInjectPacket(v, _ws);
      s.debugInjectPacket(scaleMain(60, locked: true).sublist(0, 11), _ws);
      s.debugInjectPacket(scaleMain(60, locked: true).sublist(0, 10), _ws);
      expect(s.measurements.weightScale.weight, isNull);
      s.dispose();
    });

    test('P5-27 paket 17 byte: berat dari byte 8–9', () {
      final s = session();
      s.debugInjectPacket(scaleMain(58.4, locked: false, len: 17), _ws);
      expect(s.measurements.weightScale.weight, closeTo(58.4, 1e-9));
      s.dispose();
    });

    test(
      'P5-28 berat belum terkunci → BMI dari tinggi, langkah "measuring"',
      () {
        final s = session();
        s.debugInjectPacket(scaleMain(64, locked: false), _ws);
        expect(s.measurements.weightScale.bmi, closeTo(25.0, 0.01));
        expect(s.stepOf(DeviceType.weightScale), MeasureStep.measuring);
        s.dispose();
      },
    );

    test('P5-29 paket final (03 03) dengan byte acak tidak crash', () {
      for (final v in [
        [0, 0, 0, 0, 3, 3, 0, 0],
        [255, 255, 255, 255, 3, 3, 255, 255],
      ]) {
        expect(
          () => WeightScaleParser.parse(v, deviceName: 'IF_B8B'),
          returnsNormally,
        );
      }
    });

    test('P5-30 paket acak 1–20 byte tidak melempar', () {
      for (var n = 1; n <= 20; n++) {
        final v = List<int>.generate(n, (i) => (i * 37 + n * 11) & 0xFF);
        expect(
          () => WeightScaleParser.parse(v, deviceName: 'IF_B8B'),
          returnsNormally,
        );
        expect(() => HealthParserUtils.parseOxymeter(v, _bo), returnsNormally);
        expect(() => HealthParserUtils.parseOxymeter(v, _ks), returnsNormally);
        expect(
          () => HealthParserUtils.parseTemperature(v, _ht),
          returnsNormally,
        );
        expect(
          () => HealthParserUtils.parseTemperature(v, _btbp),
          returnsNormally,
        );
        expect(() => HealthParserUtils.parseBloodPressure(v), returnsNormally);
      }
    });
  });

  test('P5-31 fromDeviceName: kosong, akhiran ganda, huruf kecil', () {
    expect(BleDeviceModel.fromDeviceName(''), isNull);
    expect(BleDeviceModel.fromDeviceName('yuwell bo-yx110-1DA3'), _bo);
    expect(BleDeviceModel.fromDeviceName('Yuwell BP-YE670D-AB12'), _bp);
    expect(BleDeviceModel.fromDeviceName('IF_B8B'), _ws);
  });

  group('B tambahan', () {
    test('B-P01 BO-YX110 sampah tanpa 0xFE (bukan 6 byte) → tanpa nilai', () {
      for (final v in [
        [23, 112, 2, 230, 77, 97, 11],
        [0, 77, 97, 23, 112, 2, 230, 1, 2, 3],
      ]) {
        final r = HealthParserUtils.parseOxymeter(v, _bo);
        expect(r.heartRate, isNull, reason: '$v');
        expect(r.oxygen, isNull, reason: '$v');
      }
    });

    test('B-P02 BO-YX110 frame 0x57 lalu sampah → tanpa nilai', () {
      final r = HealthParserUtils.parseOxymeter([
        ...fe57,
        23,
        112,
        2,
        230,
        9,
        9,
      ], _bo);
      expect(r.heartRate, isNull);
      expect(r.oxygen, isNull);
    });

    test('B-P03 0x2A35 tanpa flag nadi → nadi 0; flag 0x1C (nadi+user+status, '
        'tanpa cap waktu) → offset 7', () {
      expect(
        HealthParserUtils.parseBloodPressure([
          0x00,
          120,
          0,
          80,
          0,
          90,
          0,
        ])!.pulse,
        0,
      );
      final bp = HealthParserUtils.parseBloodPressure([
        0x1C,
        130,
        0,
        85,
        0,
        95,
        0,
        68,
        0,
        1,
        0,
        0,
      ])!;
      expect(bp.systolic, 130);
      expect(bp.pulse, 68);
    });

    test('B-P04 HT-YHW FLOAT eksponen 0 & mantisa negatif', () {
      expect(
        HealthParserUtils.parseTemperature([0x00, 37, 0, 0, 0x00], _ht),
        closeTo(37.0, 1e-9),
      );
      expect(
        HealthParserUtils.parseTemperature([0x00, 0xB4, 0xF1, 0xFF, 0xFE], _ht),
        isNull,
      ); // -36,6
    });

    test('B-P05 CM100 tidak ditawarkan untuk jenis alat apa pun', () {
      for (final t in DeviceType.values) {
        expect(
          MeasurementSession.nameMatchesDeviceType(t, 'Yuwell CM100'),
          isFalse,
        );
      }
      expect(
        MeasurementSession.nameMatchesDeviceType(
          DeviceType.pulseOximeter,
          'Yuwell BO-YX110-1DA3',
        ),
        isTrue,
      );
    });
  });
}
