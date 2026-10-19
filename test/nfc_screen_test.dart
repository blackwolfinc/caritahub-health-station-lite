import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/nfc_reader.dart';
import 'package:health_station_lite/app/theme.dart';
import 'package:health_station_lite/screens/nfc_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('pembaca NFC: status siap, kartu tampil dengan detailnya', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const methods = MethodChannel('caritahub/nfc');
    messenger.setMockMethodCallHandler(methods, (call) async {
      return switch (call.method) {
        'status' => {'available': true, 'enabled': true},
        'start' || 'stop' => true,
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(methods, null));
    // Event dari kanal 'caritahub/nfc/tags'.
    messenger.setMockMethodCallHandler(
      const MethodChannel('caritahub/nfc/tags'),
      (call) async => null,
    );

    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const NfcScreen()),
    );
    await tester.pump();
    expect(find.textContaining('Siap membaca'), findsOneWidget);

    // Kartu ditempel: kirim event seperti dari Android.
    const codec = StandardMethodCodec();
    await messenger.handlePlatformMessage(
      'caritahub/nfc/tags',
      codec.encodeSuccessEnvelope({
        'uid': '04 A2 1B 3C',
        'techs': ['IsoDep', 'NfcB'],
        'time': DateTime(2026, 10, 19, 2, 0).millisecondsSinceEpoch,
        'nfcB': {'applicationData': '00 00 00 00', 'protocolInfo': '81 81 85'},
        'isoDep': {'selectMf': '6A 82'},
      }),
      (_) {},
    );
    await tester.pump();
    expect(find.textContaining('UID 04 A2 1B 3C'), findsOneWidget);
    expect(find.text('IsoDep'), findsOneWidget);
    expect(find.text('nfcB.protocolInfo'), findsOneWidget);
    expect(find.text('isoDep.selectMf'), findsOneWidget);
  });

  test('kartu yang sama dalam 4 detik hanya dihitung sekali', () {
    final t0 = DateTime(2026, 10, 19, 2);
    expect(NfcReader.isNewTap('AA', t0), isTrue);
    expect(
      NfcReader.isNewTap('AA', t0.add(const Duration(seconds: 1))),
      isFalse,
    );
    // Diam di pembaca terus → tetap diabaikan (jendela bergeser).
    expect(
      NfcReader.isNewTap('AA', t0.add(const Duration(seconds: 4))),
      isFalse,
    );
    expect(
      NfcReader.isNewTap('BB', t0.add(const Duration(seconds: 5))),
      isTrue,
    );
    expect(
      NfcReader.isNewTap('AA', t0.add(const Duration(seconds: 6))),
      isTrue,
    );
    expect(
      NfcReader.isNewTap('AA', t0.add(const Duration(seconds: 11))),
      isTrue,
    );
  });
}
