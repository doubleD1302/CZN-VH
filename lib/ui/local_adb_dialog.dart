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
  final _connectPortController = TextEditingController();
  final _pairingPortController = TextEditingController();
  final _pairingCodeController = TextEditingController();
  bool _firstTimePairing = true;
  bool _loading = false;
  String? _statusError;

  @override
  void dispose() {
    _connectPortController.dispose() ;
    _pairingPortController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
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

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _statusError = null;
    });

    try {
      final connPort = int.tryParse(_connectPortController.text.trim()) ?? 0;
      if (connPort <= 0 || connPort > 65535) {
        throw Exception('Cổng kết nối không hợp lệ (1 - 65535).');
      }

      if (_firstTimePairing) {
        final pairPort = int.tryParse(_pairingPortController.text.trim()) ?? 0;
        final code = _pairingCodeController.text.trim();
        if (pairPort <= 0 || pairPort > 65535) {
          throw Exception('Cổng ghép nối không hợp lệ (1 - 65535).');
        }
        if (code.length < 6) {
          throw Exception('Mã ghép nối phải gồm 6 chữ số.');
        }

        final paired = await NativeBridge.pairLocalAdb(pairPort, code);
        if (!paired) {
          throw Exception('Ghép nối thất bại. Hãy kiểm tra lại Cổng và Mã 6 số.');
        }
      }

      final connected = await NativeBridge.connectLocalAdb(connPort);
      if (!connected) {
        throw Exception('Kết nối thất bại. Hãy kiểm tra lại Cổng kết nối.');
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
          _statusError = e.toString().replaceFirst('Exception: ', '');
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 680),
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
                      Icons.cell_tower,
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
                          'KẾT NỐI LOCAL ADB',
                          style: TextStyle(
                            fontFamily: 'CznDisplay',
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFAF7EE),
                          ),
                        ),
                        Text(
                          'Gỡ lỗi không dây — Hoạt động độc lập, không cần Shizuku',
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

              // Scrollable content
              Expanded(
                child: ListView(
                  children: [
                    // Step 1: Open settings button
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE8C170),
                        side: const BorderSide(color: Color(0xFFE8C170)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings, size: 20),
                      label: const Text('1. Mở Tùy chọn nhà phát triển'),
                    ),
                    const SizedBox(height: 12),

                    // Instruction steps
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1B2E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF332D4E)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hướng dẫn thao tác (chỉ mất 10 giây):',
                            style: TextStyle(
                              color: Color(0xFFE8C170),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            '• Bật "Gỡ lỗi không dây" (Wireless debugging).\n'
                            '• Bấm vào dòng chữ để vào mục chi tiết.\n'
                            '• Xem Cổng kết nối (dưới địa chỉ IP, 5 số cuối).\n'
                            '• Nếu ghép lần đầu: bấm "Ghép nối bằng mã ghép nối" để lấy Mã 6 số và Cổng ghép nối.',
                            style: TextStyle(
                              color: Color(0xFFFAF7EE),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Connection Port Field
                    TextField(
                      controller: _connectPortController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Color(0xFFFAF7EE)),
                      decoration: InputDecoration(
                        labelText: 'Cổng kết nối (Connect Port)',
                        labelStyle: const TextStyle(color: Color(0xFFE8C170)),
                        hintText: 'Ví dụ: 41253',
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
                    const SizedBox(height: 12),

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
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pairingPortController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Color(0xFFFAF7EE)),
                              decoration: InputDecoration(
                                labelText: 'Cổng ghép nối',
                                labelStyle: const TextStyle(color: Color(0xFFE8C170)),
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
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _pairingCodeController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Color(0xFFFAF7EE)),
                              decoration: InputDecoration(
                                labelText: 'Mã ghép nối (6 số)',
                                labelStyle: const TextStyle(color: Color(0xFFE8C170)),
                                hintText: 'Ví dụ: 123456',
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
                    ],

                    if (_statusError != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A1A1A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent),
                        ),
                        child: Text(
                          _statusError!,
                          style: const TextStyle(
                            color: Color(0xFFFFB4B4),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),
              // Submit button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8C170),
                  foregroundColor: const Color(0xFF161526),
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
                          fontSize: 14,
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
