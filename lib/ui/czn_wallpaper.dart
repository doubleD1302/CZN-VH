import 'package:flutter/material.dart';

/// Shared behind Navigator so every route and dialog keeps the wallpaper.
class CznWallpaper extends StatelessWidget {
  const CznWallpaper({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          bounds.maxWidth > bounds.maxHeight
              ? 'assets/anniversary_landscape.jpg'
              : 'assets/anniversary_portrait.png',
          key: const Key('anniversary-background'),
          fit: BoxFit.cover,
          alignment: bounds.maxWidth > bounds.maxHeight
              ? Alignment.bottomCenter
              : Alignment.center,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66101623),
                  Colors.transparent,
                  Colors.transparent,
                  Color(0x80190915),
                ],
                stops: [0, .17, .65, 1],
              ),
            ),
          ),
        ),
        child,
      ],
    ),
  );
}
