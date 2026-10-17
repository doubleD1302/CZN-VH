import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class BugReporterService {
  // Web App URL từ Google Apps Script
  static const String scriptUrl =
      'https://script.google.com/macros/s/AKfycbzZikDvENr99MR7b6EWZ02fOSpb_bdNs2chAz-UQ67Dt1ued1H11IIHHBbTkPR8N24l/exec';

  /// 1. Gửi ảnh chụp màn hình + Tên người gửi lên Google Drive & Sheets
  static Future<bool> submitBugReport({
    required File imageFile,
    required String senderName,
    required String description,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse(scriptUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sender': senderName,
          'description': description,
          'image_base64': base64Image,
        }),
      );

      // Google Apps Script thường trả về 200 hoặc Redirect 302 khi POST thành công
      if (response.statusCode == 200 || response.statusCode == 302) {
        return true;
      }
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('Lỗi gửi báo cáo: $e');
      return false;
    }
  }

  /// 2. Lấy danh sách Bảng Vinh Danh (Hall of Fame) hiển thị trong App
  static Future<List<Map<String, dynamic>>> fetchHallOfFame() async {
    try {
      final response = await http.get(Uri.parse('$scriptUrl?mode=leaderboard'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['leaderboard'] ?? []);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Lỗi tải Bảng Vinh Danh: $e');
    }
    return [];
  }
}
