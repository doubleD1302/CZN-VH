import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ui/home_screen.dart';
import 'ui/windows_home.dart';
import 'ui/czn_theme.dart';
import 'ui/czn_wallpaper.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Shizuku API',
      'lz4-java',
      'SSRA reference',
    ], await rootBundle.loadString('assets/THIRD_PARTY_LICENSES.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Noto Serif',
    ], await rootBundle.loadString('assets/fonts/NotoSerif_OFL.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Roboto Condensed',
    ], await rootBundle.loadString('assets/fonts/RobotoCondensed_OFL.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Tinos',
    ], await rootBundle.loadString('assets/fonts/Tinos_LICENSE.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Noto Sans',
    ], await rootBundle.loadString('assets/fonts/Notosans_LICENSE.txt'));
  });
  final healthIndex = args.indexOf('--health-token');
  final healthToken = healthIndex >= 0 && healthIndex + 1 < args.length
      ? args[healthIndex + 1]
      : null;
  runApp(
    Platform.isWindows
        ? MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: windowsLauncherTheme,
            home: WindowsHome(healthToken: healthToken),
          )
        : const CznPatcherApp(),
  );
}

class CznPatcherApp extends StatelessWidget {
  const CznPatcherApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chaos Zero Nightmare Việt Hóa',
    debugShowCheckedModeBanner: false,
    theme: CznTheme.dark,
    builder: (context, child) => CznWallpaper(child: child!),
    home: const HomeScreen(),
  );
}
