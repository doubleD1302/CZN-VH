import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:czn_patcher/ui/czn_landing.dart';
import 'package:czn_patcher/ui/czn_glass.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final viewports = <String, Size>{
    'Android Portrait (412x915)': const Size(412, 915),
    'Android Landscape (800x360)': const Size(800, 360),
    'Small Portrait (320x640)': const Size(320, 640),
    'Windows Desktop (1280x720)': const Size(1280, 720),
  };

  for (final entry in viewports.entries) {
    testWidgets('Measure CznDonateButton on ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool donateTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: entry.value),
            child: Scaffold(
              body: CznLanding(
                patchVersion: '1.9.4',
                appVersion: '1.9.4',
                access: true,
                ready: true,
                installed: true,
                busy: false,
                checking: false,
                message: '',
                primaryLabel: 'Cập nhật tiếng Việt',
                onPrimary: () {},
                onSetup: () {},
                onUpdates: () {},
                onHelp: () {},
                onDonate: () => donateTapped = true,
                isPc: entry.value.width >= 1000,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final donateFinder = find.byKey(const Key('open-donate'));
      expect(donateFinder, findsOneWidget);

      final visualFinder = find.byKey(const Key('donate-visual-pill'));
      expect(visualFinder, findsOneWidget);

      final Rect touchRect = tester.getRect(donateFinder);
      final Rect visualRect = tester.getRect(visualFinder);

      print('AFTER [${entry.key}]: visual=(w=${visualRect.width.toStringAsFixed(1)}, h=${visualRect.height.toStringAsFixed(1)}, left=${visualRect.left.toStringAsFixed(1)}, top=${visualRect.top.toStringAsFixed(1)}), touch=(w=${touchRect.width.toStringAsFixed(1)}, h=${touchRect.height.toStringAsFixed(1)}, left=${touchRect.left.toStringAsFixed(1)}, top=${touchRect.top.toStringAsFixed(1)})');

      // Test tap on touch target
      await tester.tap(donateFinder);
      expect(donateTapped, isTrue);
    });
  }
}
