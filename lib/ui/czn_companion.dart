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
    this.onTap,
    this.reservedTop = 0,
    this.dragRegion,
  });
  final Widget child;
  final bool visible;
  final VoidCallback onHide;
  final VoidCallback? onTap;
  final double reservedTop;
  final Rect Function(Size viewport)? dragRegion;

  @override
  State<CznCompanion> createState() => _CznCompanionState();
}

class _CznCompanionState extends State<CznCompanion> {
  Offset _position = const Offset(.92, 0);
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
      final x = prefs.getDouble('companion_x') ?? .92;
      final y = prefs.getDouble('companion_y') ?? 0;
      setState(
        () => _position = Offset(
          x.isFinite ? x.clamp(0, 1) : .92,
          y.isFinite ? y.clamp(0, 1) : 0,
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

  void _tap() {
    if (widget.onTap != null) {
      widget.onTap!();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kéo nhân vật để di chuyển. Nhấn giữ để ẩn; bật lại trong Cài đặt.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final width = math.min(78.0, math.max(48.0, bounds.maxWidth - 16));
      final height = width;
      final viewport = Size(bounds.maxWidth, bounds.maxHeight);
      final region =
          (widget.dragRegion?.call(viewport) ??
                  Rect.fromLTRB(
                    8,
                    8 + widget.reservedTop,
                    bounds.maxWidth - 8,
                    bounds.maxHeight - 8,
                  ))
              .intersect(Offset.zero & viewport);
      final fits = region.width >= width && region.height >= height;
      final maxX = math.max(0.0, region.width - width);
      final maxY = math.max(0.0, region.height - height);
      return Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (widget.visible && fits)
            Positioned(
              left: region.left + _position.dx * maxX,
              top: region.top + _position.dy * maxY,
              child: Semantics(
                container: true,
                excludeSemantics: true,
                onTap: _tap,
                label: 'Nhân vật đồng hành. Chạm để trò chuyện, kéo để di chuyển, nhấn giữ để ẩn.',
                button: true,
                onLongPress: widget.onHide,
                child: GestureDetector(
                  key: const Key('floating-companion'),
                  behavior: HitTestBehavior.opaque,
                  onLongPress: widget.onHide,
                  onTap: _tap,
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
