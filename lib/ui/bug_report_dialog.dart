import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/bug_reporter_service.dart';

enum BugReportMode { imageBug, chunkMissing }

class BugReportDialog extends StatefulWidget {
  final bool initialSuccess;
  final bool isChunkMode;
  final String? initialChunkName;
  final Map<String, dynamic>? initialMetadata;

  const BugReportDialog({
    super.key,
    this.initialSuccess = false,
    this.isChunkMode = false,
    this.initialChunkName,
    this.initialMetadata,
  });

  const BugReportDialog.forChunk({
    super.key,
    required String chunkName,
    Map<String, dynamic>? metadata,
  })  : initialSuccess = false,
        isChunkMode = true,
        initialChunkName = chunkName,
        initialMetadata = metadata;

  @override
  State<BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends State<BugReportDialog> {
  late BugReportMode _mode;
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _chunkNameController = TextEditingController();

  File? _imageFile;
  bool _submitting = false;
  late bool _submittedSuccess;
  String _successMessage = '';
  late String _requestId;

  // Danh mục các chunk vật lý phổ biến của CZN để người dùng dễ chọn
  static const List<String> _knownChunks = [
    'base_b01_0.ssrc',
    'base_b02_0.ssrc',
    'base_b03_0.ssrc',
    'base_b04_0.ssrc',
    'base_b07_0.ssrc',
    'base_b08_0.ssrc',
    'base_b09_0.ssrc',
    'base_b10_0.ssrc',
    'base_b11_0.ssrc',
    'base_b12_0.ssrc',
    'base_b13_0.ssrc',
    'base_b15_0.ssrc',
    'base_b17_0.ssrc',
    'base_b19_0.ssrc',
    'base_b20_0.ssrc',
    'base_b21_0.ssrc',
    'base_b22_0.ssrc',
    'base_b23_0.ssrc',
    'base_b24_0.ssrc',
    'base_b25_0.ssrc',
    'base_b26_0.ssrc',
    'base_b31_0.ssrc',
    'lang_ja_b01_0.ssrc',
  ];

  @override
  void initState() {
    super.initState();
    _mode = widget.isChunkMode
        ? BugReportMode.chunkMissing
        : BugReportMode.imageBug;
    _submittedSuccess = widget.initialSuccess;
    _chunkNameController.text = widget.initialChunkName ?? 'base_b08_0.ssrc';
    _requestId = 'req_${DateTime.now().millisecondsSinceEpoch}_${widget.initialChunkName ?? "gen"}';
    _loadLastName();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _chunkNameController.dispose();
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
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file != null && file.path != null && mounted) {
        setState(() => _imageFile = File(file.path!));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Không thể chọn ảnh: $e')));
      }
    }
  }

  void _clearImage() {
    setState(() => _imageFile = null);
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên của Thuyền trưởng.')),
      );
      return;
    }

    if (_mode == BugReportMode.imageBug) {
      if (_imageFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vui lòng chọn ảnh chụp màn hình bị lỗi.'),
          ),
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

      final result = await BugReporterService.submitBugReport(
        imageFile: _imageFile!,
        senderName: name,
        description: desc,
        requestId: _requestId,
      );

      if (!mounted) return;
      setState(() => _submitting = false);

      if (result.success) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('last_bug_reporter_name', name);
        } catch (_) {}

        if (!mounted) return;
        setState(() {
          _successMessage =
              'Báo cáo lỗi của Thuyền Trưởng đã được ghi nhận và gửi thành công!';
          _submittedSuccess = true;
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFB03B50),
            content: Text('Chưa gửi được báo cáo: ${result.message}'),
          ),
        );
      }
    } else {
      // Chế độ báo chunk chưa dịch
      final chunkName = _chunkNameController.text.trim();
      if (chunkName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng chọn hoặc nhập tên file chunk.')),
        );
        return;
      }

      setState(() => _submitting = true);

      final meta = Map<String, dynamic>.from(widget.initialMetadata ?? {});
      meta['chunk_name'] = chunkName;
      meta['report_type'] = 'missing_translation';

      final result = await BugReporterService.submitChunkReport(
        chunkName: chunkName,
        senderName: name,
        userNotes: _descController.text.trim(),
        optionalImageFile: _imageFile,
        metadata: meta,
        requestId: _requestId,
      );

      if (!mounted) return;
      setState(() => _submitting = false);

      if (result.success) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('last_bug_reporter_name', name);
        } catch (_) {}

        if (!mounted) return;
        setState(() {
          _successMessage = result.isDuplicate
              ? 'Báo cáo cho chunk $chunkName đã được ghi nhận trước đó! Cảm ơn Thuyền Trưởng đã quan tâm và đồng hành.'
              : 'Báo cáo chunk $chunkName chưa dịch đã được ghi nhận và gửi thành công!';
          _submittedSuccess = true;
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFB03B50),
            content: Text('Chưa gửi được báo cáo: ${result.message}'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
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
                    Icon(
                      Icons.favorite_rounded,
                      color: Color(0xFFB03B50),
                      size: 20,
                    ),
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
                  _successMessage.isNotEmpty
                      ? _successMessage
                      : 'Báo cáo của Thuyền Trưởng ${_nameController.text.trim().isNotEmpty ? _nameController.text.trim() : "bạn"} đã được ghi nhận và gửi thành công!\n\nChân thành cảm ơn sự đồng hành và đóng góp quý báu của Thuyền Trưởng để bản Việt Hóa Chaos Zero Nightmare ngày một hoàn hảo và trọn vẹn hơn! ♥',
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
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
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
              Icon(
                _mode == BugReportMode.chunkMissing
                    ? Icons.translate_rounded
                    : Icons.bug_report_rounded,
                color: const Color(0xFFB03B50),
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _mode == BugReportMode.chunkMissing
                      ? 'Báo Cho Nhóm Dịch'
                      : 'Báo Lỗi Bằng Hình Ảnh',
                  style: const TextStyle(
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
          const SizedBox(height: 6),

          // Selector chuyển đổi giữa 2 chế độ
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFECE6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _submitting
                        ? null
                        : () => setState(() => _mode = BugReportMode.chunkMissing),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _mode == BugReportMode.chunkMissing
                            ? const Color(0xFFB03B50)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Chunk Chưa Dịch',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _mode == BugReportMode.chunkMissing
                              ? Colors.white
                              : const Color(0xFF8A2E3B),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _submitting
                        ? null
                        : () => setState(() => _mode = BugReportMode.imageBug),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _mode == BugReportMode.imageBug
                            ? const Color(0xFFB03B50)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Lỗi Hình Ảnh',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _mode == BugReportMode.imageBug
                              ? Colors.white
                              : const Color(0xFF8A2E3B),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Khối riêng cho Chunk Mode
          if (_mode == BugReportMode.chunkMissing) ...[
            // Banner hiển thị tiêu đề báo cáo người dùng yêu cầu
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFB74D), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: Color(0xFFE65100)),
                      SizedBox(width: 6),
                      Text(
                        'TIÊU ĐỀ BÁO CÁO TỰ ĐỘNG:',
                        style: TextStyle(
                          color: Color(0xFFE65100),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Chunk ${_chunkNameController.text.trim()} chưa được dịch',
                    style: const TextStyle(
                      color: Color(0xFFBF360C),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Dropdown / Nhập tên chunk
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chunkNameController,
                    enabled: !_submitting,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Tên file chunk vật lý',
                      labelStyle: const TextStyle(
                        color: Color(0xFF9E233A),
                        fontWeight: FontWeight.w600,
                      ),
                      hintText: 'base_b08_0.ssrc',
                      prefixIcon: const Icon(Icons.folder_zip_outlined,
                          color: Color(0xFF9E233A)),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFB03B50)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.arrow_drop_down_circle_outlined,
                      color: Color(0xFF9E233A)),
                  tooltip: 'Chọn chunk phổ biến',
                  onSelected: (chunk) {
                    setState(() {
                      _chunkNameController.text = chunk;
                    });
                  },
                  itemBuilder: (ctx) => _knownChunks
                      .map((c) => PopupMenuItem(
                            value: c,
                            child: Text(c,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                          ))
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Khối tải ảnh
          InkWell(
            onTap: _submitting ? null : _pickImage,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                color: const Color(0xFFFFE3DC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFB03B50),
                  width: 1.5,
                ),
              ),
              child: _imageFile != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.file(_imageFile!, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Color(0xAA000000),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: _clearImage,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Color(0xAAE53935),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.add_a_photo_outlined,
                          size: 30,
                          color: Color(0xFF9E233A),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _mode == BugReportMode.chunkMissing
                              ? 'Đính kèm ảnh minh họa (Tùy chọn)'
                              : 'Chạm để chọn ảnh chụp màn hình lỗi',
                          style: const TextStyle(
                            color: Color(0xFF9E233A),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _mode == BugReportMode.chunkMissing
                              ? 'Không bắt buộc với báo cáo chunk'
                              : '(Chỉ cấp quyền đọc cho ảnh được chọn)',
                          style: const TextStyle(
                              color: Color(0xFF6B6275), fontSize: 11),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),

          // Ô nhập tên người gửi
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
              hintStyle: const TextStyle(color: Color(0xFF8A7F92)),
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
                borderSide: const BorderSide(color: Color(0xFFB03B50), width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Ô ghi chú / mô tả lỗi
          TextField(
            controller: _descController,
            enabled: !_submitting,
            maxLines: 3,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            cursorColor: Colors.black,
            decoration: InputDecoration(
              labelText: _mode == BugReportMode.chunkMissing
                  ? 'Ghi chú thêm (Tùy chọn)'
                  : 'Mô tả lỗi',
              labelStyle: const TextStyle(
                color: Color(0xFF9E233A),
                fontWeight: FontWeight.w600,
              ),
              hintText: _mode == BugReportMode.chunkMissing
                  ? 'Mô tả ngữ cảnh, nhiệm vụ hoặc đoạn game gặp chunk này...'
                  : 'Vị trí lỗi, câu thoại, thẻ bài hoặc tình huống...',
              hintStyle: const TextStyle(color: Color(0xFF8A7F92)),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 35),
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
                borderSide: const BorderSide(color: Color(0xFFB03B50), width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 16),

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _mode == BugReportMode.chunkMissing
                                ? Icons.send_and_archive_rounded
                                : Icons.send_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _mode == BugReportMode.chunkMissing
                                ? 'Gửi Cho Nhóm Dịch'
                                : 'Gửi Báo Cáo',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      );
}
