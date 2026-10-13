import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'czn_glass.dart';

enum CznToolsTab { setup, updates, notice, settings }

enum CznToolsGlyph16 {
  key,
  update,
  bell,
  gear,
  heart,
  wifi,
  layers,
  folder,
  install,
  package,
  translation,
  chat,
  photo,
  download,
  back,
  restore,
}

enum CznToolsText10 {
  setupTitle,
  updateTitle,
  noticeTitle,
  settingsTitle,
  install,
  checkUpdate,
  saveSettings,
  dismiss,
  snooze,
  restore,
}

abstract final class CznToolsColors {
  static const ivory = Color(0xFFFFEAD0);
  static const gold = Color(0xFFF2D09C);
  static const muted = Color(0xFFC4C2CA);
  static const panel = Color(0xB61A1D2D);
  static const crimson = Color(0xFF6A101C);
}

/// Shared shell for the four approved pages. The wallpaper/backdrop remains
/// outside this scaffold so both its glass panels and its footer are transparent.
class CznToolsScaffold extends StatelessWidget {
  const CznToolsScaffold({
    super.key,
    required this.activeTab,
    required this.title,
    required this.subtitle,
    required this.appVersion,
    required this.onTabChanged,
    required this.onBack,
    required this.child,
    this.navigationEnabled = true,
    this.headerTail,
  });

  final CznToolsTab activeTab;
  final String title;
  final String subtitle;
  final String appVersion;
  final ValueChanged<CznToolsTab> onTabChanged;
  final VoidCallback onBack;
  final Widget child;
  final bool navigationEnabled;
  final Widget? headerTail;

