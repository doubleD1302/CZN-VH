import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/windows_patch_service.dart';

class WindowsGamePathDialog extends StatefulWidget {
  const WindowsGamePathDialog({
    super.key,
    required this.currentPath,
    required this.service,
  });

  final String currentPath;
  final WindowsPatchService service;

  @override
  State<WindowsGamePathDialog> createState() => _WindowsGamePathDialogState();
}

class _WindowsGamePathDialogState extends State<WindowsGamePathDialog> {
  late final TextEditingController _controller;
  bool _scanning = false;
  String? _errorText;
  bool _isValid = false;
  bool _hasJapanese = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPath);
    _validatePath(_controller.text);
    _controller.addListener(() => _validatePath(_controller.text));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validatePath(String path) {
    final valid = widget.service.isValidGameDir(path);
    final hasJa = widget.service.hasJapanesePackage(path);
    if (mounted) {
      setState(() {
        _isValid = valid;
        _hasJapanese = hasJa;
        if (!valid) {
          _errorText =
              'Thư mục chưa đúng. Cần chọn thư mục chứa file ucldr_chaoszeronightmare.exe hoặc bin\\appdata.';
        } else if (!hasJa) {
          _errorText =
              'Thư mục hợp lệ, nhưng chưa tải gói Tiếng Nhật (lang_ja). Bạn cần mở CZN chọn 日本語 trước khi cài.';
        } else {
          _errorText = null;
        }
      });
    }
  }

  Future<void> _browseFolder() async {
    try {
      final picked = await FilePicker.getDirectoryPath(
        dialogTitle: 'Chọn thư mục cài đặt Chaos Zero Nightmare',
        initialDirectory: widget.service.isValidGameDir(_controller.text)
            ? _controller.text
            : null,
      );
      if (picked != null && mounted) {
        _controller.text = picked;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi duyệt thư mục: $e')),
        );
      }
    }
  }

  Future<void> _autoDetect() async {
    setState(() => _scanning = true);
    final detected = await widget.service.autoDetectGameDirectory();
    if (mounted) {
      setState(() => _scanning = false);
      if (detected != null) {
        _controller.text = detected;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            content: Text('Đã tự động tìm thấy game tại: $detected'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFB03B50),
            content: Text('Không tìm thấy thư mục mặc định. Vui lòng duyệt hoặc nhập thủ công.'),
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    final path = _controller.text.trim();
    if (!widget.service.isValidGameDir(path)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFB03B50),
          content: Text('Đường dẫn không hợp lệ. Vui lòng kiểm tra lại thư mục game.'),
        ),
      );
      return;
    }
    await widget.service.setGameDirectory(path);
    if (mounted) Navigator.pop(context, path);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF161A24),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE0C88F), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.folder_open_rounded,
                  color: Color(0xFFE0C88F),
                  size: 26,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'ĐƯỜNG DẪN THƯ MỤC GAME CZN',
                    style: TextStyle(
                      color: Color(0xFFF0E6D2),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFFA8B0BF)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Color(0x33E0C88F), height: 24),

            // Instructions
            const Text(
              'Chọn thư mục gốc cài đặt Chaos Zero Nightmare trên máy tính của bạn '
              '(thư mục chứa ucldr_chaoszeronightmare.exe hoặc nhánh bin\\appdata).',
              style: TextStyle(
                color: Color(0xFFC5CDE0),
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),

            // Input Field
            TextField(
              controller: _controller,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontFamily: 'Consolas',
              ),
              decoration: InputDecoration(
                labelText: 'Đường dẫn thư mục game',
                labelStyle: const TextStyle(color: Color(0xFFE0C88F)),
                hintText: r'C:\ProgramData\Smilegate\Games\ChaosZeroNightmare',
                hintStyle: const TextStyle(color: Color(0xFF6B7280)),
                filled: true,
                fillColor: const Color(0xFF0F1219),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE0C88F)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: _isValid ? const Color(0xFF4CAF50) : const Color(0xFF4B5563),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE0C88F), width: 1.5),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.folder_shared_outlined, color: Color(0xFFE0C88F)),
                  tooltip: 'Duyệt thư mục...',
                  onPressed: _browseFolder,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Status indication
            Row(
              children: [
                Icon(
                  !_isValid
                      ? Icons.error_outline_rounded
                      : (!_hasJapanese ? Icons.warning_amber_rounded : Icons.check_circle_outline),
                  color: !_isValid
                      ? const Color(0xFFEF5350)
                      : (!_hasJapanese ? const Color(0xFFFFA726) : const Color(0xFF4CAF50)),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    !_isValid
                        ? (_errorText ?? 'Thư mục chưa đúng cấu trúc game CZN.')
                        : (!_hasJapanese
                            ? (_errorText ??
                                'Thư mục hợp lệ, nhưng chưa tải gói Tiếng Nhật.')
                            : 'Thư mục game CZN hợp lệ, đã có gói Tiếng Nhật.'),
                    style: TextStyle(
                      color: !_isValid
                          ? const Color(0xFFEF5350)
                          : (!_hasJapanese ? const Color(0xFFFFB74D) : const Color(0xFF81C784)),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Actions row
            Row(
              children: [
                // Nút tự động dò tìm
                OutlinedButton.icon(
                  onPressed: _scanning ? null : _autoDetect,
                  icon: _scanning
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE0C88F)),
                        )
                      : const Icon(Icons.travel_explore_rounded, size: 18),
                  label: Text(_scanning ? 'Đang dò tìm…' : 'Tự động tìm'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE0C88F),
                    side: const BorderSide(color: Color(0xFFE0C88F)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const Spacer(),

                // Hủy
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy', style: TextStyle(color: Color(0xFFA8B0BF))),
                ),
                const SizedBox(width: 8),

                // Lưu
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Lưu & Áp dụng'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE0C88F),
                    foregroundColor: const Color(0xFF14171F),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
