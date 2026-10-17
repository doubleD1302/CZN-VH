import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:czn_patcher/ui/windows_home.dart';
import 'package:czn_patcher/services/windows_patch_service.dart';

class FakeWindowsService extends WindowsPatchService {
  final calls = <String>[];
  bool failInstall = false;
  bool failDownload = false;
  bool hasJapanese = true;
  bool installed = false;
  int cachedCode = 10625;
  int remoteCode = 10626;
  int? installedCode;
  @override
  bool isValidGameDir(String dir) => true;
  @override
  bool hasJapanesePackage(String dir) => hasJapanese;
  @override
  Future<String> getGameDirectory() async => r'C:\Games\ChaosZeroNightmare';
  @override
  Future<Map<String, dynamic>> translationInfo() async => {
    'version': '1.6.${cachedCode % 100}',
    'code': cachedCode,
  };
  @override
  Future<Map<String, dynamic>> run(String command, {String? token}) async {
    calls.add(command);
    switch (command) {
      case 'status':
        return {
          'success': true,
          'installed': installed,
          'files_match': installed,
          if (installedCode != null) 'installed_code': installedCode,
          'message': 'Sẵn sàng cài tiếng Việt.',
        };
      case 'check':
        return {
          'success': true,
          'channel': {
            'translation': {
              'version': '1.6.${remoteCode % 100}',
              'code': remoteCode,
            },
            'launcher': {'version': '1.4.0', 'code': 10400},
          },
        };
      case 'translation':
        if (failDownload) throw Exception('HTTP 404 · Không tải được bản dịch');
        cachedCode = remoteCode;
        return {'success': true, 'message': 'Đã xác minh bản dịch.'};
      case 'install':
        if (failInstall) throw Exception('HTTP 404 · Không tải được bản dịch');
        installed = true;
        installedCode = cachedCode;
        return {
          'success': true,
          'message': 'Đã cài và đọc lại dữ liệu. Chọn 日本語 trong game.',
          'post_install': {
            'success': true,
            'installed': true,
            'files_match': true,
            'installed_code': installedCode,
          },
        };
      default:
        return {'success': true};
    }
  }

  @override
  Future<void> launchGame({bool launchOverlay = true}) async =>
      calls.add('launch');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final text = FontLoader('CznSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans.ttf'));
    final primary = FontLoader('CznSerif')
      ..addFont(rootBundle.load('assets/fonts/NotoSerif.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await text.load();
    await primary.load();
    await icons.load();
  });
  setUp(
    () =>
        SharedPreferences.setMockInitialValues({'windows_auto_update': false}),
  );
  Future<void> load(
    WidgetTester tester,
    FakeWindowsService service,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: windowsLauncherTheme,
        home: RepaintBoundary(
          key: const Key('desktop-preview'),
          child: WindowsHome(service: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'One click downloads translation then installs without Android bridge',
    (tester) async {
      final service = FakeWindowsService();
      await load(tester, service, const Size(1280, 900));
      await tester.tap(find.byKey(const Key('windows-one-click')));
      await tester.pumpAndSettle();
      expect(service.calls, containsAllInOrder(['translation', 'install']));
      expect(find.textContaining('Đã cài'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Install failure never shows an old success', (tester) async {
    final service = FakeWindowsService()..failInstall = true;
    await load(tester, service, const Size(1280, 900));
    await tester.tap(find.byKey(const Key('windows-one-click')));
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 404'), findsWidgets);
    expect(find.text('Đã cài tiếng Việt'), findsNothing);
  });
  testWidgets(
    'Automatic download still requires installing into an older game',
    (tester) async {
      SharedPreferences.setMockInitialValues({'windows_auto_update': true});
      final service = FakeWindowsService()
        ..installed = true
        ..installedCode = 10625;
      await load(tester, service, const Size(1280, 900));
      expect(service.calls.where((c) => c == 'translation'), hasLength(1));
      expect(find.text('CẬP NHẬT BẢN DỊCH'), findsOneWidget);
      await tester.tap(find.byKey(const Key('windows-one-click')));
      await tester.pumpAndSettle();
      expect(service.calls, containsAllInOrder(['translation', 'install']));
      expect(service.calls.where((c) => c == 'translation'), hasLength(1));
      expect(service.calls, isNot(contains('launch')));
      expect(find.text('VÀO GAME CZN'), findsOneWidget);
      await tester.tap(find.byKey(const Key('windows-one-click')));
      await tester.pumpAndSettle();
      expect(service.calls.last, 'launch');
    },
  );
  testWidgets('Cached newer translation installs without downloading again', (
    tester,
  ) async {
    final service = FakeWindowsService()
      ..installed = true
      ..installedCode = 10625
      ..cachedCode = 10626;
    await load(tester, service, const Size(1280, 900));
    await tester.tap(find.byKey(const Key('windows-one-click')));
    await tester.pumpAndSettle();
    expect(service.calls, contains('install'));
    expect(service.calls, isNot(contains('translation')));
    expect(service.calls, isNot(contains('launch')));
  });
  testWidgets(
    'Missing installed receipt requires installing the known catalog',
    (tester) async {
      final service = FakeWindowsService()
        ..installed = true
        ..cachedCode = 10626;
      await load(tester, service, const Size(1280, 900));
      expect(find.text('CẬP NHẬT BẢN DỊCH'), findsOneWidget);
      await tester.tap(find.byKey(const Key('windows-one-click')));
      await tester.pumpAndSettle();
      expect(service.calls, contains('install'));
      expect(service.calls, isNot(contains('launch')));
    },
  );
  testWidgets(
    'Download failure never installs the old catalog or launches game',
    (tester) async {
      final service = FakeWindowsService()
        ..installed = true
        ..installedCode = 10625
        ..failDownload = true;
      await load(tester, service, const Size(1280, 900));
      await tester.tap(find.byKey(const Key('windows-one-click')));
      await tester.pumpAndSettle();
      expect(service.calls, contains('translation'));
      expect(service.calls, isNot(contains('install')));
      expect(service.calls, isNot(contains('launch')));
      expect(find.textContaining('HTTP 404'), findsWidgets);
    },
  );
  testWidgets(
    'Missing Japanese package blocks install and shows friendly guidance dialog',
    (tester) async {
      final service = FakeWindowsService()..hasJapanese = false;
      await load(tester, service, const Size(1280, 900));
      await tester.tap(find.byKey(const Key('windows-one-click')));
      await tester.pumpAndSettle();
      expect(find.text('Chưa tải gói Tiếng Nhật'), findsOneWidget);
      expect(find.textContaining('lang_ja_b01_0.ssrc'), findsOneWidget);
      expect(find.textContaining('Chọn 日本語'), findsOneWidget);
      expect(service.calls, isNot(contains('install')));
    },
  );
  for (final size in [
    const Size(1280, 900),
    const Size(800, 600),
    const Size(520, 720),
  ]) {
    testWidgets('Windows layout fits $size', (tester) async {
      await load(tester, FakeWindowsService(), size);
      expect(tester.takeException(), isNull);
      if (size.width == 1280) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('desktop-preview')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '../data/reports/WINDOWS_LAUNCHER_20261016/windows-ui-fixture.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
