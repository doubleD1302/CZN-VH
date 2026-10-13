import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'czn_theme.dart';

class CznMark extends StatelessWidget {
  const CznMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * .18),
      child: Image.asset(
        'assets/app_icon.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.high,
      ),
    ),
  );
}

class CznHero extends StatelessWidget {
  const CznHero({super.key, required this.patchVersion});
  final String? patchVersion;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF242029), Color(0xFF111319)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: CustomPaint(
        painter: const _AnomalyPainter(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            border: Border.all(color: CznColors.red.withValues(alpha: .22)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: Divider(color: CznColors.red, thickness: 2),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'BẢN VIỆT HÓA CỘNG ĐỒNG',
                      style: TextStyle(
                        color: CznColors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 21),
              Text(
                'CHAOS ZERO',
                style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                  fontSize: 30,
                  letterSpacing: .5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'NIGHTMARE',
                style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                  fontSize: 30,
                  letterSpacing: .5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Giữa hỗn loạn, câu chuyện vẫn tiếp nối.',
                style: TextStyle(
                  color: CznColors.text,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 26),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  Text(
                    'BẢN DỊCH  ${patchVersion ?? 'Đang đọc…'}',
                    style: const TextStyle(
                      color: CznColors.text,
                      fontSize: 10,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Text(
                    'NGÔN NGỮ  日本語 → VI',
                    style: TextStyle(
                      color: CznColors.muted,
                      fontSize: 10,
                      letterSpacing: .5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// Vector atmosphere stays crisp on phones without a network or bitmap asset.
class _AnomalyPainter extends CustomPainter {
  const _AnomalyPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final c = Offset(size.width * .93, size.height * .39);
    final radius = size.width * .32;
    final glowRect = Rect.fromCircle(center: c, radius: radius * 1.5);
    canvas.drawRect(
      glowRect,
      Paint()
        ..shader = RadialGradient(
          colors: [CznColors.red.withValues(alpha: .22), Colors.transparent],
        ).createShader(glowRect),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final scale in [.77, 1.0, 1.16]) {
      ring.color = CznColors.red.withValues(alpha: scale == 1 ? .5 : .15);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: radius * scale),
        -1.85,
        math.pi * 1.56,
        false,
        ring,
      );
    }
    final fracture = Path()
      ..moveTo(size.width * .88, -20)
      ..lineTo(size.width * .71, size.height * .49)
      ..lineTo(size.width * .82, size.height * .43)
      ..lineTo(size.width * .62, size.height + 20)
      ..lineTo(size.width * .96, size.height * .36)
      ..lineTo(size.width * .85, size.height * .40)
      ..lineTo(size.width * 1.02, -20)
      ..close();
    canvas.drawPath(
      fracture,
      Paint()..color = CznColors.red.withValues(alpha: .10),
    );
    canvas.drawPath(
      fracture,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = CznColors.red.withValues(alpha: .23),
    );
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .035)
      ..strokeWidth = .5;
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final ruins = Paint()
      ..color = const Color(0xFF0C0E14).withValues(alpha: .30);
    for (var i = 0; i < 18; i++) {
      final x = size.width * .43 + i * 17;
      final h = 10.0 + (i * 37 % 57);
      canvas.drawRect(Rect.fromLTWH(x, size.height - h, 13, h), ruins);
    }
    final red = Paint()
      ..color = CznColors.red.withValues(alpha: .55)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width - 25, 20),
      Offset(size.width - 12, 20),
      red,
    );
    canvas.drawLine(
      Offset(size.width - 12, 20),
      Offset(size.width - 12, 33),
      red,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AnomalyPainter oldDelegate) => false;
}

class CznSectionLabel extends StatelessWidget {
  const CznSectionLabel(this.title, {super.key, this.trailing});
  final String title;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: [
        Container(width: 3, height: 14, color: CznColors.red),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
              color: CznColors.text,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(fontSize: 11, color: CznColors.muted),
          ),
      ],
    ),
  );
}

class CznStatusStrip extends StatelessWidget {
  const CznStatusStrip({
    super.key,
    required this.access,
    required this.ready,
    required this.installed,
  });
  final bool access, ready, installed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Row(
      children: [
        for (final item in [
          ('Shizuku', access),
          ('Dữ liệu', ready),
          ('Bản dịch', installed),
        ])
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(
                    item.$2 ? Icons.check_box_outlined : Icons.crop_square,
                    size: 15,
                    color: item.$2 ? CznColors.green : CznColors.muted,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    item.$1,
                    style: TextStyle(
                      fontSize: 12,
                      color: item.$2 ? CznColors.green : CznColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
