// Tampilkan 4 pose avatar di perangkat/simulator sungguhan (Impeller) supaya
// bisa di-screenshot:  fvm flutter test integration_test/avatar_view_test.dart -d <id>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/widgets/avatar3d.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('avatar di Impeller', (tester) async {
    Widget cell(AvatarPhase p, Gender? g, Map<DeviceType, AvatarSpot> spots,
            Set<DeviceType> on, {GripSide side = GripSide.left}) =>
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(4),
            color: Colors.white,
            child: ElderAvatar3D(phase: p, gender: g, spots: spots, devicesOn: on, gripSide: side),
          ),
        );
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF4F5F9),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: Row(children: [
                cell(AvatarPhase.standing, Gender.female, {
                  DeviceType.weightScale: AvatarSpot.active,
                  DeviceType.thermometer: AvatarSpot.done,
                  DeviceType.pulseOximeter: AvatarSpot.active,
                }, {DeviceType.pulseOximeter}),
                cell(AvatarPhase.seated, Gender.female, {
                  DeviceType.tensimeter: AvatarSpot.active,
                }, {DeviceType.tensimeter, DeviceType.pulseOximeter}),
              ]),
            ),
            Expanded(
              child: Row(children: [
                cell(AvatarPhase.gripping, Gender.male, {
                  DeviceType.gripStrength: AvatarSpot.active,
                }, {DeviceType.gripStrength}, side: GripSide.right),
                cell(AvatarPhase.finished, Gender.male, {}, {}),
              ]),
            ),
          ]),
        ),
      ),
    ));
    // Biarkan animasi berjalan; screenshot diambil dari luar (simctl).
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
