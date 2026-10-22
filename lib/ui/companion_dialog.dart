import 'package:flutter/material.dart';

import 'bug_report_dialog.dart';
import 'hall_of_fame_dialog.dart';

const companionMessage =
    'Chào Thuyền trưởng! Thuyền trưởng thấy dịch thuật chỗ nào còn sai sót ư? Hãy chụp màn hình và gửi cho em để em sửa nhé! Ngoài ra Thuyền trưởng có thể copy mã lỗi hoặc dùng Báo lỗi hình ảnh để gửi phản hồi nhé!';

class CompanionDialog extends StatefulWidget {
  const CompanionDialog({
    super.key,
    required this.onCopyError,
    required this.onOpenDeveloper,
    this.onLaunchOverlay,
    this.onTroubleshoot,
  });
  final Future<bool> Function() onCopyError;
  final Future<void> Function() onOpenDeveloper;
  final VoidCallback? onLaunchOverlay;
  final VoidCallback? onTroubleshoot;
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
            ? 'Đã copy mã lỗi vào bộ nhớ tạm.'
            : 'Chưa copy được mã lỗi. Thử lại nhé.';
        _copying = false;
      });
    }
  }

  void _openBugReport() {
    showDialog<void>(context: context, builder: (_) => const BugReportDialog());
  }

  void _openChunkReport() {
    showDialog<void>(
      context: context,
      builder: (_) => const BugReportDialog(isChunkMode: true),
    );
  }

  void _openHallOfFame() {
    showDialog<void>(
      context: context,
      builder: (_) => const HallOfFameDialog(),
    );
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
                  fontSize: 16,
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
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(
                (MediaQuery.disableAnimationsOf(context) ||
                        WidgetsBinding.instance.runtimeType.toString().contains(
                          'Test',
                        ))
                    ? 'assets/companion_still.png'
                    : 'assets/companion.gif',
                width: 164,
                height: 172,
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RichText(
                      textScaler: MediaQuery.textScalerOf(context),
                      text: TextSpan(
                        style: const TextStyle(
                          color: Color(0xFF292332),
                          fontSize: 16,
                          height: 1.6,
                        ),
                        children: [
                          const TextSpan(
                            text: 'Chào Thuyền trưởng! Nếu gặp lỗi hoặc thấy dịch thuật chỗ nào còn sai sót ư? Hãy chụp màn hình lại và gửi cho em qua nút Báo Lỗi bên dưới để em sửa ngay nhé! Hoặc Thuyền trưởng có thể ',
                          ),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: _link(
                              'copy mã lỗi',
                              const Key('copy-error-link'),
                              _copy,
                            ),
                          ),
                          const TextSpan(text: ' hoặc '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: _link(
                              'nhắn cho Dev',
                              const Key('dev-profile-link'),
                              widget.onOpenDeveloper,
                            ),
                          ),
                          const TextSpan(
                            text: ' để được hỗ trợ nhanh chóng nhé!',
                          ),
                        ],
                      ),
                    ),
                    if (_feedback.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _feedback,
                          key: const Key('copy-error-feedback'),
                          style: const TextStyle(
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Các nút hành động: Chibi Nổi, Báo Lỗi Bằng Hình Ảnh & Bảng Vinh Danh
                    if (widget.onLaunchOverlay != null) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          widget.onLaunchOverlay!();
                          Navigator.pop(context);
                        },
                        icon: const Icon(
                          Icons.picture_in_picture_alt_rounded,
                          size: 20,
                        ),
                        label: const Text(
                          'Bật Chibi nổi khi chơi game (F9)',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E5BB0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (widget.onTroubleshoot != null) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onTroubleshoot!();
                        },
                        icon: const Icon(
                          Icons.build_circle_outlined,
                          size: 20,
                        ),
                        label: const Text(
                          'Hướng Dẫn Sửa Lỗi Shizuku',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD48B37),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    ElevatedButton.icon(
                      onPressed: _openChunkReport,
                      icon: const Icon(
                        Icons.translate_rounded,
                        size: 20,
                      ),
                      label: const Text(
                        'Báo Cho Nhóm Dịch (Chunk Chưa Dịch)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8A2E3B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _openBugReport,
                      icon: const Icon(
                        Icons.add_photo_alternate_rounded,
                        size: 20,
                      ),
                      label: const Text(
                        'Báo Lỗi Bằng Hình Ảnh',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB03B50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    OutlinedButton.icon(
                      onPressed: _openHallOfFame,
                      icon: const Icon(
                        Icons.volunteer_activism_rounded,
                        color: Color(0xFFD4AF37),
                        size: 20,
                      ),
                      label: const Text(
                        'Lời Cám Ơn',
                        style: TextStyle(
                          color: Color(0xFF9E233A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Color(0xFFB03B50),
                          width: 1.5,
                        ),
                        backgroundColor: const Color(0xFFFFE3DC),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Đã hiểu',
                          style: TextStyle(
                            color: Color(0xFF9E233A),
                            fontWeight: FontWeight.w700,
                          ),
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
