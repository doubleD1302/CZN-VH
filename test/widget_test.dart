import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:czn_patcher/main.dart';
import 'package:czn_patcher/services/patch_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({'companion_visible': false});
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
    await tester.tap(find.byKey(const Key('open-setup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('game-wordmark')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('anniversary-background'))).size,
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    await tester.scrollUntilVisible(find.text('1. Kết nối Shizuku'), 150);
    expect(find.text('1. Kết nối Shizuku'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Bản đi kèm vẫn có thể cài.'),
      250,
    );
    expect(find.textContaining('Bản đi kèm vẫn có thể cài.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Setup and update are distinct tabs on a blurred wallpaper', (
    tester,
  ) async {
    await tester.pumpWidget(const CznPatcherApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tools-blurred-background')), findsNothing);
    await tester.tap(find.byKey(const Key('open-setup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tools-blurred-background')), findsOneWidget);
    expect(find.text('Kiểm tra cập nhật'), findsNothing);
    expect(find.text('1. Kết nối Shizuku'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tools-update-tab')));
    await tester.pumpAndSettle();
    expect(find.text('Kiểm tra cập nhật'), findsOneWidget);
    expect(find.text('1. Kết nối Shizuku'), findsNothing);
    await tester.tap(find.byTooltip('Về hình nền'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tools-blurred-background')), findsNothing);
    await tester.tap(find.byKey(const Key('open-updates')));
    await tester.pumpAndSettle();
    expect(find.text('Kiểm tra cập nhật'), findsOneWidget);
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
    await tester.tap(find.byKey(const Key('open-setup')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Cài từ gói tải sẵn'), 240);
    await tester.ensureVisible(find.text('Cài từ gói tải sẵn'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Hướng dẫn và trợ giúp'), 240);
    await tester.tap(find.text('Hướng dẫn và trợ giúp'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sao chép báo cáo'), 240);
    expect(tester.takeException(), isNull);
  });
}
