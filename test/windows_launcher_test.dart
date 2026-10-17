import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:czn_patcher/services/windows_patch_service.dart';
import 'package:czn_patcher/ui/windows_game_path_dialog.dart';
import 'package:czn_patcher/ui/windows_home.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'windows_game_dir': r'C:\ProgramData\Smilegate\Games\ChaosZeroNightmare',
      'windows_auto_update': true,
      'companion_visible': true,
    });
  });

  group('Windows Launcher Remake 2.1.12 Tests', () {
    test('WindowsPatchService exposes distinct 2.1.12 versioning', () {
      expect(WindowsPatchService.currentVersion, equals('2.1.12'));
      expect(WindowsPatchService.currentVersionCode, equals(20112));
      expect(WindowsPatchService.currentVersion, isNot(contains('1.6.12')));
    });

    test('WindowsPatchService candidate directories include default and common paths', () {
      final service = WindowsPatchService();
      expect(
        service.candidateGameDirectories,
        contains(r'C:\ProgramData\Smilegate\Games\ChaosZeroNightmare'),
      );
      expect(
        service.candidateGameDirectories,
        contains(r'C:\Program Files\Smilegate\Games\ChaosZeroNightmare'),
      );
    });

    testWidgets('WindowsGamePathDialog renders manual text field and action buttons', (tester) async {
      final service = WindowsPatchService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WindowsGamePathDialog(
              currentPath: r'C:\ProgramData\Smilegate\Games\ChaosZeroNightmare',
              service: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ĐƯỜNG DẪN THƯ MỤC GAME CZN'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Tự động tìm'), findsOneWidget);
      expect(find.text('Lưu & Áp dụng'), findsOneWidget);
      expect(find.text('Hủy'), findsOneWidget);
    });

    testWidgets('WindowsHome renders landscape UI with 2.1.12 and companion', (tester) async {
      final service = WindowsPatchService();
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: windowsLauncherTheme,
          home: WindowsHome(service: service),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Verifies distinct 2.1.12 version label
      expect(find.textContaining('2.1.12'), findsWidgets);

      // Verifies companion is present
      expect(find.byKey(const Key('floating-companion')), findsOneWidget);

      // Verifies utility buttons
      expect(find.byKey(const Key('open-setup')), findsOneWidget);
      expect(find.byKey(const Key('open-updates')), findsOneWidget);
    });

    test('WindowsPatchService exposes launchChibiOverlay method', () {
      final service = WindowsPatchService();
      expect(service.launchChibiOverlay, isNotNull);
    });
  });
}
