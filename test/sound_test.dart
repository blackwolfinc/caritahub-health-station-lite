import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/sound.dart';
import 'package:health_station_lite/data/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('caritahub/sound');
  final played = <Map<Object?, Object?>>[];

  setUp(() async {
    played.clear();
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    messenger.setMockMethodCallHandler(channel, (call) async {
      played.add(call.arguments as Map<Object?, Object?>);
      return true;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('efek suara menyala bawaan; ketuk & detak lebih pelan', () async {
    Sound.play(Sfx.card);
    Sound.play(Sfx.tap);
    await flush();
    expect(played, [
      {'name': 'card', 'volume': 1.0},
      {'name': 'tap', 'volume': 0.35},
    ]);
  });

  test(
    'suara dimatikan → tidak ada bunyi; bunyi keyboard bisa terpisah',
    () async {
      await AppSettings.instance.setKeySound(false);
      Sound.play(Sfx.tap);
      Sound.play(Sfx.success);
      await AppSettings.instance.setSound(false);
      Sound.play(Sfx.error);
      await flush();
      expect(played, [
        {'name': 'success', 'volume': 1.0},
      ]);
    },
  );

  test('tanpa plugin native: diam, tidak melempar galat', () async {
    messenger.setMockMethodCallHandler(channel, null);
    Sound.play(Sfx.done);
    await flush();
  });
}
