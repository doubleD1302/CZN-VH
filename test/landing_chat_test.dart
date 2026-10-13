import 'dart:convert';
import 'dart:ui' show SemanticsAction;

import 'package:czn_patcher/main.dart';
import 'package:czn_patcher/ui/czn_landing.dart';
import 'package:czn_patcher/ui/czn_glass.dart';
import 'package:czn_patcher/ui/companion_dialog.dart';
import 'package:czn_patcher/ui/czn_wallpaper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class FakeLauncher extends UrlLauncherPlatform {
  String? opened;
  @override
  Null get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened = url;
    expect(options.mode, PreferredLaunchMode.externalApplication);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [
    const Size(320, 640),
    const Size(412, 915),
    const Size(800, 360),
  ]) {
    testWidgets(
      'Wallpaper fills screen and overlay actions work at $size and large text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => CznWallpaper(child: child!),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(1.8),
              ),
              child: Scaffold(
                body: CznLanding(
                  patchVersion: '1.5.5',
                  appVersion: '1.6.0',
                  access: false,
                  ready: false,
                  installed: false,
                  busy: false,
                  checking: false,
                  message: '',
                  primaryLabel: 'Thiết lập tiếng Việt',
                  onPrimary: () {},
                  onSetup: () {},
                  onUpdates: () {},
                  onHelp: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final art = tester.getRect(
          find.byKey(const Key('anniversary-background')),
        );
        final dock = tester.getRect(find.byKey(const Key('landing-primary')));
        expect(art.overlaps(dock), true);
        expect(art.size, size);
        expect(art.height, greaterThan(0));
        expect(
          tester
              .widget<Image>(find.byKey(const Key('anniversary-background')))
              .fit,
          BoxFit.cover,
        );
        expect(
          find.byKey(const Key('landing-primary')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Enabled glass actions expose taps to screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CznGlassPrimary(
                key: const Key('enabled-primary'),
                label: 'Cài tiếng Việt',
                onPressed: () {},
              ),
              CznGlassUtility(
                key: const Key('enabled-utility'),
                label: 'Thiết lập',
                icon: Icons.settings,
                onPressed: () {},
              ),
              const CznGlassPrimary(
                key: Key('disabled-primary'),
                label: 'Đang cài',
                onPressed: null,
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Cài tiếng Việt'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      true,
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('enabled-utility')))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      true,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Đang cài'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      false,
    );
    semantics.dispose();
  });

  testWidgets(
    'Legacy saved sprite extremes and rotation never block home actions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'companion_visible': true,
        'companion_x': .96,
        'companion_y': 1.0,
      });
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('vn.czn.viethoa/patcher');
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'bundledInfo') {
          return {'version': '1.6.5', 'version_code': 10605, 'changelog': ''};
        }
        return <String, dynamic>{};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(const CznPatcherApp());
      await tester.pump(const Duration(milliseconds: 500));
      final sprite = find.byKey(const Key('floating-companion'));
      void check() {
        final rect = tester.getRect(sprite);
        for (final key in [
          'landing-primary',
          'open-setup',
          'open-updates',
          'open-help',
          'game-wordmark',
        ]) {
          expect(
            rect.overlaps(tester.getRect(find.byKey(Key(key)))),
            false,
            reason: key,
          );
        }
        expect(rect.overlaps(tester.getRect(find.byTooltip('Cài đặt'))), false);
        expect(
          rect.overlaps(tester.getRect(find.byTooltip('Thông báo cộng đồng'))),
          false,
        );
        expect(tester.takeException(), isNull);
      }

      check();
      await tester.drag(sprite, const Offset(-2000, -2000));
      await tester.pump(const Duration(milliseconds: 100));
      check();
      tester.view.physicalSize = const Size(800, 360);
      await tester.pump(const Duration(milliseconds: 200));
      check();
      await tester.drag(sprite, const Offset(2000, 2000));
      await tester.pump(const Duration(milliseconds: 100));
      check();
      await tester.tap(sprite);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('companion-chat')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [const Size(640, 300), const Size(800, 300)]) {
    testWidgets(
      'Short landscape $size with system insets and large text remains usable',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
        tester.platformDispatcher.textScaleFactorTestValue = 1.8;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        SharedPreferences.setMockInitialValues({
          'companion_visible': true,
          'companion_x': 1.0,
          'companion_y': 1.0,
        });
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const channel = MethodChannel('vn.czn.viethoa/patcher');
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'bundledInfo') {
            return {'version': '1.6.5', 'version_code': 10605, 'changelog': ''};
          }
          return <String, dynamic>{};
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await tester.pumpWidget(const CznPatcherApp());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('floating-companion')), findsNothing);
        final primary = tester.getRect(
          find.byKey(const Key('landing-primary')),
        );
        for (final key in ['open-setup', 'open-updates', 'open-help']) {
          final action = find.byKey(Key(key));
          expect(action.hitTestable(), findsOneWidget);
          expect(primary.overlaps(tester.getRect(action)), false);
          expect(
            tester
                .getRect(action)
                .overlaps(tester.getRect(find.byTooltip('Cài đặt'))),
            false,
          );
        }
        expect(
          find.byKey(const Key('landing-primary')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('landing-primary')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('game-wordmark')), findsOneWidget);
        expect(
          tester.getRect(find.byKey(const Key('anniversary-background'))).size,
          size,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Comic links copy the actual error and open the supplied Dev profile',
    (tester) async {
      SharedPreferences.setMockInitialValues({'companion_visible': false});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? copied;
      final previousLauncher = UrlLauncherPlatform.instance;
      final launcher = FakeLauncher();
      UrlLauncherPlatform.instance = launcher;
      addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);
      messenger.setMockMethodCallHandler(
        const MethodChannel('vn.czn.viethoa/patcher'),
        (call) async {
          switch (call.method) {
            case 'status':
              return {
                'appVersion': '1.6.0',
                'appCode': 10600,
                'accessGranted': false,
              };
            case 'bundledInfo':
              return {
                'version': '1.4.2',
                'version_code': 10402,
                'changelog': '',
              };
            case 'lastOperation':
              return {
                'success': false,
                'error_code': 'TEST_STORAGE',
                'message': 'Lỗi kiểm tra',
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
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = call.arguments['text'] as String;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('vn.czn.viethoa/patcher'),
          null,
        );
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      await tester.pumpWidget(const CznPatcherApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-help')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('companion-chat')), findsOneWidget);
      final rich = tester.widget<RichText>(
        find
            .descendant(
              of: find.byKey(const Key('companion-chat')),
              matching: find.byType(RichText),
            )
            .first,
      );
      expect(
        rich.text.toPlainText(includePlaceholders: false),
        contains('Thuyền trưởng lại gặp lỗi rồi ư?'),
      );
      expect(companionMessage, endsWith('chăm sóc thôi~♥'));
      await tester.tap(find.byKey(const Key('copy-error-link')));
      await tester.pump();
      expect(jsonDecode(copied!)['error_code'], 'TEST_STORAGE');
      expect(find.text('Đã copy mã lỗi ♥'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dev-profile-link')));
      await tester.pump();
      expect(launcher.opened, 'https://www.facebook.com/datnguyen.kei/');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Tapping GIF opens chat at its retained position', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({'companion_visible': true});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('vn.czn.viethoa/patcher'),
      (call) async {
        if (call.method == 'bundledInfo') {
          return {'version': '1.4.2', 'version_code': 10402, 'changelog': ''};
        }
        return <String, dynamic>{};
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('vn.czn.viethoa/patcher'),
        null,
      ),
    );
    await tester.pumpWidget(const CznPatcherApp());
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester
          .getSemantics(find.bySemanticsLabel(RegExp('Nhân vật đồng hành')))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      true,
    );
    await tester.tap(find.byKey(const Key('floating-companion')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('companion-chat')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
