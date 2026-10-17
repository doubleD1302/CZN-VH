import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:czn_patcher/main.dart';
import 'package:czn_patcher/ui/czn_tools_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> result = {}, receipt = {}, scan = {};
  final calls = <String>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({'companion_visible': false});
    receipt = {};
    scan = {'success': true};
    calls.clear();
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
              case 'lastOperation':
                return receipt;
              case 'checkUpdate':
                throw PlatformException(code: 'OFFLINE');
              case 'scanGame':
                return scan;
              case 'installBundled':
                receipt = {
                  ...result,
                  'action': 'installBundled',
                  'phase': result['success'] == true ? 'completed' : 'failed',
                };
                return result;
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
  Future<void> install(
    WidgetTester tester, {
    String label = 'Cài tiếng Việt',
  }) async {
    await tester.pumpWidget(const CznPatcherApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-setup')));
    await tester.pumpAndSettle();
    final button = find.byWidgetPredicate(
      (w) =>
          w is CznToolsButton &&
          w.primary &&
          w.label.toLowerCase() == label.toLowerCase(),
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(
      tester.widget<CznToolsButton>(button).onPressed,
      isNotNull,
      reason: calls.toString(),
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls, contains('installBundled'));
    for (var n = 0; n < 5; n++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder translationState(bool done) => find.byWidgetPredicate(
    (w) =>
        w is Semantics &&
        w.properties.label ==
            'Bản dịch: ${done ? "Đã hoàn tất" : "Chưa hoàn tất"}',
  );

  testWidgets('Cache failure is explicit and survives refresh/reopening', (
    tester,
  ) async {
    result = {
      'success': false,
      'message': 'Cache game chưa sẵn sàng.',
      'error_code': 'CACHE_FORMAT_UNSUPPORTED',
    };
    await install(tester);
    expect(find.text('Chưa cài được Việt hóa'), findsOneWidget);
    expect(find.text('Sao chép lỗi'), findsOneWidget);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(translationState(false), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const CznPatcherApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-setup')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('operation-result')));
    expect(find.byKey(const Key('operation-result')), findsOneWidget);
    expect(find.text('Cache game chưa sẵn sàng.'), findsWidgets);
  });
  testWidgets('Verified post-install hashes show success and step three done', (
    tester,
  ) async {
    result = {
      'success': true,
      'version': '1.4.1',
      'version_code': 10401,
      'post_install': {
        'success': true,
        'files_match': true,
        'installed_version': '1.4.1',
        'installed_code': 10401,
        'recovery_required': false,
      },
    };
    await install(tester);
    expect(find.text('Cài Việt hóa thành công'), findsOneWidget);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(translationState(true), findsOneWidget);
  });
  testWidgets('A success response without matching files is not marked done', (
    tester,
  ) async {
    result = {
      'success': true,
      'version_code': 10401,
      'post_install': {
        'success': true,
        'files_match': false,
        'installed_version': '1.4.1',
        'installed_code': 10401,
      },
    };
    await install(tester);
    expect(find.text('Chưa cài được Việt hóa'), findsOneWidget);
    expect(find.textContaining('Dữ liệu sau cài chưa khớp'), findsWidgets);
  });
  testWidgets('Failed readback clears the previous installed tick', (
    tester,
  ) async {
    scan = {
      'success': true,
      'files_match': true,
      'installed_version': '1.4.0',
      'installed_code': 10400,
    };
    result = {
      'success': false,
      'message': 'Đọc lại thất bại',
      'post_install': {
        'success': true,
        'files_match': false,
        'installed_version': '1.4.0',
        'installed_code': 10400,
      },
    };
    await install(tester, label: 'Cập nhật bản dịch');
    expect(find.text('Chưa cài được Việt hóa'), findsOneWidget);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(translationState(false), findsOneWidget);
  });
  testWidgets('Recovery journal prevents green installed tick', (tester) async {
    scan = {
      'success': true,
      'files_match': true,
      'installed_version': '1.4.1',
      'installed_code': 10401,
      'recovery_required': true,
    };
    await tester.pumpWidget(const CznPatcherApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-setup')));
    await tester.pumpAndSettle();
    expect(translationState(false), findsOneWidget);
  });
  testWidgets(
    'A failed new operation never inherits an old successful receipt',
    (tester) async {
      result = {
        'success': false,
        'message': 'Máy chủ GitHub phản hồi lỗi HTTP 404',
      };
      await tester.pumpWidget(const CznPatcherApp());
      await tester.pumpAndSettle();
      receipt = {
        'success': true,
        'post_install': {
          'success': true,
          'files_match': true,
          'installed_version': '1.4.0',
          'installed_code': 10400,
        },
      };
      final channel =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      channel.setMockMethodCallHandler(
        const MethodChannel('vn.czn.viethoa/patcher'),
        (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'status':
              return {
                'package': 'com.smilegate.chaoszero.stove.google',
                'accessGranted': true,
              };
            case 'installBundled':
              throw PlatformException(code: 'HTTP_404', message: 'HTTP 404');
            case 'lastOperation':
              return receipt;
            case 'scanGame':
              return {'success': true};
            default:
              return <String, dynamic>{};
          }
        },
      );
      await tester.tap(find.byKey(const Key('open-setup')));
      await tester.pumpAndSettle();
      final button = find.byWidgetPredicate(
        (w) =>
            w is CznToolsButton &&
            w.primary &&
            w.label.toLowerCase() == 'cài tiếng việt',
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Chưa cài được Việt hóa'), findsOneWidget);
      expect(
        calls.where((x) => x == 'lastOperation').length,
        1,
        reason: 'No read/merge of a previous native receipt after this new failure.',
      );
    },
  );
}
