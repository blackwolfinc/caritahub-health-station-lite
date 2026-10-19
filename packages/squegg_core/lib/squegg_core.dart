/// Flutter package for Squegg Smart Hand Grip Trainer BLE communication.
///
/// ## Quick start
///
/// ```dart
/// import 'package:squegg_core/squegg_core.dart';
///
/// final squegg = SqueggCore();
///
/// // Scan
/// await squegg.startScan();
/// squegg.scanResultsStream.listen((devices) => print(devices));
///
/// // Connect
/// await squegg.connect(deviceId);
///
/// // Read data
/// squegg.dataStream.listen((data) {
///   print('${data.strength} kg — squeezing: ${data.isSqueezing}');
/// });
///
/// // Disconnect
/// await squegg.disconnect();
/// ```
library;

export 'src/src.dart';
