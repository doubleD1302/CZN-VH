import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ui/home_screen.dart';
import 'ui/czn_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Shizuku API',
      'lz4-java',
      'SSRA reference',
    ], await rootBundle.loadString('assets/THIRD_PARTY_LICENSES.txt'));
  });
  runApp(const CznPatcherApp());
}

class CznPatcherApp extends StatelessWidget {
  const CznPatcherApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'CZN Việt Hóa',
    debugShowCheckedModeBanner: false,
    theme: CznTheme.dark,
    home: const HomeScreen(),
  );
}
