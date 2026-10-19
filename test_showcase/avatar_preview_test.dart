// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_station_lite/app/motion.dart';
import 'package:health_station_lite/models/device_models.dart';
import 'package:health_station_lite/models/health_record.dart';
import 'package:health_station_lite/models/measurements.dart';
import 'package:health_station_lite/widgets/avatar3d.dart';

void main() {
  testWidgets('pratinjau avatar', (tester) async {
    final icons = FontLoader('MaterialIcons');
    await icons.load();
    Motion.enabled = false;
    tester.view.physicalSize = const Size(2000, 700);
    tester.view.devicePixelRatio = 1;
    Widget cell(AvatarPhase p, Gender? g, Map<DeviceType, AvatarSpot> spots,
            Set<DeviceType> on, {GripSide side = GripSide.left}) =>
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(8),
            color: Colors.white,
            child: ElderAvatar3D(phase: p, gender: g, spots: spots, devicesOn: on, gripSide: side),
          ),
        );
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF4F5F9),
        body: Row(children: [
          cell(AvatarPhase.standing, Gender.female, {
            DeviceType.weightScale: AvatarSpot.active,
            DeviceType.thermometer: AvatarSpot.done,
            DeviceType.pulseOximeter: AvatarSpot.active,
          }, {DeviceType.pulseOximeter, DeviceType.thermometer}),
          cell(AvatarPhase.seated, Gender.female, {
            DeviceType.tensimeter: AvatarSpot.active,
            DeviceType.pulseOximeter: AvatarSpot.done,
          }, {DeviceType.tensimeter, DeviceType.pulseOximeter}),
          cell(AvatarPhase.gripping, Gender.male, {
            DeviceType.gripStrength: AvatarSpot.active,
          }, {DeviceType.gripStrength}, side: GripSide.right),
          cell(AvatarPhase.finished, null, {}, {}),
        ]),
      ),
    ));
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/avatar_preview.png'));
    expect(File('test_showcase/screens/avatar_preview.png').existsSync(), isTrue);
  });
}
