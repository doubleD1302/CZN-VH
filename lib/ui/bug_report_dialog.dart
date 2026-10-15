import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/bug_reporter_service.dart';

class BugReportDialog extends StatefulWidget {
  final bool initialSuccess;
  const BugReportDialog({super.key, this.initialSuccess = false});

  @override
  State<BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends State<BugReportDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  File? _imageFile;
  bool _submitting = false;
  late bool _submittedSuccess;

  @override
  void initState() {
    super.initState();
    _submittedSuccess = widget.initialSuccess;
    _loadLastName();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _loadLastName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastName = prefs.getString('last_bug_reporter_name') ?? '';
      if (mounted && lastName.isNotEmpty) {
        _nameController.text = lastName;
      }
    } catch (_) {}
  }

  Future<void> _pickImage() async {
    try {
      // Quyền truy cập ảnh tối ưu nhất: Photo Picker hệ thống
      // Chỉ ảnh nào được chọn thì ứng dụng mới có quyền đọc tệp đó
      final file = await FilePicker.pickFile(
        type: FileType.image,
      );

      if (file != null && file.path != null && mounted) {
        setState(() => _imageFile = File(file.path!));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể chọn ảnh: $e')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ảnh chụp màn hình bị lỗi.')),
      );
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên của Thuyền trưởng.')),
      );
      return;
    }

    final desc = _descController.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập mô tả lỗi gặp phải.')),
      );
      return;
    }

    setState(() => _submitting = true);

    final success = await BugReporterService.submitBugReport(
      imageFile: _imageFile!,
      senderName: name,
      description: desc,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (success) {
      // Lưu lại tên người gửi để tự động kế thừa ở lần nhập sau
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_bug_reporter_name', name);
      } catch (_) {}

      if (!mounted) return;
      setState(() => _submittedSuccess = true);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFB03B50),
          content: Text('Chưa gửi được báo cáo. Vui lòng thử lại.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8EE),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _submittedSuccess
                ? const Color(0xFF2E7D32)
                : const Color(0xFFB03B50),
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 22,
              offset: Offset(0, 9),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: _submittedSuccess ? _buildSuccessView() : _buildFormView(),
        ),
      ),
    ),
  );

  Widget _buildSuccessView() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF292332)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFE8F5E9),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check_circle_rounded,
          color: Color(0xFF2E7D32),
          size: 52,
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'GHI NHẬN THÀNH CÔNG!',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF1B5E20),
          fontSize: 18.5,
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFECE6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5A8B0), width: 1.2),
        ),
        child: Column(
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_rounded, color: Color(0xFFB03B50), size: 20),
                SizedBox(width: 8),
                Text(
                  'CẢM ƠN THUYỀN TRƯỞNG',
                  style: TextStyle(
                    color: Color(0xFF9E233A),
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    letterSpacing: .5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Báo cáo lỗi của Thuyền Trưởng ${_nameController.text.trim().isNotEmpty ? _nameController.text.trim() : "bạn"} đã được ghi nhận và gửi thành công!\n\nChân thành cảm ơn sự đồng hành và đóng góp quý báu của Thuyền Trưởng để bản Việt Hóa Chaos Zero Nightmare ngày một hoàn hảo và trọn vẹn hơn! ♥',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF4A3E4E),
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      SizedBox(
        height: 44,
        child: ElevatedButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.check_rounded, size: 20),
          label: const Text(
            'Đã Hiểu & Đóng',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _buildFormView() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Header
      Row(
        children: [
          const Icon(
            Icons.bug_report_rounded,
            color: Color(0xFFB03B50),
            size: 28,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Báo Lỗi Bằng Hình Ảnh',
              style: TextStyle(
                color: Color(0xFF292332),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF292332)),
            onPressed: _submitting ? null : () => Navigator.pop(context),
          ),
        ],
      ),
      const Divider(color: Color(0xFFB03B50), thickness: 1),
      const SizedBox(height: 10),

      // Ô chọn ảnh
      InkWell(
        onTap: _submitting ? null : _pickImage,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: const Color(0xFFFFE3DC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFB03B50),
              width: 1.5,
              style: BorderStyle.solid,
            ),
          ),
          child: _imageFile != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.file(
                        _imageFile!,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xAA000000),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                )
              : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_a_photo_outlined,
                      size: 40,
                      color: Color(0xFF9E233A),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Chạm để chọn ảnh chụp màn hình lỗi',
                      style: TextStyle(
                        color: Color(0xFF9E233A),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '(Chỉ cấp quyền đọc cho ảnh được chọn)',
                      style: TextStyle(
                        color: Color(0xFF6B6275),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
        ),
      ),
      const SizedBox(height: 14),

      // Ô nhập tên (kế thừa lần nhập gần nhất)
      TextField(
        controller: _nameController,
        enabled: !_submitting,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
        cursorColor: Colors.black,
        decoration: InputDecoration(
          labelText: 'Tên Thuyền trưởng',
          labelStyle: const TextStyle(
            color: Color(0xFF9E233A),
            fontWeight: FontWeight.w600,
          ),
          hintText: 'Nhập tên hoặc biệt danh...',
          hintStyle: const TextStyle(
            color: Color(0xFF8A7F92),
          ),
          prefixIcon: const Icon(
            Icons.person_outline,
            color: Color(0xFF9E233A),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFB03B50)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD3C0A7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFFB03B50),
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
      ),
      const SizedBox(height: 12),

      // Ô mô tả lỗi
      TextField(
        controller: _descController,
        enabled: !_submitting,
        maxLines: 3,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: Colors.black,
        decoration: InputDecoration(
          labelText: 'Mô tả lỗi',
          labelStyle: const TextStyle(
            color: Color(0xFF9E233A),
            fontWeight: FontWeight.w600,
          ),
          hintText: 'Vị trí lỗi, câu thoại, thẻ bài hoặc tình huống...',
          hintStyle: const TextStyle(
            color: Color(0xFF8A7F92),
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(bottom: 40),
            child: Icon(Icons.description_outlined, color: Color(0xFF9E233A)),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFB03B50)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD3C0A7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFFB03B50),
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
      ),
      const SizedBox(height: 18),

      // Nút hành động
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.pop(context),
            child: const Text(
              'Hủy',
              style: TextStyle(
                color: Color(0xFF6B6275),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB03B50),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.send_rounded, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Gửi Báo Cáo',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ],
  );
}
