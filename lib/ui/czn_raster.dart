import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const cznMatteAlpha = ColorFilter.matrix([
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
]);

enum CznUiGlyph { settings, update, help, install, back, copy, restore, folder }

class CznImageIcon extends StatelessWidget {
  const CznImageIcon(this.icon, {super.key, this.size = 24}) : glyph = null;
  const CznImageIcon.glyph(this.glyph, {super.key, this.size = 24})
    : icon = null;
  final IconData? icon;
  final CznUiGlyph? glyph;
  final double size;
  @override
  Widget build(BuildContext context) {
    final icons = {
      Icons.settings: CznUiGlyph.settings,
      Icons.settings_outlined: CznUiGlyph.settings,
      Icons.notifications_none: CznUiGlyph.update,
      Icons.campaign_outlined: CznUiGlyph.update,
      Icons.help_outline: CznUiGlyph.help,
      Icons.arrow_back: CznUiGlyph.back,
      Icons.chevron_left: CznUiGlyph.back,
      Icons.content_copy: CznUiGlyph.copy,
      Icons.restore: CznUiGlyph.restore,
      Icons.folder_open: CznUiGlyph.folder,
      Icons.download_done: CznUiGlyph.install,
    };
    final selected = glyph ?? icons[icon];
    if (selected == null) return Icon(icon, size: size);
    final column = selected.index % 4, row = selected.index ~/ 4;
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment(-1 + 2 * column / 3, -1 + 2.0 * row),
            minWidth: size * 4,
            maxWidth: size * 4,
            minHeight: size * 2,
            maxHeight: size * 2,
            child: ColorFiltered(
              colorFilter: cznMatteAlpha,
              child: Image.asset(
                'assets/ui_icons.png',
                width: size * 4,
                height: size * 2,
                fit: BoxFit.fill,
                excludeFromSemantics: true,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CznCircleArt extends StatelessWidget {
  const CznCircleArt({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ColorFiltered(
      colorFilter: cznMatteAlpha,
      child: Image.asset(
        'assets/ui_circle.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    ),
  );
}

/// Raster frame sliced only while painting; the generated PNG is never edited.
class CznButtonArt extends StatefulWidget {
  const CznButtonArt({super.key, required this.child});
  final Widget child;
  @override
  State<CznButtonArt> createState() => _CznButtonArtState();
}

class _CznButtonArtState extends State<CznButtonArt> {
  ImageStream? _stream;
  late ImageStreamListener _listener;
  ui.Image? _picture;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream != null) return;
    _stream = const AssetImage('assets/ui_button.png')
        .resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((info, synchronous) {
      final next = info.image.clone();
      info.dispose();
      if (!mounted) {
        next.dispose();
        return;
      }
      setState(() {
        _picture?.dispose();
        _picture = next;
      });
    });
    _stream!.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _picture?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ButtonArtPainter(_picture), child: widget.child);
}

class _ButtonArtPainter extends CustomPainter {
  _ButtonArtPainter(this.picture);
  final ui.Image? picture;
  @override
  void paint(Canvas canvas, Size size) {
    final image = picture;
    if (image == null || size.isEmpty) return;
    final band = Rect.fromLTWH(
      0,
      image.height * .14,
      image.width.toDouble(),
      image.height * .63,
    );
    final sourceCap = band.height * .95;
    final cap = math.min(size.width / 2, sourceCap * size.height / band.height);
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..colorFilter = cznMatteAlpha;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, band.top, sourceCap, band.height),
      Rect.fromLTWH(0, 0, cap, size.height),
      paint,
    );
    if (size.width > cap * 2) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          sourceCap,
          band.top,
          band.width - 2 * sourceCap,
          band.height,
        ),
        Rect.fromLTWH(cap, 0, size.width - 2 * cap, size.height),
        paint,
      );
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(band.width - sourceCap, band.top, sourceCap, band.height),
      Rect.fromLTWH(size.width - cap, 0, cap, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ButtonArtPainter oldDelegate) =>
      oldDelegate.picture != picture;
}