  @override
  Widget build(BuildContext context) {
    final inherited = Theme.of(context);
    return Theme(
      data: inherited.copyWith(
        textTheme: inherited.textTheme.apply(
          fontFamily: 'CznSans',
          bodyColor: CznToolsColors.ivory,
          displayColor: CznToolsColors.ivory,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 560;
              final superCompact = constraints.maxHeight < 360;
              final landscape = constraints.maxWidth > constraints.maxHeight;
              final horizontal = compact ? 14.0 : 22.0;
              return DefaultTextStyle.merge(
                style: const TextStyle(
                  fontFamily: 'CznSans',
                  color: CznToolsColors.ivory,
                  height: 1.35,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: landscape ? 820 : 620,
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: horizontal),
                          child: SizedBox(
                            height: compact ? 46 : 78,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: compact ? 136 : 164,
                                  height: compact ? 45 : 72,
                                  child: const CznGameLogo(
                                    showVietnamese: false,
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: IconButton(
                                    tooltip: 'Về trang chính',
                                    onPressed: navigationEnabled
                                        ? onBack
                                        : null,
                                    icon: const CznToolsIcon(
                                      CznToolsGlyph16.back,
                                      size: 25,
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0x70201928),
                                      border: Border.all(
                                        color: CznToolsColors.gold.withValues(
                                          alpha: .7,
                                        ),
                                        width: .7,
                                      ),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Text(
                                      'v$appVersion',
                                      style: const TextStyle(
                                        fontFamily: 'CznSans',
                                        fontSize: 11,
                                        color: CznToolsColors.muted,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!superCompact) ...[
                          SizedBox(height: compact ? 0 : 17),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontal,
                            ),
                            child: Semantics(
                              header: true,
                              child: CznToolsLabel(
                                CznToolsText10.values[activeTab.index],
                                semanticsLabel: title,
                                height: compact ? 34 : 54,
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: constraints.maxWidth * .16,
                            ),
                            child: CznToolsSeparator(height: compact ? 8 : 13),
                          ),
                          Text(
                            subtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'CznSans',
                              fontSize: compact ? 13 : 16,
                              color: CznToolsColors.muted,
                            ),
                          ),
                          ?headerTail,
                        ] else
                          Semantics(
                            header: true,
                            label: title,
                            child: const SizedBox.shrink(),
                          ),
                        SizedBox(height: superCompact ? 4 : (compact ? 8 : 16)),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontal,
                            ),
                            child: child,
                          ),
                        ),
                        _ToolsNavigation(
                          selected: activeTab,
                          compact: compact,
                          superCompact: superCompact,
                          enabled: navigationEnabled,
                          onChanged: onTabChanged,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ToolsNavigation extends StatelessWidget {
  const _ToolsNavigation({
    required this.selected,
    required this.compact,
    required this.superCompact,
    required this.enabled,
    required this.onChanged,
  });

  final CznToolsTab selected;
  final bool compact;
  final bool superCompact;
  final bool enabled;
  final ValueChanged<CznToolsTab> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['Thiết lập', 'Cập nhật', 'Thông báo', 'Cài đặt'];
    const glyphs = [
      CznToolsGlyph16.key,
      CznToolsGlyph16.update,
      CznToolsGlyph16.bell,
      CznToolsGlyph16.gear,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        superCompact ? 2 : (compact ? 4 : 14),
        12,
        superCompact ? 2 : (compact ? 3 : 8),
      ),
      child: Row(
        children: [
          for (final tab in CznToolsTab.values)
            Expanded(
              child: Semantics(
                container: true,
                button: true,
                selected: selected == tab,
                enabled: enabled,
                label: labels[tab.index],
                onTap: enabled ? () => onChanged(tab) : null,
                excludeSemantics: true,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: enabled ? () => onChanged(tab) : null,
                    borderRadius: BorderRadius.circular(30),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: superCompact ? 3 : 5,
                      ),
                      child: Opacity(
                        opacity: enabled ? 1 : .5,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CznToolsDecoratedRing(
                              size: superCompact ? 28 : (compact ? 36 : 51),
                              glyph: glyphs[tab.index],
                              selected: selected == tab,
                            ),
                            SizedBox(height: superCompact ? 3 : 5),
                            SizedBox(
                              height: superCompact ? 13 : null,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  labels[tab.index],
                                  style: TextStyle(
                                    fontFamily: 'CznSans',
                                    fontSize: superCompact
                                        ? 10
                                        : (compact ? 11 : 13),
                                    fontWeight: selected == tab
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: selected == tab
                                        ? CznToolsColors.ivory
                                        : CznToolsColors.muted,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 5,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CznToolsPanel extends StatelessWidget {
  const CznToolsPanel({
    super.key,
    required this.child,
    this.variant = 0,
    this.padding = const EdgeInsets.all(18),
    this.accent = false,
  });
  final Widget child;
  final int variant;
  final EdgeInsetsGeometry padding;
  final bool accent;

  int get _safeVariant => variant < 0 ? 0 : (variant > 3 ? 3 : variant);

  @override
  Widget build(BuildContext context) => _AtlasArt(
    group: 'panels',
    index: _safeVariant,
    namedKey: const ['setup', 'update', 'notice', 'settings'][_safeVariant],
    mode: _ArtMode.panel,
    foregroundPainter: _PanelFramePainter(_safeVariant),
    fallback: BoxDecoration(
      borderRadius: BorderRadius.circular(15),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xC1192030), Color(0xAA241C2A)],
      ),
      border: Border.all(color: CznToolsColors.gold, width: .8),
      boxShadow: accent
          ? const [BoxShadow(color: Color(0x406A101C), blurRadius: 14)]
          : null,
    ),
    child: Padding(padding: padding, child: child),
  );
}

class CznToolsButton extends StatelessWidget {
  const CznToolsButton({
    super.key,
    required this.label,
    this.onPressed,
    this.primary = false,
    this.textArt,
    this.icon,
    this.compact = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final CznToolsText10? textArt;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onPressed != null,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: Opacity(
      opacity: onPressed == null ? .48 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const StadiumBorder(),
          splashColor: CznToolsColors.gold.withValues(alpha: .13),
          child: _AtlasArt(
            group: 'buttons',
            index: primary ? 1 : 0,
            namedKey: primary ? 'primary' : 'secondary',
            mode: _ArtMode.button,
            foregroundPainter: _CapsuleFramePainter(
              primary: primary,
              centerTips: textArt == CznToolsText10.checkUpdate,
            ),
            fallback: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: primary
                    ? const [Color(0xE4871823), Color(0xD33B0711)]
                    : const [Color(0xB3222636), Color(0xA11A1B2A)],
              ),
              border: Border.all(color: CznToolsColors.gold, width: 1.1),
              boxShadow: primary
                  ? const [BoxShadow(color: Color(0x509F241C), blurRadius: 12)]
                  : null,
            ),
            child: SizedBox(
              height: compact ? 44 : (primary ? 57 : 51),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 13 : 21),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      _buttonIcon(icon!),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: textArt == null
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'CznDisplay',
                                  fontSize: compact ? 16 : 19,
                                  color: CznToolsColors.ivory,
                                  fontWeight: FontWeight.w500,
                                  shadows: const [
                                    Shadow(color: Colors.black, blurRadius: 4),
                                  ],
                                ),
                              ),
                            )
                          : CznToolsLabel(
                              textArt!,
                              semanticsLabel: label,
                              height: compact ? 23 : 27,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buttonIcon(IconData value) {
    final glyph = {
      Icons.key: CznToolsGlyph16.key,
      Icons.key_rounded: CznToolsGlyph16.key,
      Icons.sync: CznToolsGlyph16.update,
      Icons.refresh: CznToolsGlyph16.update,
      Icons.notifications_none: CznToolsGlyph16.bell,
      Icons.settings: CznToolsGlyph16.gear,
      Icons.folder_open: CznToolsGlyph16.folder,
      Icons.download: CznToolsGlyph16.download,
      Icons.download_done: CznToolsGlyph16.install,
      Icons.restore: CznToolsGlyph16.restore,
      Icons.content_copy: CznToolsGlyph16.chat,
    }[value];
    return glyph == null
        ? Icon(value, color: CznToolsColors.gold, size: 21)
        : CznToolsIcon(glyph, size: 21);
  }
}

class CznToolsIcon extends StatelessWidget {
  const CznToolsIcon(
    this.glyph, {
    super.key,
    this.size = 30,
    this.color = CznToolsColors.gold,
  });
  final CznToolsGlyph16 glyph;
  final double size;
  final Color color;

  static const _fallbacks = [
    Icons.key_rounded,
    Icons.sync_rounded,
    Icons.notifications_none_rounded,
    Icons.settings_outlined,
    Icons.favorite_border_rounded,
    Icons.wifi_rounded,
    Icons.layers_outlined,
    Icons.folder_open_rounded,
    Icons.auto_awesome_outlined,
    Icons.inventory_2_outlined,
    Icons.translate_rounded,
    Icons.chat_bubble_outline_rounded,
    Icons.photo_outlined,
    Icons.file_download_outlined,
    Icons.chevron_left_rounded,
    Icons.restore_rounded,
  ];

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: _AtlasArt(
        group: 'icons',
        index: glyph.index,
        namedKey: glyph.name,
        fallbackWidget: Icon(_fallbacks[glyph.index], size: size, color: color),
      ),
    ),
  );
}

/// Text from the approved raster typography, with a real accessibility label.
/// Tight source bounds come from the atlas; no pixels or files are rewritten.
class CznToolsLabel extends StatelessWidget {
  const CznToolsLabel(
    this.textArt, {
    super.key,
    required this.semanticsLabel,
    this.height = 40,
  });
  final CznToolsText10 textArt;
  final String semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    excludeSemantics: true,
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: _AtlasArt(
        group: 'type',
        index: textArt.index,
        namedKey: textArt.name,
        fallbackWidget: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            semanticsLabel,
            style: TextStyle(
              fontFamily: 'CznDisplay',
              fontSize: height * .88,
              color: CznToolsColors.ivory,
              height: 1,
              fontWeight: FontWeight.w500,
              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ),
      ),
    ),
  );
}

class CznToolsDecoratedRing extends StatelessWidget {
  const CznToolsDecoratedRing({
    super.key,
    this.child,
    this.glyph,
    this.selected = false,
    this.size = 54,
  });
  final Widget? child;
  final CznToolsGlyph16? glyph;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: _AtlasArt(
      group: 'rings',
      index: selected ? 1 : 0,
      namedKey: selected ? 'selected' : 'normal',
      foregroundPainter: _RingFramePainter(selected),
      fallback: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? const Color(0xAD530B15) : const Color(0x8B161927),
        border: Border.all(
          color: selected ? CznToolsColors.gold : const Color(0xBBDDCDB9),
          width: selected ? 1.6 : .8,
        ),
        boxShadow: selected
            ? const [BoxShadow(color: Color(0x709C261C), blurRadius: 12)]
            : null,
      ),
      child: Center(
        child:
            child ??
            (glyph == null
                ? const SizedBox.shrink()
                : CznToolsIcon(glyph!, size: size * .45)),
      ),
    ),
  );
}

class CznToolsSeparator extends StatelessWidget {
  const CznToolsSeparator({super.key, this.height = 15});
  final double height;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SeparatorPainter()),
    ),
  );
}

/// A line leading from the wallpaper toward a label, with its ornament at the
/// label-facing end. Unlike a central separator, both halves remain visible.
class CznToolsSideLine extends StatelessWidget {
  const CznToolsSideLine({
    super.key,
    this.height = 14,
    this.pointingRight = true,
  });
  final double height;
  final bool pointingRight;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SideLinePainter(pointingRight)),
    ),
  );
}

