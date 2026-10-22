import 'dart:io';
import 'dart:ui' as ui;

import 'package:czn_patcher/ui/donate_screen.dart';
import 'package:czn_patcher/ui/windows_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final emptyMockClient = MockClient((request) async {
    return http.Response(
      '{"schema":1,"supporters":[]}',
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  setUpAll(() async {
    for (final pair in [
      ['CznSans', 'assets/fonts/NotoSans.ttf'],
      ['CznSerif', 'assets/fonts/NotoSerif.ttf'],
      ['MaterialIcons', 'fonts/MaterialIcons-Regular.otf'],
    ]) {
      await (FontLoader(pair[0])..addFont(rootBundle.load(pair[1]))).load();
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      DonationService.cacheKeyData: '{"schema":1,"supporters":[]}',
      DonationService.cacheKeyTime: DateTime.now().millisecondsSinceEpoch,
    });
  });

  Future<void> load(
    WidgetTester tester,
    Size size, {
    double scale = 1,
    http.Client? client,
  }) async {
    await tester.runAsync(
      () => rootBundle.loadString('assets/donate_supporters.json'),
    );
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: windowsLauncherTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const Key('donate-render'),
          child: DonateScreen(client: client ?? emptyMockClient),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final context = tester.element(find.byType(DonateScreen));
      await Future.wait([
        precacheImage(const AssetImage(DonationDetails.bankQr), context),
        precacheImage(const AssetImage(DonationDetails.momoQr), context),
        precacheImage(const AssetImage('assets/companion_still.png'), context),
      ]);
    });
    await tester.pumpAndSettle();
  }

  Future<void> pumpDonate(
    WidgetTester tester, {
    http.Client? client,
    Size size = const Size(1280, 1100),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: windowsLauncherTheme,
        home: DonateScreen(
          client: client,
          retryDelay: Duration.zero,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('donate-render')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(
        '../data/tasks/DONATE_INTEGRATION_20261021/screenshots',
      )..createSync(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  test(
    'Donor data accepts an empty real list and rejects malformed rows',
    () async {
      expect(
        DonationSupporter.decode(
          await rootBundle.loadString('assets/donate_supporters.json'),
        ),
        isEmpty,
      );
      expect(
        () => DonationSupporter.decode('{"schema":2,"supporters":[]}'),
        throwsFormatException,
      );
      expect(
        () => DonationSupporter.decode(
          '{"schema":1,"supporters":[{"display_name":""}]}',
        ),
        throwsFormatException,
      );
      final entries = DonationSupporter.decode(
        '{"schema":1,"supporters":[{"display_name":"Ẩn danh"}]}',
      );
      expect(entries.single.name, 'Ẩn danh');
      expect(entries.single.message, contains('Cảm ơn'));
    },
  );

  testWidgets('Bank and MoMo show the correct original asset and recipient', (
    tester,
  ) async {
    await load(tester, const Size(1280, 1100));
    expect(find.byKey(const Key('donate-bank-qr')), findsOneWidget);
    expect(find.byKey(const Key('donate-momo-qr')), findsNothing);
    expect(find.text(DonationDetails.holder), findsOneWidget);
    expect(find.text(DonationDetails.formattedAccount), findsOneWidget);
    expect(find.text('DoubleD1302'), findsOneWidget);
    expect(find.text('Chaos Zero Nightmare'), findsOneWidget);
    await screenshot(tester, 'flutter-desktop-bank');
    expect(find.byKey(const Key('donate-empty-thanks')), findsOneWidget);
    expect(find.textContaining('MINH HỌA'), findsNothing);
    await tester.tap(find.text('MoMo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('donate-momo-qr')), findsOneWidget);
    expect(find.byKey(const Key('donate-bank-qr')), findsNothing);
    expect(find.text(DonationDetails.maskedWallet), findsOneWidget);
    expect(find.byKey(const Key('donate-copy-account')), findsNothing);
    await screenshot(tester, 'flutter-desktop-momo');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Copy sends exact bank and Vietnamese note; it never adds a donor',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await load(tester, const Size(1280, 1100));
      await tester.tap(find.byKey(const Key('donate-copy-account')));
      await tester.pump();
      expect(copied, '19075904603016');
      await tester.tap(find.byKey(const Key('donate-copy-note')));
      await tester.pump();
      expect(find.textContaining('Nhập tên / biệt danh'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('donate-name')),
        '  Nguyễn  Ánh <b>  ',
      );
      await tester.tap(find.byKey(const Key('donate-copy-note')));
      await tester.pumpAndSettle();
      expect(copied, 'Chaos Zero Nightmare - Nguyễn Ánh <b>');
      expect(find.byKey(const Key('donate-empty-thanks')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Unavailable clipboard keeps exact account selectable without success',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'DENIED');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await load(tester, const Size(390, 844));
      await tester.ensureVisible(find.byKey(const Key('donate-copy-account')));
      await tester.tap(find.byKey(const Key('donate-copy-account')));
      await tester.pumpAndSettle();
      expect(find.text('Sao chép thủ công'), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const Key('donate-copy-fallback')),
            )
            .data,
        DonationDetails.account,
      );
      expect(find.text('Đã sao chép số tài khoản Techcombank.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(800, 360),
  ]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('Donation reflows at $size text scale $scale', (
        tester,
      ) async {
        await load(tester, size, scale: scale);
        expect(find.byTooltip('Về trang chính'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (scale == 1 && size.width == 390) {
          await screenshot(tester, 'flutter-phone-bank');
        }
        await tester.ensureVisible(find.byKey(const Key('donate-copy-note')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const Key('donate-empty-thanks')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (scale == 1 && size.width == 390) {
          await screenshot(tester, 'flutter-phone-thanks');
        }
      });
    }
  }

  // =========================================================================
  // REGRESSION TEST
  // =========================================================================
  testWidgets(
    'Regression: Network error without cache must NEVER silently convert to empty thanks',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final failingClient = MockClient((request) async {
        throw http.ClientException('Simulated network timeout');
      });

      await pumpDonate(tester, client: failingClient);

      expect(find.byKey(const Key('donate-error-view')), findsOneWidget);
      expect(find.byKey(const Key('donate-empty-thanks')), findsNothing);
      expect(find.byKey(const Key('donate-retry-button')), findsOneWidget);
      expect(
        find.textContaining('Không thể tải danh sách người ủng hộ'),
        findsOneWidget,
      );
    },
  );

  // =========================================================================
  // DONATION SERVICE UNIT TESTS
  // =========================================================================
  group('DonationService Unit Tests', () {
    test(
      '200 OK valid JSON with Icarus returns online status and caches data',
      () async {
        SharedPreferences.setMockInitialValues({});
        final client = MockClient((request) async {
          return http.Response(
            '{"schema":1,"supporters":[{"display_name":"Icarus","message":"Cảm ơn bạn rất nhiều!"}]}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final result = await DonationService.fetch(client: client);
        expect(result.status, DonationStatus.online);
        expect(result.supporters.length, 1);
        expect(result.supporters.first.name, 'Icarus');

        final cached = await DonationService.loadCachedSupporters();
        expect(cached, isNotNull);
        expect(cached!.first.name, 'Icarus');
      },
    );

    test(
      '200 OK valid empty list returns empty status and overwrites previous cache',
      () async {
        SharedPreferences.setMockInitialValues({
          DonationService.cacheKeyData:
              '{"schema":1,"supporters":[{"display_name":"OldSupporter","message":"hi"}]}',
          DonationService.cacheKeyTime: 1000,
        });

        final client = MockClient((request) async {
          return http.Response('{"schema":1,"supporters":[]}', 200);
        });

        final result = await DonationService.fetch(client: client);
        expect(result.status, DonationStatus.empty);
        expect(result.supporters, isEmpty);

        final cached = await DonationService.loadCachedSupporters();
        expect(cached, isEmpty);
      },
    );

    test('302 redirect is followed and returns final response', () async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((request) async {
        if (request.url.host == 'script.google.com') {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://script.googleusercontent.com/echo'},
          );
        }
        if (request.url.host == 'script.googleusercontent.com') {
          return http.Response(
            '{"schema":1,"supporters":[{"display_name":"Icarus","message":"Via redirect"}]}',
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final result = await DonationService.fetch(client: client);
      expect(result.status, DonationStatus.online);
      expect(result.supporters.first.name, 'Icarus');
    });

    test(
      'HTTP 403 client error does not retry and fails over to cache if available',
      () async {
        var callCount = 0;
        SharedPreferences.setMockInitialValues({
          DonationService.cacheKeyData:
              '{"schema":1,"supporters":[{"display_name":"CachedHero","message":"Saved"}]}',
          DonationService.cacheKeyTime: 12345,
        });

        final client = MockClient((request) async {
          callCount++;
          return http.Response('Forbidden', 403);
        });

        final result = await DonationService.fetch(client: client);
        expect(callCount, 1);
        expect(result.status, DonationStatus.cached);
        expect(result.supporters.first.name, 'CachedHero');
      },
    );

    test('Corrupted cache is safely ignored without crashing', () async {
      SharedPreferences.setMockInitialValues({
        DonationService.cacheKeyData: 'INVALID_JSON_CORRUPTED',
        DonationService.cacheKeyTime: 12345,
      });

      final cached = await DonationService.loadCachedSupporters();
      expect(cached, isNull);
    });
  });

  // =========================================================================
  // DONATE SCREEN UI STATE TESTS
  // =========================================================================
  group('DonateScreen UI State Tests', () {
    testWidgets('Online state displays supporter list with Icarus', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((request) async {
        return http.Response(
          '{"schema":1,"supporters":[{"display_name":"Icarus","message":"Cảm ơn bạn rất nhiều!"}]}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      await pumpDonate(tester, client: client);

      expect(find.text('Icarus'), findsOneWidget);
      expect(find.text('Cảm ơn bạn rất nhiều!'), findsOneWidget);
      expect(find.byKey(const Key('donate-empty-thanks')), findsNothing);
      expect(find.byKey(const Key('donate-error-view')), findsNothing);
      expect(find.byKey(const Key('donate-cached-banner')), findsNothing);
    });

    testWidgets('Cached state displays cached banner and supporter list', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        DonationService.cacheKeyData:
            '{"schema":1,"supporters":[{"display_name":"OfflineDonor","message":"Vẫn nhớ bạn"}]}',
        DonationService.cacheKeyTime: 99999,
      });
      final failingClient = MockClient((request) async {
        throw http.ClientException('No internet');
      });

      await pumpDonate(tester, client: failingClient);

      expect(find.byKey(const Key('donate-cached-banner')), findsOneWidget);
      expect(find.text('OfflineDonor'), findsOneWidget);
      expect(find.text('Vẫn nhớ bạn'), findsOneWidget);
      expect(find.byKey(const Key('donate-error-view')), findsNothing);
    });

    testWidgets('Tapping retry button re-triggers fetch', (tester) async {
      SharedPreferences.setMockInitialValues({});
      var attemptCount = 0;
      final mockClient = MockClient((request) async {
        attemptCount++;
        if (attemptCount <= 2) {
          throw http.ClientException('Error $attemptCount');
        }
        return http.Response(
          '{"schema":1,"supporters":[{"display_name":"Icarus","message":"Recovered!"}]}',
          200,
        );
      });

      await pumpDonate(tester, client: mockClient);

      expect(find.byKey(const Key('donate-error-view')), findsOneWidget);
      expect(find.byKey(const Key('donate-retry-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('donate-retry-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('donate-error-view')), findsNothing);
      expect(find.text('Icarus'), findsOneWidget);
      expect(find.text('Recovered!'), findsOneWidget);
    });

    testWidgets(
      'Rapid refresh clicks are guarded against duplicate in-flight calls',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        var callCount = 0;
        final slowClient = MockClient((request) async {
          callCount++;
          await Future.delayed(const Duration(milliseconds: 50));
          return http.Response(
            '{"schema":1,"supporters":[{"display_name":"Icarus","message":"Great"}]}',
            200,
          );
        });

        await pumpDonate(tester, client: slowClient);

        final initialCalls = callCount;
        await tester.tap(find.byKey(const Key('donate-refresh-supporters')));
        await tester.tap(find.byKey(const Key('donate-refresh-supporters')));
        await tester.pumpAndSettle();

        expect(callCount, initialCalls + 1);
      },
    );
  });
}
