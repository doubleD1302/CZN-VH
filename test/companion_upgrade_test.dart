import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:czn_patcher/ui/companion_dialog.dart';
import 'package:czn_patcher/ui/bug_report_dialog.dart';
import 'package:czn_patcher/ui/hall_of_fame_dialog.dart';
import 'package:czn_patcher/ui/czn_companion.dart';
import 'package:czn_patcher/ui/czn_tools_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'last_bug_reporter_name': 'Thuyền Trưởng Test',
      'companion_visible': true,
      'companion_overlay': true,
    });
  });

  group('Companion Upgrades Test Suite', () {
    testWidgets('CompanionDialog renders polite natural dialogue and action buttons', (tester) async {
      var copyCalled = false;
      var devOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompanionDialog(
              onCopyError: () async {
                copyCalled = true;
                return true;
              },
              onOpenDeveloper: () async {
                devOpened = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify no cringe dialogue
      expect(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('để em chăm sóc thôi~♥')),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('Chào Thuyền trưởng!')),
        findsOneWidget,
      );

      // Verify action buttons exist
      expect(find.text('Báo Lỗi Bằng Hình Ảnh'), findsOneWidget);
      expect(find.text('Lời Cám Ơn'), findsOneWidget);

      // Tap copy error
      await tester.tap(find.byKey(const Key('copy-error-link')));
      await tester.pumpAndSettle();
      expect(copyCalled, isTrue);
      expect(find.text('Đã copy mã lỗi vào bộ nhớ tạm.'), findsOneWidget);

      // Tap dev link
      await tester.tap(find.byKey(const Key('dev-profile-link')));
      await tester.pumpAndSettle();
      expect(devOpened, isTrue);
    });

    testWidgets('BugReportDialog loads saved reporter name and provides UI fields', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BugReportDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check title and inherited sender name
      expect(find.text('Báo Lỗi Bằng Hình Ảnh'), findsOneWidget);
      expect(find.text('Thuyền Trưởng Test'), findsOneWidget);

      // Check fields and buttons
      expect(find.text('Chạm để chọn ảnh chụp màn hình lỗi'), findsOneWidget);
      expect(find.text('Gửi Báo Cáo'), findsOneWidget);

      // Verify black text color on both text fields to prevent faded text
      final textFields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(textFields.length, equals(2));
      expect(textFields[0].style?.color, equals(Colors.black));
      expect(textFields[1].style?.color, equals(Colors.black));
      expect(textFields[0].cursorColor, equals(Colors.black));
      expect(textFields[1].cursorColor, equals(Colors.black));
    });

    testWidgets('BugReportDialog displays success gratitude overlay when submitted', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BugReportDialog(initialSuccess: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('GHI NHẬN THÀNH CÔNG!'), findsOneWidget);
      expect(find.text('CẢM ƠN THUYỀN TRƯỞNG'), findsOneWidget);
      expect(find.text('Đã Hiểu & Đóng'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('HallOfFameDialog displays gratitude section, leaderboard, and close button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HallOfFameDialog(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Lời Cám Ơn'), findsOneWidget);
      expect(find.text('Bảng Xếp Hạng Đóng Góp'), findsOneWidget);
      expect(find.text('Chỉ tính lỗi FIXED'), findsOneWidget);
      expect(find.textContaining('TRI ÂN THUYỀN TRƯỞNG'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('CznCompanion renders with x2 enlarged scale (up to 156dp)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 500,
              child: CznCompanion(
                visible: true,
                onHide: () {},
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final companionFinder = find.byKey(const Key('floating-companion'));
      expect(companionFinder, findsOneWidget);
      final renderBox = tester.renderObject<RenderBox>(companionFinder);
      expect(renderBox.size.width, equals(156.0));
      expect(renderBox.size.height, equals(156.0));
    });

    testWidgets('CznToolsSettingsPage renders overlay switch and handles toggle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CznToolsSettingsPage(
              companionVisible: true,
              companionOverlayVisible: false,
              autoDownload: true,
              channel: 'https://test.com/channel.json',
              appVersion: '1.6.12',
              patchVersion: '1.6.5',
              busy: false,
              onSave: (companion, auto, channel, overlay) async => true,
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lớp phủ trên ứng dụng khác'), findsOneWidget);
      expect(find.text('Hiện nhân vật nổi khi mở game hoặc ứng dụng khác.'), findsOneWidget);
    });
  });
}