class _SeparatorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final cy = size.height / 2;
    final cx = size.width / 2;
    final diamond = math.min(size.height * .29, 5.0);
    final linePaint = Paint()
      ..strokeWidth = .9
      ..shader = const LinearGradient(
        colors: [Color(0x18F2D09C), CznToolsColors.gold, Color(0x18F2D09C)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawLine(Offset(0, cy), Offset(cx - diamond - 5, cy), linePaint);
    canvas.drawLine(
      Offset(cx + diamond + 5, cy),
      Offset(size.width, cy),
      linePaint,
    );
    final path = Path()
      ..moveTo(cx, cy - diamond)
      ..lineTo(cx + diamond, cy)
      ..lineTo(cx, cy + diamond)
      ..lineTo(cx - diamond, cy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = CznToolsColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.05,
    );
    _drawDiamond(canvas, Offset(cx - diamond - 5.5, cy), 1.5);
    _drawDiamond(canvas, Offset(cx + diamond + 5.5, cy), 1.5);
  }

  @override
  bool shouldRepaint(_SeparatorPainter oldDelegate) => false;
}

class _SideLinePainter extends CustomPainter {
  _SideLinePainter(this.pointingRight);
  final bool pointingRight;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final cy = size.height / 2;
    final end = pointingRight ? size.width - 3 : 3.0;
    final start = pointingRight ? 0.0 : size.width;
    final finish = pointingRight ? end - 5 : end + 5;
    final paint = Paint()
      ..strokeWidth = .9
      ..shader = LinearGradient(
        colors: pointingRight
            ? const [Color(0x08F2D09C), CznToolsColors.gold]
            : const [CznToolsColors.gold, Color(0x08F2D09C)],
      ).createShader(Offset.zero & size);
    canvas.drawLine(Offset(start, cy), Offset(finish, cy), paint);
    _drawDiamond(canvas, Offset(end, cy), 2.3);
    _drawDiamond(
      canvas,
      Offset(pointingRight ? end - 7 : end + 7, cy),
      1.25,
      fill: true,
    );
  }

  @override
  bool shouldRepaint(_SideLinePainter oldDelegate) =>
      oldDelegate.pointingRight != pointingRight;
}

