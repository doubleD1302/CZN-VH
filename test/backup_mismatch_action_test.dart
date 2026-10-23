import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Backup mismatch detection matches various error strings', () {
    bool isBackupOrSourceMismatch(String msg) {
      final lower = msg.toLowerCase();
      return lower.contains('không khớp nguồn') ||
          lower.contains('backup') ||
          lower.contains('không nhất quán') ||
          lower.contains('còn giữ chunk');
    }

    expect(isBackupOrSourceMismatch('Backup không khớp nguồn: chunks/base_b24_0.ssrc'), isTrue);
    expect(isBackupOrSourceMismatch('Backup không khớp nguồn: chunks/base_b21_0.ssrc'), isTrue);
    expect(isBackupOrSourceMismatch('Game cập nhật còn giữ chunk của bản vá cũ'), isTrue);
    expect(isBackupOrSourceMismatch('Bộ dữ liệu đang cài không nhất quán'), isTrue);
    expect(isBackupOrSourceMismatch('Lỗi kết nối Shizuku timeout'), isFalse);
    expect(isBackupOrSourceMismatch('Thành công'), isFalse);
  });
}
