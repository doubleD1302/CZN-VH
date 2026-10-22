import 'package:flutter/material.dart';

import 'czn_raster.dart';

const glassIvory = Color(0xFFFFE6CB);

class CznGlassPrimary extends StatelessWidget {
  const CznGlassPrimary({
    super.key,
    required this.label,
    required this.onPressed,
    this.compact = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool compact;
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? .6 : 1,
    child: Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const StadiumBorder(),
          splashColor: glassIvory.withValues(alpha: .14),
          child: CznButtonArt(
            child: SizedBox(
              height: compact ? 52 : 68,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 17 : 23),
                child: Row(
                  children: [
                    const CznImageIcon.glyph(CznUiGlyph.install, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label.toUpperCase(),
                          style: TextStyle(
                            color: glassIvory,
                            fontFamily: 'CznSerif',
                            fontSize: compact ? 18 : 21,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .7,
                            shadows: const [
                              Shadow(color: Colors.black, blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Transform.flip(
                      flipX: true,
                      child: const CznImageIcon.glyph(
                        CznUiGlyph.back,
                        size: 22,
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
}

/// A main home action below installation, using the launcher's gold frame.
class CznDonateButton extends StatelessWidget {
  const CznDonateButton({
    super.key,
    required this.onPressed,
    this.compact = false,
    this.width,
  });
  final VoidCallback? onPressed;
  final bool compact;
  final double? width;

  static const double minContentWidth = 148.0;

  @override
  Widget build(BuildContext context) {
    final visualHeight = compact ? 24.0 : 28.0;
    final touchHeight = compact ? 44.0 : 48.0;
    final targetWidth = width != null
        ? (width! < minContentWidth ? minContentWidth : width!)
        : minContentWidth;

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Ủng hộ dự án',
      onTap: onPressed,
      excludeSemantics: true,
      child: Opacity(
        opacity: onPressed == null ? .6 : 1,
        child: SizedBox(
          width: targetWidth,
          height: touchHeight,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(visualHeight / 2),
              child: Center(
                child: Container(
                  key: const Key('donate-visual-pill'),
                  width: targetWidth,
                  height: visualHeight,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xF0452632), Color(0xF01C1D2B)],
                    ),
                    border: Border.all(
                      color: const Color(0xCCBD9568),
                      width: 1.0,
                    ),
                    borderRadius: BorderRadius.circular(visualHeight / 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 10.0 : 12.0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.favorite_border,
                          color: glassIvory,
                          size: compact ? 12.0 : 14.0,
                        ),
                        SizedBox(width: compact ? 5.0 : 6.0),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'ỦNG HỘ DỰ ÁN',
                              style: TextStyle(
                                fontFamily: 'CznSerif',
                                color: glassIvory,
                                fontSize: compact ? 10.5 : 12.0,
                                letterSpacing: .4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: compact ? 4.0 : 5.0),
                        Icon(
                          Icons.chevron_right,
                          color: glassIvory,
                          size: compact ? 12.0 : 14.0,
                        ),
                      ],
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
}

class CznGlassUtility extends StatelessWidget {
  const CznGlassUtility({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.compact = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool compact;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: label,
    enabled: onPressed != null,
    onTap: onPressed,
    excludeSemantics: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: compact ? 40 : 50,
                height: compact ? 40 : 50,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Positioned.fill(child: CznCircleArt()),
                    Opacity(
                      opacity: onPressed == null ? .45 : 1,
                      child: CznImageIcon(icon, size: compact ? 23 : 26),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 4 : 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: glassIvory,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black, blurRadius: 5)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class CznGlassIcon extends StatelessWidget {
  const CznGlassIcon({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: SizedBox(
      width: 34,
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(child: CznCircleArt()),
          CznImageIcon(icon, size: 21),
        ],
      ),
    ),
  );
}

/// Generated clean logo. The black matte is made transparent at paint time;
/// the raster asset remains exactly as produced by ImageGen.
class CznGameLogo extends StatelessWidget {
  const CznGameLogo({super.key, this.showVietnamese = true});
  final bool showVietnamese;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Chaos Zero Nightmare Việt Hóa',
    image: true,
    excludeSemantics: true,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ColorFiltered(
            colorFilter: const ColorFilter.matrix([
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
            ]),
            child: Image.asset(
              'assets/game_logo.png',
              key: const Key('game-wordmark'),
              width: 176,
              height: 76,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ),
          if (showVietnamese)
            const Padding(
              padding: EdgeInsets.only(left: 10),
              child: Text(
                'VIỆT HÓA',
                style: TextStyle(
                  color: glassIvory,
                  fontSize: 9,
                  letterSpacing: 1.1,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