void _drawDiamond(
  Canvas canvas,
  Offset center,
  double radius, {
  bool fill = false,
  Color color = CznToolsColors.gold,
}) {
  final path = Path()
    ..moveTo(center.dx, center.dy - radius)
    ..lineTo(center.dx + radius, center.dy)
    ..lineTo(center.dx, center.dy + radius)
    ..lineTo(center.dx - radius, center.dy)
    ..close();
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = .9,
  );
}

class _PanelFramePainter extends CustomPainter {
  _PanelFramePainter(this.variant);
  final int variant;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final frame = Rect.fromLTWH(
      3,
      3,
      math.max(0.0, size.width - 6),
      math.max(0.0, size.height - 6),
    );
    final paint = Paint()
      ..color = CznToolsColors.gold.withValues(alpha: .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    if (variant == 2) {
      _drawNotchedFrame(canvas, frame, 17, paint);
      _drawNotchedFrame(
        canvas,
        frame.deflate(3),
        15,
        paint..color = CznToolsColors.gold.withValues(alpha: .35),
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(frame, const Radius.circular(14)),
        paint,
      );
    }
    if (variant == 3) {
      _drawDiamond(canvas, Offset(3.5, size.height / 2), 3.4);
      _drawDiamond(canvas, Offset(size.width - 3.5, size.height / 2), 3.4);
    }
  }

