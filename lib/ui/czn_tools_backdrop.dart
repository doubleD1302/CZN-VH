import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class CznToolsBackdrop extends StatelessWidget {
  const CznToolsBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: ClipRect(
            child: BackdropFilter(
              key: const Key('tools-blurred-background'),
              filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x75101420), Color(0x7D23101A)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      child,
    ],
  );
}
