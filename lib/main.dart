import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app/kiosk.dart';
import 'app/theme.dart';
import 'data/app_settings.dart';
import 'data/device_registry_store.dart';
import 'data/member_store.dart';
import 'data/record_store.dart';
import 'printing/printer_service.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  Intl.defaultLocale = 'id_ID';
  await Future.wait([
    AppSettings.instance.load(),
    RecordStore.instance.load(),
    DeviceRegistryStore.instance.load(),
    MemberStore.instance.load(),
  ]);
  runApp(const HealthStationLiteApp());
  unawaited(Kiosk.restore());
  // Lebar kertas belum pernah dipilih → ikuti printer iMin.
  unawaited(
    PrinterService.instance.detectPaper().then((p) {
      if (p != null && !AppSettings.instance.paperChosen) {
        AppSettings.instance.setPaper(p);
      }
    }),
  );
}

class HealthStationLiteApp extends StatelessWidget {
  const HealthStationLiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health Station Lite',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeScreen(),
    );
  }
}