  void _drawNotchedFrame(Canvas canvas, Rect rect, double radius, Paint paint) {
    final r = math.min(radius, math.min(rect.width, rect.height) / 2);
    final path = Path()
      ..moveTo(rect.left + r, rect.top)
      ..lineTo(rect.right - r, rect.top)
      ..quadraticBezierTo(
        rect.right - r,
        rect.top + r,
        rect.right,
        rect.top + r,
      )
      ..lineTo(rect.right, rect.bottom - r)
      ..quadraticBezierTo(
        rect.right - r,
        rect.bottom - r,
        rect.right - r,
        rect.bottom,
      )
      ..lineTo(rect.left + r, rect.bottom)
      ..quadraticBezierTo(
        rect.left + r,
        rect.bottom - r,
        rect.left,
        rect.bottom - r,
      )
      ..lineTo(rect.left, rect.top + r)
      ..quadraticBezierTo(rect.left + r, rect.top + r, rect.left + r, rect.top)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PanelFramePainter oldDelegate) =>
      oldDelegate.variant != variant;
}

class _CapsuleFramePainter extends CustomPainter {
  _CapsuleFramePainter({required this.primary, required this.centerTips});
  final bool primary, centerTips;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 24 || size.height < 18) return;
    final outer = Rect.fromLTWH(5, 3, size.width - 10, size.height - 6);
    final inner = outer.deflate(2.7);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = CznToolsColors.gold.withValues(alpha: primary ? .83 : .62);
    canvas.drawRRect(
      RRect.fromRectAndRadius(outer, Radius.circular(outer.height / 2)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, Radius.circular(inner.height / 2)),
      paint..color = CznToolsColors.gold.withValues(alpha: primary ? .62 : .38),
    );
    _drawDiamond(canvas, Offset(5, size.height / 2), primary ? 4 : 3);
    _drawDiamond(
      canvas,
      Offset(size.width - 5, size.height / 2),
      primary ? 4 : 3,
    );
    if (centerTips) {
      _drawDiamond(canvas, Offset(size.width / 2, 3.3), 3.5);
      _drawDiamond(canvas, Offset(size.width / 2, size.height - 3.3), 3.5);
    }
  }

  @override
  bool shouldRepaint(_CapsuleFramePainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.centerTips != centerTips;
}

class _RingFramePainter extends CustomPainter {
  _RingFramePainter(this.selected);
  final bool selected;
  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) * .44;
    if (radius <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? .85 : .6
      ..color = CznToolsColors.gold.withValues(alpha: selected ? .9 : .5);
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(
      center,
      radius - 2.1,
      paint
        ..color = CznToolsColors.gold.withValues(alpha: selected ? .75 : .35),
    );
    final tip = selected ? 2.9 : 1.9;
    for (final delta in [
      Offset(radius, 0),
      Offset(-radius, 0),
      Offset(0, radius),
      Offset(0, -radius),
    ]) {
      _drawDiamond(canvas, center + delta, tip, fill: selected);
    }
  }

  @override
  bool shouldRepaint(_RingFramePainter oldDelegate) =>
      oldDelegate.selected != selected;
}

