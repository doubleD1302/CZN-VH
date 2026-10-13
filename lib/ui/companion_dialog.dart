import 'package:flutter/material.dart';

const companionMessage =
    'Thuyền trưởng lại gặp lỗi rồi ư? Người cứ copy mã lỗi này gửi cho Dev xử lý nhé, việc của Thuyền trưởng lúc này chỉ là nghỉ ngơi và để em chăm sóc thôi~♥';

class CompanionDialog extends StatefulWidget {
  const CompanionDialog({
    super.key,
    required this.onCopyError,
    required this.onOpenDeveloper,
  });
  final Future<bool> Function() onCopyError;
  final Future<void> Function() onOpenDeveloper;
  @override
  State<CompanionDialog> createState() => _CompanionDialogState();
}

class _CompanionDialogState extends State<CompanionDialog> {
  String _feedback = '';
  bool _copying = false;
  Future<void> _copy() async {
    if (_copying) return;
    setState(() => _copying = true);
    final copied = await widget.onCopyError();
    if (mounted) {
      setState(() {
        _feedback = copied
            ? 'Đã copy mã lỗi ♥'
            : 'Chưa copy được mã lỗi. Thử lại nhé.';
        _copying = false;
      });
    }
  }

  Widget _link(String text, Key key, Future<void> Function() callback) =>
      Semantics(
        link: true,
        label: text,
        onTap: callback,
        excludeSemantics: true,
        child: Material(
          color: const Color(0xFFFFE3DC),
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            key: key,
            onTap: callback,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFF9E233A),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('companion-chat'),
    backgroundColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 420,
        maxHeight: MediaQuery.sizeOf(context).height * .82,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(
                MediaQuery.disableAnimationsOf(context)
                    ? 'assets/companion_still.png'
                    : 'assets/companion.gif',
                width: 82,
                height: 86,
                excludeFromSemantics: true,
              ),
            ),
            CustomPaint(
              painter: const _SpeechTail(),
              child: Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8EE),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFB03B50), width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 22,
                      offset: Offset(0, 9),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichText(
                      textScaler: MediaQuery.textScalerOf(context),
                      text: TextSpan(
                        style: const TextStyle(
                          color: Color(0xFF292332),
                          fontSize: 17,
                          height: 1.65,
                        ),
                        children: [
                          const TextSpan(
                            text: 'Thuyền trưởng lại gặp lỗi rồi ư? Người cứ ',
                          ),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: _link(
                              'copy mã lỗi',
                              const Key('copy-error-link'),
                              _copy,
                            ),
                          ),
                          const TextSpan(text: ' này '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: _link(
                              'gửi cho Dev',
                              const Key('dev-profile-link'),
                              widget.onOpenDeveloper,
                            ),
                          ),
                          const TextSpan(
                            text: ' xử lý nhé, việc của Thuyền trưởng lúc này chỉ là nghỉ ngơi và để em chăm sóc thôi~♥',
                          ),
                        ],
                      ),
                    ),
                    if (_feedback.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _feedback,
                          key: const Key('copy-error-feedback'),
                          style: const TextStyle(color: Color(0xFF9E233A)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Đã hiểu ♥',
                        style: TextStyle(
                          color: Color(0xFF9E233A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SpeechTail extends CustomPainter {
  const _SpeechTail();
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(30, 16)
      ..lineTo(43, 1)
      ..lineTo(58, 16)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFF8EE));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFB03B50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
