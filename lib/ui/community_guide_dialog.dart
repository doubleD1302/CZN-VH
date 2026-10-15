import 'package:flutter/material.dart';

class CommunityGuideDialog extends StatelessWidget {
  const CommunityGuideDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF161526),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8C170), width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF28233D),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      color: Color(0xFFE8C170),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HƯỚNG DẪN CÀI ĐẶT & SỬ DỤNG',
                          style: TextStyle(
                            fontFamily: 'CznDisplay',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFAF7EE),
                          ),
                        ),
                        Text(
                          'Dành cho cộng đồng người chơi Chaos Zero Nightmare',
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
              const Divider(color: Color(0xFF332D4E), height: 24),
              Expanded(
                child: ListView(
                  children: [
                    _buildStepCard(
                      stepNumber: '1',
                      title: 'Chuẩn bị trước khi cài',
                      description:
                          '• Hãy đảm bảo bạn đã đóng game CZN hoàn toàn.\n'
                          '• Bộ cài sẽ tự động tìm thư mục game (mặc định tại C:\\ProgramData\\Smilegate\\Games\\ChaosZeroNightmare).\n'
                          '• Nếu bạn cài game ở ổ đĩa khác, hãy bấm "Chọn thư mục" trong mục Thiết lập.',
                      icon: Icons.check_circle_outline,
                    ),
                    const SizedBox(height: 12),
                    _buildStepCard(
                      stepNumber: '2',
                      title: 'Cài đặt Tiếng Việt',
                      description:
                          '• Bấm nút lớn [ CÀI TIẾNG VIỆT ] ngay màn hình chính.\n'
                          '• Quá trình chỉ mất vài giây. File gốc sẽ được tự động sao lưu an toàn 100% để bạn có thể khôi phục bất cứ lúc nào.',
                      icon: Icons.download_done_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildStepCard(
                      stepNumber: '3',
                      title: 'Kích hoạt Tiếng Việt trong Game',
                      description:
                          '• Khởi động game qua STOVE hoặc bấm [ Mở CZN ].\n'
                          '• Vào Cài đặt (Settings ⚙️) góc phải màn hình game.\n'
                          '• Tại mục Ngôn ngữ văn bản (Text Language) -> Chọn 日本語 (Tiếng Nhật).\n'
                          '• Toàn bộ hội thoại, thẻ bài, kỹ năng, vật phẩm và cốt truyện sẽ hiển thị bằng Tiếng Việt mượt mà!',
                      highlight: true,
                      icon: Icons.translate_rounded,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'CÂU HỎI THƯỜNG GẶP (FAQ)',
                      style: TextStyle(
                        fontFamily: 'CznDisplay',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE8C170),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildFaqItem(
                      question: 'Tại sao lại chọn tiếng Nhật để có tiếng Việt?',
                      answer:
                          'Game CZN chưa có nút chọn Tiếng Việt riêng. Bản patch thay thế an toàn vào gói ngôn ngữ tiếng Nhật để game nạp font chữ chuẩn và không bị lỗi vỡ chữ hay crash.',
                    ),
                    _buildFaqItem(
                      question: 'Có bị khóa tài khoản (ban acc) không?',
                      answer:
                          'Hoàn toàn không. Bản dịch chỉ can thiệp vào các tệp dữ liệu văn bản hiển thị cục bộ, tuyệt đối không chỉnh sửa mã nguồn game, không sửa file .exe/.dll và không can thiệp gameplay.',
                    ),
                    _buildFaqItem(
                      question: 'Game cập nhật qua STOVE xong bị mất tiếng Việt?',
                      answer:
                          'Khi STOVE cập nhật, nó sẽ tải lại tệp tiếng Nhật gốc của Smilegate. Lúc này bạn chỉ cần mở lại launcher này và bấm [ Cài tiếng Việt ] một lần nữa là xong ngay!',
                    ),
                    _buildFaqItem(
                      question: 'Khôi phục bản gốc như thế nào?',
                      answer:
                          'Vào mục Thiết lập -> Bấm [ Khôi phục bản gốc ]. Game sẽ quay trở về nguyên bản tiếng Nhật gốc 100% như lúc chưa cài.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE8C170),
                    foregroundColor: const Color(0xFF1A1528),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Đã hiểu',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required String stepNumber,
    required String title,
    required String description,
    required IconData icon,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFF241E38) : const Color(0xFF1E1A2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight ? const Color(0xFFE8C170) : const Color(0xFF332D4E),
          width: highlight ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlight ? const Color(0xFFE8C170) : const Color(0xFF3B3356),
            ),
            alignment: Alignment.center,
            child: Text(
              stepNumber,
              style: TextStyle(
                fontFamily: 'CznDisplay',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: highlight ? const Color(0xFF1A1528) : const Color(0xFFFAF7EE),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: highlight ? const Color(0xFFE8C170) : const Color(0xFFFAF7EE),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'CznDisplay',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: highlight ? const Color(0xFFE8C170) : const Color(0xFFFAF7EE),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    fontFamily: 'CznSans',
                    fontSize: 12.5,
                    height: 1.45,
                    color: Color(0xFFD6D1E8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqItem({required String question, required String answer}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1B172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2C2642)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.help_outline, size: 16, color: Color(0xFFE8C170)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    question,
                    style: const TextStyle(
                      fontFamily: 'CznSans',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFAF7EE),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              answer,
              style: const TextStyle(
                fontFamily: 'CznSans',
                fontSize: 12,
                height: 1.4,
                color: Color(0xFFB5B0CD),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