class CznToolsSwitch extends StatelessWidget {
  const CznToolsSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    toggled: value,
    enabled: onChanged != null,
    label: label,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: SizedBox(
        width: 65,
        height: 48,
        child: Center(
          child: Opacity(
            opacity: onChanged == null ? .45 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 60,
              height: 32,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  colors: value
                      ? const [Color(0xFF4D0815), Color(0xFF9B201F)]
                      : const [Color(0xFF171D2C), Color(0xFF36313D)],
                ),
                border: Border.all(color: CznToolsColors.gold, width: 1.25),
                boxShadow: value
                    ? const [BoxShadow(color: Color(0x4DDB3821), blurRadius: 8)]
                    : null,
              ),
              child: AnimatedAlign(
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFFFFF6E5), Color(0xFFFFD294)],
                    ),
                    boxShadow: value
                        ? const [
                            BoxShadow(color: Color(0x99FFB44C), blurRadius: 7),
                          ]
                        : null,
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 15,
                    color: value
                        ? const Color(0xFFF3C285)
                        : const Color(0xFF918077),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

enum _ArtMode { contain, panel, button }

class _AtlasArt extends StatefulWidget {
  const _AtlasArt({
    required this.group,
    required this.index,
    required this.namedKey,
    this.mode = _ArtMode.contain,
    this.fallback,
    this.fallbackWidget,
    this.child,
    this.foregroundPainter,
  });
  final String group;
  final int index;
  final String namedKey;
  final _ArtMode mode;
  final Decoration? fallback;
  final Widget? fallbackWidget;
  final Widget? child;
  final CustomPainter? foregroundPainter;

  @override
  State<_AtlasArt> createState() => _AtlasArtState();
}

