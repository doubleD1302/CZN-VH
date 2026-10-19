
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:czn_patcher/ui/czn_tools_preferences.dart";
import "package:czn_patcher/services/notice_policy.dart";

void main() {
  testWidgets("Notice page renders and taps markdown hyperlink", (tester) async {
    const notice = CommunityNotice(
      "test-id",
      "Tiêu đề test",
      "Vui lòng [bấm vào đây](https://github.com/doubleD1302/CZN-VH/releases) để cập nhật",
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CznToolsNoticePage(
          notice: notice,
          appVersion: "1.8.1",
          busy: false,
          onDismiss: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text("bấm vào đây"), findsOneWidget);
    expect(find.text("Tiêu đề test"), findsOneWidget);
  });

  testWidgets("Notice page renders and taps parenthesis hyperlink", (tester) async {
    const notice = CommunityNotice(
      "test-id-2",
      "Tiêu đề 2",
      "Vui lòng bấm vào đây (https://github.com/doubleD1302/CZN-VH/releases) để cập nhật",
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CznToolsNoticePage(
          notice: notice,
          appVersion: "1.8.1",
          busy: false,
          onDismiss: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text("bấm vào đây"), findsOneWidget);
  });
}
