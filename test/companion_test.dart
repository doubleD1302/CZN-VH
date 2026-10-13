import 'package:czn_patcher/ui/czn_companion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Widget screen({bool visible = true, VoidCallback? onHide}) => MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: CznCompanion(
          visible: visible,
          onHide: onHide ?? () {},
          child: const ColoredBox(color: Colors.black),
        ),
      ),
    ),
  );

  testWidgets('Dragging saves position and reopening restores it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'companion_x': .92,
      'companion_y': .5,
    });
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    final sprite = find.byKey(const Key('floating-companion'));
    final before = tester.getTopLeft(sprite);
    await tester.drag(sprite, const Offset(-170, -110));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(sprite);
    expect(after.dx, lessThan(before.dx));
    expect(after.dy, lessThan(before.dy));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('companion_x'), isNotNull);
    expect(prefs.getDouble('companion_y'), isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sprite), after);
  });

  testWidgets('Dragging and rotating keep the sprite inside the viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    final sprite = find.byKey(const Key('floating-companion'));
    await tester.drag(sprite, const Offset(2000, 2000));
    await tester.pumpAndSettle();
    expect(tester.getRect(sprite).right, lessThanOrEqualTo(312));
    expect(tester.getRect(sprite).bottom, lessThanOrEqualTo(632));
    tester.view.physicalSize = const Size(640, 320);
    await tester.pumpAndSettle();
    expect(tester.getRect(sprite).right, lessThanOrEqualTo(632));
    expect(tester.getRect(sprite).bottom, lessThanOrEqualTo(312));
    await tester.drag(sprite, const Offset(-2000, -2000));
    await tester.pumpAndSettle();
    expect(tester.getRect(sprite).left, greaterThanOrEqualTo(8));
    expect(tester.getRect(sprite).top, greaterThanOrEqualTo(8));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Long press hides the sprite and reduced motion uses the still frame',
    (tester) async {
      var hidden = false;
      await tester.pumpWidget(screen(onHide: () => hidden = true));
      await tester.pumpAndSettle();
      expect(
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName,
        'assets/companion_still.png',
      );
      await tester.longPress(find.byKey(const Key('floating-companion')));
      expect(hidden, true);
      await tester.pumpWidget(screen(visible: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('floating-companion')), findsNothing);
    },
  );
}
