import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A floating sprite inside the app; coordinates survive resizing and reopening.
class CznCompanion extends StatefulWidget {
  const CznCompanion({
    super.key,
    required this.child,
    required this.visible,
    required this.onHide,
  });
  final Widget child;
  final bool visible;
  final VoidCallback onHide;

  @override
  State<CznCompanion> createState() => _CznCompanionState();
}

class _CznCompanionState extends State<CznCompanion> {
  Offset _position = const Offset(.96, .58);
  bool _dragged = false;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      if (!mounted || _dragged) return;
      final x = prefs.getDouble('companion_x') ?? .96;
      final y = prefs.getDouble('companion_y') ?? .58;
      setState(
        () => _position = Offset(
          x.isFinite ? x.clamp(0, 1) : .96,
          y.isFinite ? y.clamp(0, 1) : .58,
        ),
      );
    } catch (_) {
      // A missing preferences store must never prevent using the patcher.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setDouble('companion_x', _position.dx);
      await prefs.setDouble('companion_y', _position.dy);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final width = math.min(100.0, math.max(48.0, bounds.maxWidth - 16));
      final height = width * 336 / 320;
      final maxX = math.max(0.0, bounds.maxWidth - width - 16);
      final maxY = math.max(0.0, bounds.maxHeight - height - 16);
      return Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (widget.visible && bounds.maxHeight >= height + 16)
            Positioned(
              left: 8 + _position.dx * maxX,
              top: 8 + _position.dy * maxY,
              child: Semantics(
                label: 'Nhân vật đồng hành. Kéo để di chuyển, nhấn giữ để ẩn.',
                button: true,
                onLongPress: widget.onHide,
                child: GestureDetector(
                  key: const Key('floating-companion'),
                  behavior: HitTestBehavior.opaque,
                  onLongPress: widget.onHide,
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Kéo nhân vật để di chuyển. Nhấn giữ để ẩn; bật lại trong Cài đặt.',
                      ),
                    ),
                  ),
                  onPanUpdate: (event) {
                    _dragged = true;
                    setState(
                      () => _position = Offset(
                        maxX > 0
                            ? (_position.dx + event.delta.dx / maxX).clamp(0, 1)
                            : 0,
                        maxY > 0
                            ? (_position.dy + event.delta.dy / maxY).clamp(0, 1)
                            : 0,
                      ),
                    );
                  },
                  onPanEnd: (_) => unawaited(_save()),
                  onPanCancel: () => unawaited(_save()),
                  child: RepaintBoundary(
                    child: Image.asset(
                      MediaQuery.disableAnimationsOf(context)
                          ? 'assets/companion_still.png'
                          : 'assets/companion.gif',
                      width: width,
                      height: height,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
