import 'package:flutter/material.dart';

import '../services/native_bridge.dart';

class LocalAdbDialog extends StatefulWidget {
  const LocalAdbDialog({
    super.key,
    this.onConnected,
  });

  final VoidCallback? onConnected;

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onConnected,
  }) =>
      showDialog<void>(
        context: context,
        builder: (_) => LocalAdbDialog(onConnected: onConnected),
      );

  @override
  State<LocalAdbDialog> createState() => _LocalAdbDialogState();
}

class _LocalAdbDialogState extends State<LocalAdbDialog> {
  final _hostController = TextEditingController();
  final _connectPortController = TextEditingController();
  final _pairingPortController = TextEditingController();
  final _pairingCodeController = TextEditingController();
  bool _firstTimePairing = true;
  bool _loading = false;
  String? _statusError;

  @override
  void initState() {
    super.initState();
    _connectPortController.addListener(_onPortChanged);
    _pairingPortController.addListener(_onPortChanged);
    NativeBridge.getWifiIp().then((ip) {
      if (mounted && ip != null && ip.trim().isNotEmpty) {
        setState(() {
          _hostController.text = ip.trim();
        });
      }
    });
  }

  void _onPortChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _connectPortController.removeListener(_onPortChanged);
    _pairingPortController.removeListener(_onPortChanged);
    _hostController.dispose();
    _connectPortController.dispose();
    _pairingPortController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }

  bool get _isSamePort {
    if (!_firstTimePairing) return false;
    final conn = _connectPortController.text.trim();
    final pair = _pairingPortController.text.trim();
    return conn.isNotEmpty && pair.isNotEmpty && conn == pair;
  }

  Future<void> _openSettings() async {
    final ok = await NativeBridge.openDevSettings();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng mở Cài đặt máy -> Tùy chọn nhà phát triển.'),
        ),
      );
    }
  }

  String _formatFriendlyError(dynamic e, int connPort, int pairPort) {
    final raw = e.toString();

    // Check if error is from pairing
    if (raw.contains('PAIR_FAILED') || raw.contains('pairLocalAdb')) {
      if (raw.contains('ECONNREFUSED') || raw.contains('Connection refused')) {
        return '❌ KHÔNG THỂ GHÉP NỐI (Cổng $pairPort bị từ chối kết nối)\n\n'
            '🔍 NGUYÊN NHÂN THƯỜNG GẶP:\n'
            '1. Hộp thoại mã 6 số đã bị tắt: Khi chuyển app, Android tự động đóng pop-up và hủy luôn cổng ghép nối.\n'
            '2. Nhập nhầm Cổng ghép nối: Bạn có thể đã lấy nhầm Cổng kết nối ở màn hình chính. Cổng ghép nối nằm BÊN TRONG hộp thoại pop-up có mã 6 số (thường có 5 số khác hẳn).\n\n'
            '💡 CÁCH KHẮC PHỤC CHUẨN:\n'
            '• Bước 1: Mở Cài đặt ➔ Bấm lại "Ghép nối thiết bị bằng mã ghép nối" để mở lại pop-up mới.\n'
            '• Bước 2: Dùng chế độ "Cửa sổ nổi" (Floating Window) hoặc "Chia đôi màn hình" để hộp thoại mã trên Cài đặt không bị tắt khi nhập vào CZN.\n'
            '• Bước 3: Nhập đúng 5 số cổng và mã 6 số mới hiển thị trong pop-up.';
      }
      if (raw.contains('ETIMEDOUT') || raw.contains('timed out') || raw.contains('Timeout')) {
        return '❌ HẾT THỜI GIAN GHÉP NỐI (Cổng $pairPort)\n\n'
            '💡 Vui lòng kiểm tra kết nối Wi-Fi, mở lại hộp thoại "Ghép nối bằng mã ghép nối" trong Cài đặt và thử lại.';
      }
      return '❌ GHÉP NỐI THẤT BẠI\n\n'
          '🔍 Mã ghép nối không đúng, hết hạn, hoặc bị từ chối kết nối.\n'
          '💡 Vui lòng mở lại hộp thoại "Ghép nối bằng mã ghép nối" để lấy mã 6 số và cổng ghép nối mới nhất.\n\n'
          '⚠️ Chi tiết lỗi hệ thống:\n$raw';
    }

    // Check if error is from connection
    if (raw.contains('CONNECT_FAILED') || raw.contains('connectLocalAdb')) {
      if (raw.contains('ECONNREFUSED') || raw.contains('Connection refused')) {
        return '❌ KHÔNG THỂ KẾT NỐI (Cổng $connPort không phản hồi)\n\n'
            '🔍 NGUYÊN NHÂN:\n'
            '• Tính năng "Gỡ lỗi không dây" đã bị tắt hoặc số cổng đã thay đổi khi khởi động lại.\n'
            '• Thiết bị vừa bị ngắt hoặc đổi kết nối Wi-Fi.\n\n'
            '💡 CÁCH KHẮC PHỤC:\n'
            '• Vào Cài đặt ➔ Kiểm tra xem công tắc "Gỡ lỗi không dây" còn BẬT không.\n'
            '• Xem lại 5 số cuối của "Địa chỉ IP và Cổng" ở màn hình chính và nhập lại.';
      }
      return '❌ KẾT NỐI LOCAL ADB THẤT BẠI (Cổng $connPort)\n\n'
          '💡 Vui lòng kiểm tra lại tính năng "Gỡ lỗi không dây" trong Cài đặt và đảm bảo điện thoại đang kết nối Wi-Fi.';
    }

    if (raw.startsWith('Exception: ')) {
      return raw.substring(11);
    }
    return raw;
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _statusError = null;
    });

    int connPort = 0;
    int pairPort = 0;
    final host = _hostController.text.trim().isEmpty ? null : _hostController.text.trim();

    try {
      connPort = int.tryParse(_connectPortController.text.trim()) ?? 0;
      if (connPort <= 0 || connPort > 65535) {
        throw Exception('Cổng kết nối không hợp lệ (1 - 65535). Hãy xem 5 số cuối của dòng "Địa chỉ IP và Cổng" ở màn hình chính.');
      }

      if (_firstTimePairing) {
        pairPort = int.tryParse(_pairingPortController.text.trim()) ?? 0;
        final code = _pairingCodeController.text.trim();
        if (pairPort <= 0 || pairPort > 65535) {
          throw Exception('Cổng ghép nối không hợp lệ (1 - 65535). Hãy xem 5 số cuối trong hộp thoại pop-up có mã 6 số.');
        }
        if (code.length < 6) {
          throw Exception('Mã ghép nối phải gồm 6 chữ số (xem trong hộp thoại pop-up).');
        }

        if (connPort == pairPort) {
          throw Exception(
            'Cổng kết nối ($connPort) và Cổng ghép nối ($pairPort) không được trùng nhau!\n\n'
            '• Cổng kết nối: Nằm ở màn hình chính Gỡ lỗi không dây.\n'
            '• Cổng ghép nối: Nằm BÊN TRONG hộp thoại pop-up có mã 6 số.\n'
            'Vui lòng mở lại hộp thoại pop-up để lấy đúng Cổng ghép nối riêng biệt.',
          );
        }

        final paired = await NativeBridge.pairLocalAdb(pairPort, code, host: host);
        if (!paired) {
          throw Exception('Ghép nối thất bại. Hãy kiểm tra lại Cổng ghép nối và Mã 6 số.');
        }
      }

      final connected = await NativeBridge.connectLocalAdb(connPort, host: host);
      if (!connected) {
        throw Exception('Kết nối thất bại. Hãy kiểm tra lại Cổng kết nối ($connPort).');
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onConnected?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF1E3A2F),
            content: Text('Đã kết nối Local ADB thành công!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusError = _formatFriendlyError(e, connPort, pairPort);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF161526),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8C170), width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(18),
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
                      Icons.cell_tower,
                      color: Color(0xFFE8C170),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'KẾT NỐI LOCAL ADB',
                          style: TextStyle(
                            fontFamily: 'CznDisplay',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFAF7EE),
                          ),
                        ),
                        Text(
                          'Gỡ lỗi không dây — Hoạt động độc lập, không cần Shizuku',
                          style: TextStyle(
                            fontFamily: 'CznSans',
                            fontSize: 11,
                            color: Color(0xFFB5B0CD),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFFB5B0CD), size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF332D4E), height: 16),

              // Scrollable content
              Expanded(
                child: ListView(
                  children: [
                    // Step 1: Open settings button
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE8C170),
                        side: const BorderSide(color: Color(0xFFE8C170)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('1. Mở Cài đặt / Tùy chọn nhà phát triển'),
                    ),
                    const SizedBox(height: 10),

                    // Instruction steps with visual examples
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1B2E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF332D4E)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.menu_book, color: Color(0xFFE8C170), size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Hướng dẫn lấy Cổng & Mã (chỉ mất 10 giây):',
                                style: TextStyle(
                                  color: Color(0xFFE8C170),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Step 1 bullet
                          const Text(
                            '1️⃣ Bật "Gỡ lỗi không dây" (Wireless debugging) và bấm vào dòng chữ để vào trang chi tiết.',
                            style: TextStyle(color: Color(0xFFFAF7EE), fontSize: 11.5, height: 1.35),
                          ),
                          const SizedBox(height: 6),

                          // Step 2 with visual card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161424),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF4A4468)),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '2️⃣ Cổng kết nối (Màn hình chính):',
                                  style: TextStyle(color: Color(0xFF93C5FD), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '• Nhìn dòng "Địa chỉ IP và Cổng": VD 192.168.1.15:45683\n'
                                  '➔ Lấy 5 số cuối (45683) nhập vào ô "Cổng kết nối".',
                                  style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 11, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Step 3 with visual card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161424),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0x80E8C170)),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '3️⃣ Cổng ghép nối & Mã PIN (Trong hộp thoại Pop-up):',
                                  style: TextStyle(color: Color(0xFFFDE68A), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '• Bấm dòng "Ghép nối thiết bị bằng mã ghép nối" để mở pop-up.\n'
                                  '• Mã ghép nối Wi-Fi: VD 982746 ➔ Nhập ô "Mã ghép nối".\n'
                                  '• Địa chỉ IP & Cổng: VD 192.168.1.15:37123 ➔ Nhập 37123 vào ô "Cổng ghép nối" (KHÁC Cổng kết nối!).',
                                  style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 11, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Floating Window Tip
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF142B23),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF10B981)),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.tips_and_updates, color: Color(0xFF34D399), size: 16),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Mẹo quan trọng (Xiaomi / HyperOS / Samsung):\n'
                                    'Khi chuyển đổi app, Android sẽ tự động đóng pop-up mã 6 số khiến cổng bị tắt! Hãy mở app CZN ở dạng "Cửa sổ nổi" (Floating Window) hoặc "Chia đôi màn hình" để hộp thoại mã trên Cài đặt luôn hiển thị khi nhập.',
                                    style: TextStyle(color: Color(0xFFA7F3D0), fontSize: 11, height: 1.35),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Host / IP Address Field
                    TextField(
                      controller: _hostController,
                      keyboardType: TextInputType.text,
                      style: const TextStyle(color: Color(0xFFFAF7EE)),
                      decoration: InputDecoration(
                        labelText: 'Địa chỉ IP thiết bị (Host)',
                        labelStyle: const TextStyle(color: Color(0xFFE8C170)),
                        helperText: 'Tự nhận diện theo Wi-Fi (ví dụ: 192.168.3.105 hoặc 127.0.0.1)',
                        helperStyle: const TextStyle(color: Color(0xFF8E88AB), fontSize: 10.5),
                        hintText: '127.0.0.1',
                        hintStyle: const TextStyle(color: Color(0xFF6B6584)),
                        filled: true,
                        fillColor: const Color(0xFF1E1B2E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF332D4E)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF332D4E)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Connection Port Field
                    TextField(
                      controller: _connectPortController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Color(0xFFFAF7EE)),
                      decoration: InputDecoration(
                        labelText: 'Cổng kết nối (Connect Port)',
                        labelStyle: const TextStyle(color: Color(0xFFE8C170)),
                        helperText: 'Lấy từ màn hình Gỡ lỗi không dây chính (5 số cuối)',
                        helperStyle: const TextStyle(color: Color(0xFF8E88AB), fontSize: 10.5),
                        hintText: 'Ví dụ: 45683',
                        hintStyle: const TextStyle(color: Color(0xFF6B6584)),
                        filled: true,
                        fillColor: const Color(0xFF1E1B2E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF332D4E)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF332D4E)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Checkbox toggle
                    CheckboxListTile(
                      value: _firstTimePairing,
                      onChanged: (val) {
                        setState(() => _firstTimePairing = val ?? true);
                      },
                      title: const Text(
                        'Ghép nối thiết bị (Dành cho lần đầu sử dụng)',
                        style: TextStyle(
                          color: Color(0xFFFAF7EE),
                          fontSize: 13,
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFFE8C170),
                      checkColor: Colors.black,
                    ),

                    if (_firstTimePairing) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pairingPortController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Color(0xFFFAF7EE)),
                              decoration: InputDecoration(
                                labelText: 'Cổng ghép nối',
                                labelStyle: const TextStyle(color: Color(0xFFE8C170)),
                                helperText: '5 số trong pop-up mã',
                                helperStyle: const TextStyle(color: Color(0xFF8E88AB), fontSize: 10.5),
                                hintText: 'Ví dụ: 37123',
                                hintStyle: const TextStyle(color: Color(0xFF6B6584)),
                                filled: true,
                                fillColor: const Color(0xFF1E1B2E),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFF332D4E)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFF332D4E)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _pairingCodeController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Color(0xFFFAF7EE)),
                              decoration: InputDecoration(
                                labelText: 'Mã ghép nối (6 số)',
                                labelStyle: const TextStyle(color: Color(0xFFE8C170)),
                                helperText: 'Mã 6 số trong pop-up',
                                helperStyle: const TextStyle(color: Color(0xFF8E88AB), fontSize: 10.5),
                                hintText: 'Ví dụ: 982746',
                                hintStyle: const TextStyle(color: Color(0xFF6B6584)),
                                filled: true,
                                fillColor: const Color(0xFF1E1B2E),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFF332D4E)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFF332D4E)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Warning banner if same port entered
                      if (_isSamePort)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF33230A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFF59E0B)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Cảnh báo: Bạn đang nhập Cổng ghép nối trùng với Cổng kết nối (${_connectPortController.text.trim()}).\n'
                                  '• Cổng ghép nối nằm TRONG hộp thoại pop-up có mã 6 số (thường là 5 số khác hẳn).\n'
                                  '• Nếu nhập trùng sẽ bị lỗi kết nối bị từ chối (ECONNREFUSED).',
                                  style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 11, height: 1.35),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],

                    // Friendly error banner
                    if (_statusError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E1515),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 18),
                                const SizedBox(width: 8),
                                const Text(
                                  'Thông báo hỗ trợ xử lý lỗi:',
                                  style: TextStyle(
                                    color: Color(0xFFEF4444),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => setState(() => _statusError = null),
                                  child: const Icon(Icons.close, color: Color(0xFFFFB4B4), size: 16),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              _statusError!,
                              style: const TextStyle(
                                color: Color(0xFFFFD4D4),
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 14),
              // Submit button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8C170),
                  foregroundColor: const Color(0xFF161526),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF161526)),
                        ),
                      )
                    : Text(
                        _firstTimePairing ? 'GHÉP NỐI & KẾT NỐI' : 'KẾT NỐI LOCAL ADB',
                        style: const TextStyle(
                          fontFamily: 'CznDisplay',
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

