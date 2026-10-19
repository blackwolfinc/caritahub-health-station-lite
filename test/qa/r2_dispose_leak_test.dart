// QA round 2 — the 8 s supervisor timer is armed after dispose() when the
// screen is closed while _initBluetooth() is still awaiting systemDevices()
// (no `_alive` check between `_sweepSystemDevices()` and `_armSupervisor()`).
// Periodic timers created by the session are tracked through a Zone.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/ble/measurement_session.dart';
import 'package:health_station_lite/data/device_registry_store.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SlowFbp extends FlutterBluePlusPlatform {
  final adapter = StreamController<BmBluetoothAdapterState>.broadcast();
  final desc = StreamController<BmDescriptorData>.broadcast();
  final conn = StreamController<BmConnectionStateResponse>.broadcast();
  @override
  Stream<BmBluetoothAdapterState> get onAdapterStateChanged => adapter.stream;
  @override
  Stream<BmDescriptorData> get onDescriptorWritten => desc.stream;
  @override
  Stream<BmConnectionStateResponse> get onConnectionStateChanged => conn.stream;
  @override
  Future<bool> isSupported(BmIsSupportedRequest request) async => true;
  @override
  Future<BmBluetoothAdapterState> getAdapterState(
          BmBluetoothAdapterStateRequest request) async =>
      BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on);
  @override
  Future<BmDevicesList> getSystemDevices(BmSystemDevicesRequest request) =>
      Future.delayed(const Duration(milliseconds: 500),
          () => BmDevicesList(devices: []));
  @override
  Future<bool> stopScan(BmStopScanRequest request) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('QA-LEAK-SUPERVISOR: no periodic timer may survive dispose()', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterBluePlusPlatform.instance = SlowFbp();
    await DeviceRegistryStore.instance.load();
    await DeviceRegistryStore.instance.register(const RegisteredDevice(
        type: DeviceType.thermometer, remoteId: 'C', name: 'Yuwell HT-YHW'));

    final periodic = <(Duration, Timer)>[];
    late MeasurementSession s;
    await runZoned(
      () async {
        s = MeasurementSession(profile: const PersonProfile(name: 'X'));
        await s.start();
      },
      zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, period, f) {
          final t = parent.createPeriodicTimer(zone, period, f);
          periodic.add((period, t));
          return t;
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    s.dispose(); // nurse leaves while systemDevices() is still pending
    await Future<void>.delayed(const Duration(seconds: 1));
    final alive = [
      for (final (p, t) in periodic)
        if (t.isActive) p,
    ];
    for (final (_, t) in periodic) {
      t.cancel();
    }
    expect(alive, isEmpty, reason: 'periodic timers alive after dispose: $alive');
  });
}
