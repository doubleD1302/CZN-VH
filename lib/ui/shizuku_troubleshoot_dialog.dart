import 'package:flutter/material.dart';

import '../services/native_bridge.dart';

class ShizukuTroubleshootDialog extends StatelessWidget {
  const ShizukuTroubleshootDialog({
    super.key,
    this.onCopyReport,
  });

  final Future<bool> Function()? onCopyReport;

  static Future<void> show(
    BuildContext context, {
    Future<bool> Function()? onCopyReport,
  }) =>
      showDialog<void>(
        context: context,
        builder: (_) => ShizukuTroubleshootDialog(onCopyReport: onCopyReport),
      );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF161526),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8C170), width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF28233D),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.build_circle_outlined,
                      color: Color(0xFFE8C170),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HƯỚNG DẪN SỬA LỖI KẾT NỐI',
                          style: TextStyle(
                            fontFamily: 'CznDisplay',
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFAF7EE),
                          ),
                        ),
                        Text(
                          'Khắc phục lỗi "Kết nối chưa hoàn tất" & Shizuku bị treo',
                          style: TextStyle(
                            fontFamily: 'CznSans',
                            fontSize: 12,
                            color: Color(0xFFB5B0CD),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFFB5B0CD)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF332D4E), height: 20),

              // Scrollable instructions
              Expanded(
                child: ListView(
                  children: [
                    // Xiaomi Callout Warning
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B1D16),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF58220), width: 1),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Color(0xFFF58220), size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Đặc biệt lưu ý cho máy Xiaomi / POCO / Redmi (HyperOS / MIUI):\n'
                              'Hệ điều hành thường chặn tiến trình nền Shizuku nếu chưa bật cài đặt bảo mật.',
                              style: TextStyle(
                                fontFamily: 'CznSans',
                                fontSize: 12,
                                height: 1.35,
                                color: Color(0xFFFFD1A9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Step 1
                    _buildStep(
                      stepNumber: '1',
                      title: 'Khởi động lại dịch vụ Shizuku (Khắc phục 80%)',
                      content:
                          '• Mở ứng dụng Shizuku, cuộn xuống dưới chọn [ Dừng ] (Stop).\n'
                          '• Bấm [ Khởi động ] (Start) lại qua Ghép nối không dây (Wireless Debugging).\n'
                          '• Vào mục "Ứng dụng được phép" trong Shizuku -> Gạt Tắt rồi Bật lại cho CZN Việt Hóa.\n'
                          '• Quay lại app CZN và bấm thử lại.',
                      icon: Icons.refresh_rounded,
                      highlight: true,
                    ),
                    const SizedBox(height: 12),

                    // Step 2
                    _buildStep(
                      stepNumber: '2',
                      title: 'Cài đặt bắt buộc cho Xiaomi / HyperOS / MIUI',
                      content:
                          '• Vào Cài đặt điện thoại -> Cài đặt bổ sung -> Tùy chọn nhà phát triển:\n'
                          '   + Bật: "Gỡ lỗi USB (Cài đặt bảo mật)" [Bắt buộc]\n'
                          '   + Đảm bảo "Gỡ lỗi không dây" đang bật.\n'
                          '• Tắt hạn chế pin (tránh Xiaomi ngắt kết nối ngầm):\n'
                          '   + Giữ icon app Shizuku -> Thông tin ứng dụng -> Tiết kiệm pin -> Chọn "Không hạn chế".\n'
                          '   + Bật "Tự khởi chạy" (Autostart) cho Shizuku.\n'
                          '   + Làm tương tự cho app CZN Việt Hóa.',
                      icon: Icons.phonelink_setup_rounded,
                    ),
                    const SizedBox(height: 12),

                    // Step 3
                    _buildStep(
                      stepNumber: '3',
                      title: 'Khởi động lại điện thoại (Nếu vẫn chưa được)',
                      content:
                          '• Khởi động lại máy (Restart điện thoại).\n'
                          '• Kết nối lại Wi-Fi và mở Shizuku bấm Khởi động lại một lần nữa.',
                      icon: Icons.restart_alt_rounded,
                    ),
                  ],
                ),
              ),

              const Divider(color: Color(0xFF332D4E), height: 20),

              // Actions
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE8C170),
                      side: const BorderSide(color: Color(0xFFE8C170)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Mở Shizuku', style: TextStyle(fontFamily: 'CznSans', fontSize: 13)),
                    onPressed: () async {
                      await NativeBridge.action('openShizuku');
                    },
                  ),
                  if (onCopyReport != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB5B0CD),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Sao chép báo cáo lỗi', style: TextStyle(fontFamily: 'CznSans', fontSize: 13)),
                      onPressed: () async {
                        final success = await onCopyReport!();
                        if (success && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã copy mã lỗi và báo cáo.')),
                          );
                        }
                      },
                    ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE8C170),
                      foregroundColor: const Color(0xFF161526),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Đã hiểu', style: TextStyle(fontFamily: 'CznSans', fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep({
    required String stepNumber,
    required String title,
    required String content,
    required IconData icon,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFF1E1B33) : const Color(0xFF1B192E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? const Color(0xFFE8C170).withValues(alpha: 0.6) : const Color(0xFF332D4E),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: highlight ? const Color(0xFFE8C170) : const Color(0xFF28233D),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  stepNumber,
                  style: TextStyle(
                    fontFamily: 'CznDisplay',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: highlight ? const Color(0xFF161526) : const Color(0xFFE8C170),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'CznDisplay',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFAF7EE),
                  ),
                ),
              ),
              Icon(icon, color: const Color(0xFFE8C170), size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontFamily: 'CznSans',
              fontSize: 12.5,
              height: 1.45,
              color: Color(0xFFB5B0CD),
            ),
          ),
        ],
      ),
    );
  }
}
