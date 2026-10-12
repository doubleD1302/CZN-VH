import 'package:czn_patcher/main.dart';
import 'package:czn_patcher/services/patch_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  late Map<String, dynamic> remote;
  var state = 'installer_opened',
      pending = false,
      allowed = true,
      offline = false,
      failedDownload = false;
  setUp(() {
    SharedPreferences.setMockInitialValues({'companion_visible': false});
    calls.clear();
    state = 'installer_opened';
    pending = false;
    allowed = true;
    offline = false;
    failedDownload = false;
    remote = {
      'patch_version': '1.4.2',
      'patch_code': 10402,
      'changelog': '',
      'app_version': '1.5.2',
      'app_code': 10502,
      'app_size': 70000000,
      'app_url': 'https://example.com/app.apk',
      'app_sha256': List.filled(64, 'a').join(),
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('vn.czn.viethoa/progress'),
          (call) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('vn.czn.viethoa/patcher'),
          (call) async {
            calls.add(call.method);
            switch (call.method) {
              case 'status':
                return {
                  'package': null,
                  'accessGranted': false,
                  'appVersion': '1.5.1',
                  'appCode': 10501,
                  'pendingAppUpdate': pending,
                  'appInstallAllowed': allowed,
                };
              case 'bundledInfo':
                return {
                  'version': '1.4.2',
                  'version_code': 10402,
                  'changelog': '',
                };
              case 'cachedChannel':
                return remote;
              case 'lastOperation':
                return <String, dynamic>{};
              case 'checkUpdate':
                if (offline) throw PlatformException(code: 'OFFLINE');
                return remote;
              case 'downloadApp':
                if (failedDownload) {
                  throw PlatformException(
                    code: 'DOWNLOAD',
                    message: 'Tải APK thất bại.',
                  );
                }
                return '/private/updates/future.apk';
              case 'installApp':
                pending = state == 'permission_required';
                return {'state': state};
              case 'resumeAppUpdate':
                pending = false;
                return {'state': 'installer_opened'};
              default:
                return true;
            }
          },
        );
  });
  tearDown(() {
    for (final name in ['vn.czn.viethoa/patcher', 'vn.czn.viethoa/progress']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null);
    }
  });
  Future<void> update(WidgetTester tester) async {
    await tester.pumpWidget(const CznPatcherApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('app-update-button')),
      180,
    );
    await tester.ensureVisible(find.byKey(const Key('app-update-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-update-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('APK update downloads inside app without a game or Shizuku', (
    tester,
  ) async {
    await update(tester);
    expect(calls, containsAllInOrder(['downloadApp', 'installApp']));
    expect(calls, isNot(contains('requestAccess')));
    expect(calls, isNot(contains('scanGame')));
    expect(find.byKey(const Key('operation-result')), findsNothing);
    expect(find.textContaining('Xác nhận Cập nhật'), findsOneWidget);
    expect(find.text('Cài Việt hóa thành công'), findsNothing);
  });
  testWidgets(
    'Granting install permission resumes with the same downloaded APK',
    (tester) async {
      state = 'permission_required';
      allowed = false;
      await update(tester);
      expect(find.text('Tiếp tục cập nhật'), findsOneWidget);
      allowed = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls.where((c) => c == 'downloadApp').length, 1);
      expect(calls, contains('resumeAppUpdate'));
      expect(pending, false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'A downloaded pending APK can resume after reopening while offline',
    (tester) async {
      pending = true;
      allowed = true;
      offline = true;
      await tester.pumpWidget(const CznPatcherApp());
      await tester.pumpAndSettle();
      expect(calls, contains('resumeAppUpdate'));
      expect(calls, isNot(contains('downloadApp')));
      expect(pending, false);
    },
  );
  testWidgets(
    'Download failure stays explicit and does not open Android installer',
    (tester) async {
      failedDownload = true;
      await update(tester);
      expect(find.text('Chưa cập nhật được ứng dụng'), findsOneWidget);
      expect(find.textContaining('Tải APK thất bại'), findsWidgets);
      expect(calls, isNot(contains('installApp')));
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      failedDownload = false;
      await tester.ensureVisible(find.byKey(const Key('app-update-button')));
      await tester.tap(find.byKey(const Key('app-update-button')));
      await tester.pumpAndSettle();
      expect(calls, contains('installApp'));
    },
  );
  testWidgets('Small phone and large text keep the update button reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await update(tester);
    expect(calls, contains('installApp'));
    expect(tester.takeException(), isNull);
  });
  test('Same/older APK or malformed metadata is not offered', () {
    expect(
      AppUpdateInfo.fromChannel({...remote, 'app_code': 10501}, 10501),
      isNull,
    );
    expect(
      AppUpdateInfo.fromChannel({...remote, 'app_code': 10402}, 10501),
      isNull,
    );
    expect(
      AppUpdateInfo.fromChannel({...remote, 'app_url': 42}, 10501),
      isNull,
    );
    expect(
      AppUpdateInfo.fromChannel({...remote, 'app_sha256': 'wrong'}, 10501),
      isNull,
    );
  });
}
