// QA round 2 — end-to-end proof (fake FlutterBluePlus platform) that the
// next person's session immediately receives the PREVIOUS person's
// thermometer / blood-pressure value: MeasurementSession re-subscribes with
// `characteristic.lastValueStream`, which re-emits FBP's cached last value on
// listen (cache is only cleared on disconnect, and dispose() does not
// disconnect). Thermometer & tensimeter have no carry-over gate, so the stale
// value is locked as `done` and the real reading for the new person is then
// ignored.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/ble/measurement_session.dart';
import 'package:health_station_lite/data/device_registry_store.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class FakeFbp extends FlutterBluePlusPlatform {
  final conn = StreamController<BmConnectionStateResponse>.broadcast();
  final chr = StreamController<BmCharacteristicData>.broadcast();
  final disc = StreamController<BmDiscoverServicesResult>.broadcast();
  final desc = StreamController<BmDescriptorData>.broadcast();
  final wr = StreamController<BmCharacteristicData>.broadcast();
  final adapter = StreamController<BmBluetoothAdapterState>.broadcast();

  /// remoteId -> (service, characteristic)
  final Map<String, (String, String)> gatt = {};

  @override
  Stream<BmConnectionStateResponse> get onConnectionStateChanged => conn.stream;
  @override
  Stream<BmCharacteristicData> get onCharacteristicReceived => chr.stream;
  @override
  Stream<BmDiscoverServicesResult> get onDiscoveredServices => disc.stream;
  @override
  Stream<BmDescriptorData> get onDescriptorWritten => desc.stream;
  @override
  Stream<BmDescriptorData> get onDescriptorRead => desc.stream;
  @override
  Stream<BmCharacteristicData> get onCharacteristicWritten => wr.stream;
  @override
  Stream<BmBluetoothAdapterState> get onAdapterStateChanged => adapter.stream;

  @override
  Future<bool> isSupported(BmIsSupportedRequest request) async => true;
  @override
  Future<BmBluetoothAdapterState> getAdapterState(
          BmBluetoothAdapterStateRequest request) async =>
      BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on);
  @override
  Future<BmDevicesList> getSystemDevices(BmSystemDevicesRequest request) async =>
      BmDevicesList(devices: []);
  @override
  Future<bool> stopScan(BmStopScanRequest request) async => true;
  @override
  Future<bool> startScan(BmScanSettings request) async => true;
  @override
  Future<bool> connect(BmConnectRequest request) async => true;
  @override
  Future<bool> setNotifyValue(BmSetNotifyValueRequest request) async => false;

  @override
  Future<bool> discoverServices(BmDiscoverServicesRequest request) async {
    final id = request.remoteId;
    final (svc, ch) = gatt[id.str]!;
    scheduleMicrotask(() => disc.add(BmDiscoverServicesResult(
          remoteId: id,
          success: true,
          errorCode: 0,
          errorString: '',
          services: [
            BmBluetoothService(
              remoteId: id,
              primaryServiceUuid: null,
              serviceUuid: Guid(svc),
              characteristics: [
                BmBluetoothCharacteristic(
                  remoteId: id,
                  primaryServiceUuid: null,
                  serviceUuid: Guid(svc),
                  characteristicUuid: Guid(ch),
                  instanceId: 0,
                  descriptors: [],
                  properties: BmCharacteristicProperties(
                    broadcast: false,
                    read: false,
                    writeWithoutResponse: false,
                    write: false,
                    notify: true,
                    indicate: true,
                    authenticatedSignedWrites: false,
                    extendedProperties: false,
                    notifyEncryptionRequired: false,
                    indicateEncryptionRequired: false,
                  ),
                ),
              ],
            ),
          ],
        )));
    return true;
  }

  void connected(String id) => conn.add(BmConnectionStateResponse(
      remoteId: DeviceIdentifier(id),
      connectionState: BmConnectionStateEnum.connected,
      disconnectReasonCode: null,
      disconnectReasonString: null));

  void notify(String id, List<int> value) {
    final (svc, ch) = gatt[id]!;
    chr.add(BmCharacteristicData(
      remoteId: DeviceIdentifier(id),
      primaryServiceUuid: null,
      serviceUuid: Guid(svc),
      characteristicUuid: Guid(ch),
      instanceId: 0,
      value: Uint8List.fromList(value),
      success: true,
      errorCode: 0,
      errorString: '',
    ));
  }
}

List<int> bp(int sys, int dia, int pulse) {
  final v = List<int>.filled(16, 0);
  v[0] = 0x04;
  v[1] = sys;
  v[3] = dia;
  v[14] = pulse;
  return v;
}

Future<void> settle([int ms = 400]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('QA-REPLAY: previous person temperature & BP must NOT be locked into '
      'the next person session', () async {
    SharedPreferences.setMockInitialValues({});
    MeasurementSession.debugResetCarryOver();
    final fake = FakeFbp()
      ..gatt['C'] = ('1809', '2a1c') // Yuwell HT-YHW
      ..gatt['A'] = ('1810', '2a35'); // Yuwell BP-YE670D
    FlutterBluePlusPlatform.instance = fake;

    final reg = DeviceRegistryStore.instance;
    await reg.load();
    await reg.register(const RegisteredDevice(
        type: DeviceType.thermometer, remoteId: 'C', name: 'Yuwell HT-YHW'));
    await reg.register(const RegisteredDevice(
        type: DeviceType.tensimeter, remoteId: 'A', name: 'Yuwell BP-YE670D'));

    await FlutterBluePlus.isSupported; // initialise FBP listeners
    fake.connected('C');
    fake.connected('A');
    await settle(50);

    // ── Person A ──
    final a = MeasurementSession(profile: const PersonProfile(name: 'A'));
    await a.start();
    await settle();
    expect(a.deviceOf(DeviceType.thermometer).status, DeviceStatus.connected);
    fake.notify('C', [0, 0xA0, 0x0F]); // 40.0 °C — A has fever
    fake.notify('A', bp(168, 104, 96)); // A hypertensive
    await settle(50);
    expect(a.measurements.thermometer.temperature, closeTo(40.0, 1e-9));
    expect(a.measurements.tensimeter.systolic, 168);
    a.dispose(); // record saved; devices stay connected (by design)

    // ── Person B, a few seconds later — B has NOT been measured yet ──
    await settle(300);
    final b = MeasurementSession(profile: const PersonProfile(name: 'B'));
    await b.start();
    await settle();
    // ignore: avoid_print
    print('B after start: temp=${b.measurements.thermometer.temperature} '
        'step=${b.stepOf(DeviceType.thermometer)} '
        'bp=${b.measurements.tensimeter.toJson()} '
        'step=${b.stepOf(DeviceType.tensimeter)}');
    expect(b.measurements.thermometer.temperature, isNull,
        reason: "A's 40.0 °C replayed into B and locked as done");
    expect(b.measurements.tensimeter.systolic, isNull,
        reason: "A's BP replayed into B and locked as done");

    // B's real reading is then ignored because the step is already done.
    fake.notify('C', [0, 0x4C, 0x0E]); // 36.6 °C
    await settle(50);
    expect(b.measurements.thermometer.temperature, closeTo(36.6, 1e-9));
    b.dispose();
  });
}
