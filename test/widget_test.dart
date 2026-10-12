import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:czn_patcher/main.dart';
import 'package:czn_patcher/services/patch_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('vn.czn.viethoa/patcher'),
          (call) async {
            switch (call.method) {
              case 'status':
                return {
                  'package': null,
                  'shizukuRunning': false,
                  'accessGranted': false,
                  'autoDownload': true,
                  'channel': 'https://github.com/doubleD1302/CZN-VH/releases/latest/download/channel.json',
                };
              case 'bundledInfo':
                return {
                  'version': '1.4.0',
                  'version_code': 10400,
                  'changelog': 'Bản đi kèm',
                };
              case 'checkUpdate':
                throw PlatformException(code: 'OFFLINE', message: 'Offline');
              default:
                return false;
            }
          },
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('vn.czn.viethoa/patcher'),
          null,
        ),
  );
  test('Update comparison does not offer a downgrade', () {
    final info = ReleaseInfo.channel({
      'patch_version': '1.4.0',
      'patch_code': 10400,
      'changelog': '',
      'patch_url': 'https://example.com',
    });
    expect(info.newerThan(10500), false);
    expect(info.newerThan(10300), true);
  });
  testWidgets('Offline onboarding works and explains Shizuku', (tester) async {
    await tester.pumpWidget(const CznPatcherApp());
    await tester.pumpAndSettle();
    expect(find.text('CZN Việt Hóa'), findsOneWidget);
    expect(find.text('1. Kết nối Shizuku'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Bản đi kèm vẫn có thể cài.'),
      250,
    );
    expect(find.textContaining('Bản đi kèm vẫn có thể cài.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Small phone and large text keep actions readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const CznPatcherApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