class _AtlasArtState extends State<_AtlasArt> {
  final _art = _ToolsArtRepository.instance;
  @override
  void initState() {
    super.initState();
    _art.acquire(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _art.release(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picture = _art.images[widget.group];
    final region = _art.rectFor(widget.group, widget.index, widget.namedKey);
    if (picture == null || region == null) {
      if (widget.fallbackWidget != null) return widget.fallbackWidget!;
      return CustomPaint(
        foregroundPainter: widget.foregroundPainter,
        child: DecoratedBox(
          decoration: widget.fallback ?? const BoxDecoration(),
          child: widget.child ?? const SizedBox.expand(),
        ),
      );
    }
    return CustomPaint(
      painter: _AtlasPainter(picture, region, widget.mode),
      foregroundPainter: widget.foregroundPainter,
      child: widget.child ?? const SizedBox.expand(),
    );
  }
}

/// One decoded copy per atlas. Assets live only while the tools pages consume
/// them; a short grace period avoids decode/dispose churn when changing tabs.
class _ToolsArtRepository extends ChangeNotifier {
  static final instance = _ToolsArtRepository();
  final Map<String, ui.Image> images = {};
  Map<String, dynamic>? _atlas;
  Future<void>? _loading;
  int _consumers = 0;
  int _generation = 0;
  Timer? _releaseTimer;

  void acquire(VoidCallback listener) {
    _releaseTimer?.cancel();
    _consumers++;
    addListener(listener);
    _loading ??= _load(_generation);
  }

  void release(VoidCallback listener) {
    removeListener(listener);
    _consumers--;
    if (_consumers != 0) return;
    _releaseTimer = Timer(const Duration(seconds: 2), () {
      if (_consumers != 0) return;
      _generation++;
      for (final image in images.values) {
        image.dispose();
      }
      images.clear();
      _atlas = null;
      _loading = null;
    });
  }

  Rect? rectFor(String group, int index, String key) {
    final atlas = _atlas;
    if (atlas == null) return null;
    final groups = atlas['regions'] ?? atlas;
    if (groups is! Map) return null;
    final entries = groups[group];
    dynamic values;
    if (entries is List && index < entries.length) values = entries[index];
    if (entries is Map) values = entries[key] ?? entries['$index'];
    if (values is Map) values = values['rect'] ?? values['bounds'];
    if (values is! List || values.length != 4) return null;
    final nums = values
        .map((item) => item is num ? item.toDouble() : double.nan)
        .toList();
    if (nums.any((item) => !item.isFinite)) return null;
    if (nums[0] < 0 || nums[1] < 0 || nums[2] <= 0 || nums[3] <= 0) return null;
    if (nums[0] + nums[2] > 1.001 || nums[1] + nums[3] > 1.001) return null;
    return Rect.fromLTWH(nums[0], nums[1], nums[2], nums[3]);
  }

  Future<void> _load(int generation) async {
    try {
      final parsed = jsonDecode(
        await rootBundle.loadString('assets/tools_atlas.json'),
      );
      if (generation != _generation) return;
      if (parsed is! Map<String, dynamic>) return;
      _atlas = parsed;
      await Future.wait([
        for (final group in ['type', 'icons', 'panels', 'buttons', 'rings'])
          _loadImage(group, generation),
      ]);
    } catch (_) {
      // A missing/invalid atlas leaves working vector and text controls visible.
    }
  }

  Future<void> _loadImage(String group, int generation) async {
    ui.Codec? codec;
    try {
      final bytes = await rootBundle.load('assets/tools_$group.png');
      codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final frame = await codec.getNextFrame();
      if (generation != _generation) {
        frame.image.dispose();
        return;
      }
      images[group]?.dispose();
      images[group] = frame.image;
      notifyListeners();
    } catch (_) {
      // Decode failures are local to an atlas; the affected widgets fall back.
    } finally {
      codec?.dispose();
    }
  }
}

class _AtlasPainter extends CustomPainter {
  _AtlasPainter(this.image, this.region, this.mode);
  final ui.Image image;
  final Rect region;
  final _ArtMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final source = Rect.fromLTWH(
      region.left * image.width,
      region.top * image.height,
      region.width * image.width,
      region.height * image.height,
    );
    final paint = Paint()..filterQuality = FilterQuality.high;
    if (mode == _ArtMode.contain) {
      final fitted = applyBoxFit(BoxFit.contain, source.size, size);
      final destination = Alignment.center.inscribe(
        fitted.destination,
        Offset.zero & size,
      );
      canvas.drawImageRect(image, source, destination, paint);
      return;
    }
    // Paint nine regions rather than stretching decorative corners. Nine-slice
    // coordinates are calculated at runtime; the original raster is preserved.
    final sx = math.min(source.width * .12, source.height * .5);
    final sy = source.height * .22;
    final dx = math.min(
      size.width / 2,
      mode == _ArtMode.button ? size.height * .62 : 22.0,
    );
    final dy = math.min(
      size.height / 2,
      mode == _ArtMode.button ? size.height * .22 : 16.0,
    );
    final srcX = [
      source.left,
      source.left + sx,
      source.right - sx,
      source.right,
    ];
    final srcY = [
      source.top,
      source.top + sy,
      source.bottom - sy,
      source.bottom,
    ];
    final dstX = [0.0, dx, size.width - dx, size.width];
    final dstY = [0.0, dy, size.height - dy, size.height];
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 3; column++) {
        final src = Rect.fromLTRB(
          srcX[column],
          srcY[row],
          srcX[column + 1],
          srcY[row + 1],
        );
        final dst = Rect.fromLTRB(
          dstX[column],
          dstY[row],
          dstX[column + 1],
          dstY[row + 1],
        );
        if (!src.isEmpty && !dst.isEmpty) {
          canvas.drawImageRect(image, src, dst, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_AtlasPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.region != region ||
      oldDelegate.mode != mode;
}
