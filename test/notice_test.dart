import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:czn_patcher/main.dart';
import 'package:czn_patcher/services/notice_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 12);
  const notice = CommunityNotice('n1', 'Tin mới', 'Nội dung');
  test('24 hour suppression expires and a new notice is not suppressed', () {
    final status = {
      'noticeSnoozeId': 'n1',
      'noticeSnoozeUntil': now
          .add(const Duration(hours: 24))
          .millisecondsSinceEpoch,
    };
    expect(notice.isSnoozed(status, now.add(const Duration(hours: 23))), true);
    expect(notice.isSnoozed(status, now.add(const Duration(hours: 24))), false);
    expect(
      const CommunityNotice('n2', 'Tin khác', 'Mới').isSnoozed(status, now),
      false,
    );
  });
  test('Disabled and malformed notices do not display', () {
    expect(
      CommunityNotice.fromChannel({
        'notice': {'enabled': false, 'id': 'n'},
      }),
      null,
    );
    expect(
      CommunityNotice.fromChannel({
        'notice': {'enabled': true, 'id': 'n', 'title': '', 'body': 'x'},
      }),
      null,
    );
  });
  testWidgets('Offline notice can close and is available on next launch', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('vn.czn.viethoa/patcher'),
          (call) async {
            switch (call.method) {
              case 'status':
                return {'package': null, 'accessGranted': false};
              case 'bundledInfo':
                return {
                  'version': '1.4.1',
                  'version_code': 10401,
                  'changelog': '',
                  'notice': {
                    'enabled': true,
                    'id': 'n1',
                    'title': 'Thông báo thử',
                    'body': 'Nội dung thử',
                  },
                };
              case 'cachedChannel':
                return <String, dynamic>{};
              case 'checkUpdate':
                throw PlatformException(code: 'OFFLINE');
              default:
                return true;
            }
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('vn.czn.viethoa/patcher'),
            null,
          ),
    );
    await tester.pumpWidget(const CznPatcherApp());
    await tester.pumpAndSettle();
    expect(find.text('Thông báo thử'), findsOneWidget);
    expect(find.text('Tắt trong 24 giờ'), findsOneWidget);
    await tester.tap(find.text('Tắt'));
    await tester.pumpAndSettle();
    expect(find.text('Thông báo thử'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const CznPatcherApp());
    await tester.pumpAndSettle();
    expect(find.text('Thông báo thử'), findsOneWidget);
  });
  testWidgets(
    'Scan failure does not block update checking and error is visible',
    (tester) async {
      var checked = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('vn.czn.viethoa/patcher'),
            (call) async {
              switch (call.method) {
                case 'status':
                  return {
                    'package': 'com.smilegate.chaoszero.stove.google',
                    'accessGranted': true,
                  };
                case 'bundledInfo':
                  return {
                    'version': '1.4.1',
                    'version_code': 10401,
                    'changelog': '',
                  };
                case 'cachedChannel':
                  return <String, dynamic>{};
                case 'scanGame':
                  throw PlatformException(
                    code: 'STORAGE_DENIED',
                    message: 'Xiaomi chưa cấp quyền',
                  );
                case 'checkUpdate':
                  checked = true;
                  return {
                    'patch_version': '1.4.2',
                    'patch_code': 10402,
                    'app_code': 10402,
                    'changelog': '',
                  };
                default:
                  return true;
              }
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('vn.czn.viethoa/patcher'),
              null,
            ),
      );
      await tester.pumpWidget(const CznPatcherApp());
      await tester.pumpAndSettle();
      expect(checked, true);
      await tester.scrollUntilVisible(
        find.text('Kiểm tra lại dữ liệu game'),
        150,
      );
      expect(find.textContaining('Xiaomi chưa cấp quyền'), findsWidgets);
      expect(tester.takeException(), null);
    },
  );
  testWidgets('Returning from game during a network check scans again', (
    tester,
  ) async {
    var scans = 0, checks = 0;
    final gate = Completer<Map<String, dynamic>>();
    final release = {
      'patch_version': '1.4.1',
      'patch_code': 10401,
      'changelog': '',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('vn.czn.viethoa/patcher'),
          (call) async {
            switch (call.method) {
              case 'status':
                return {
                  'package': 'com.smilegate.chaoszero.stove.google',
                  'accessGranted': true,
                };
              case 'bundledInfo':
                return {
                  'version': '1.4.1',
                  'version_code': 10401,
                  'changelog': '',
                };
              case 'cachedChannel':
                return <String, dynamic>{};
              case 'scanGame':
                scans++;
                return {'success': scans > 1, 'message': 'Chưa tải xong'};
              case 'checkUpdate':
                checks++;
                return checks == 1 ? gate.future : release;
              default:
                return true;
            }
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('vn.czn.viethoa/patcher'),
            null,
          ),
    );
    await tester.pumpWidget(const CznPatcherApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(scans, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    gate.complete(release);
    await tester.pumpAndSettle();
    expect(scans, 2);
    expect(find.textContaining('Đã tìm thấy dữ liệu CZN'), findsOneWidget);
  });
}
