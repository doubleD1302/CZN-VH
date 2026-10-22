import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class BugReportResult {
  final bool success;
  final String? reportId;
  final int? rowNumber;
  final String? fileId;
  final bool isDuplicate;
  final String message;
  final String? errorCode;

  const BugReportResult({
    required this.success,
    this.reportId,
    this.rowNumber,
    this.fileId,
    this.isDuplicate = false,
    required this.message,
    this.errorCode,
  });

  @override
  String toString() =>
      'BugReportResult(success: $success, reportId: $reportId, isDuplicate: $isDuplicate, message: $message)';
}

class BugReporterService {
  // Web App URL từ Google Apps Script
  static const String scriptUrl =
      'https://script.google.com/macros/s/AKfycbxjOzLxoLuA5HMLmPsQEdbOs0o52w1GFa97wmV4ET4ZCuyyGs-PMAlYsZqv3esMgH0u/exec';

  /// 1. Gửi báo lỗi ảnh chụp màn hình truyền thống
  static Future<BugReportResult> submitBugReport({
    required File imageFile,
    required String senderName,
    required String description,
    String? requestId,
    http.Client? client,
  }) async {
    try {
      if (!await imageFile.exists()) {
        return const BugReportResult(
          success: false,
          message: 'Tệp ảnh chụp màn hình không tồn tại.',
          errorCode: 'IMAGE_NOT_FOUND',
        );
      }
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final reqId = requestId ??
          'img_${DateTime.now().millisecondsSinceEpoch}_${base64Image.length}';

      final body = {
        'report_type': 'image_bug',
        'sender': senderName.trim().isEmpty
            ? 'Thuyền Trưởng Ẩn Danh'
            : senderName.trim(),
        'description': description.trim(),
        'image_base64': base64Image,
        'request_id': reqId,
      };

      return await _sendPost(body, client: client);
    } catch (e) {
      return BugReportResult(
        success: false,
        message: 'Lỗi chuẩn bị báo cáo: $e',
        errorCode: 'CLIENT_ERROR',
      );
    }
  }

  /// 2. Gửi báo cáo "Chunk chưa được dịch" cho nhóm dịch
  static Future<BugReportResult> submitChunkReport({
    required String chunkName,
    required String senderName,
    String? userNotes,
    File? optionalImageFile,
    Map<String, dynamic>? metadata,
    String? requestId,
    http.Client? client,
  }) async {
    try {
      final cleanChunk = chunkName.trim();
      if (cleanChunk.isEmpty) {
        return const BugReportResult(
          success: false,
          message: 'Tên file chunk không được để trống.',
          errorCode: 'EMPTY_CHUNK_NAME',
        );
      }

      final cleanSender = senderName.trim().isEmpty
          ? 'Thuyền Trưởng Ẩn Danh'
          : senderName.trim();

      // Tiêu đề bắt buộc chính xác: "Chunk <tên_file_chunk> chưa được dịch"
      final requiredTitle = 'Chunk $cleanChunk chưa được dịch';
      final fullDesc = userNotes != null && userNotes.trim().isNotEmpty
          ? '$requiredTitle\n\n${userNotes.trim()}'
          : requiredTitle;

      String? base64Image;
      if (optionalImageFile != null && await optionalImageFile.exists()) {
        final bytes = await optionalImageFile.readAsBytes();
        base64Image = base64Encode(bytes);
      }

      final reqId = requestId ??
          'chunk_${DateTime.now().millisecondsSinceEpoch}_${cleanChunk.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}';

      final body = {
        'report_type': 'missing_translation',
        'sender': cleanSender,
        'description': fullDesc,
        'chunk_name': cleanChunk,
        // ignore: use_null_aware_elements
        if (base64Image != null) 'image_base64': base64Image,
        'request_id': reqId,
        'metadata': metadata ?? {},
      };

      return await _sendPost(body, client: client);
    } catch (e) {
      return BugReportResult(
        success: false,
        message: 'Lỗi chuẩn bị báo cáo chunk: $e',
        errorCode: 'CLIENT_ERROR',
      );
    }
  }

  /// Helper thực hiện POST và xác thực phản hồi JSON có cấu trúc
  static Future<BugReportResult> _sendPost(
    Map<String, dynamic> body, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final uri = Uri.parse(scriptUrl);
      final response = await httpClient
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 35));

      final resBody = response.body.trim();
      if (resBody.isEmpty) {
        return const BugReportResult(
          success: false,
          message: 'Server không phản hồi dữ liệu (Body rỗng).',
          errorCode: 'EMPTY_BODY',
        );
      }

      if (resBody.startsWith('<') || resBody.toLowerCase().contains('<html')) {
        return const BugReportResult(
          success: false,
          message:
              'Server trả về trang HTML thay vì JSON (yêu cầu đăng nhập hoặc lỗi máy chủ).',
          errorCode: 'HTML_RESPONSE',
        );
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(resBody) as Map<String, dynamic>;
      } catch (e) {
        return BugReportResult(
          success: false,
          message: 'Không thể giải mã phản hồi JSON từ server: $e',
          errorCode: 'JSON_PARSE_ERROR',
        );
      }

      if (data['status'] == 'success') {
        return BugReportResult(
          success: true,
          reportId: data['report_id'] as String?,
          rowNumber: data['row_number'] is int
              ? data['row_number'] as int
              : int.tryParse(data['row_number']?.toString() ?? ''),
          fileId: data['file_id'] as String?,
          isDuplicate: data['is_duplicate'] == true,
          message: data['message'] as String? ?? 'Thành công',
        );
      } else {
        return BugReportResult(
          success: false,
          message: data['message'] as String? ?? 'Lỗi không xác định từ server',
          errorCode: 'SERVER_ERROR',
        );
      }
    } on TimeoutException {
      return const BugReportResult(
        success: false,
        message:
            'Kết nối tới máy chủ quá hạn (Timeout). Yêu cầu có thể đã được tiếp nhận, vui lòng thử lại nếu cần.',
        errorCode: 'TIMEOUT',
      );
    } catch (e) {
      return BugReportResult(
        success: false,
        message: 'Lỗi gửi báo cáo: $e',
        errorCode: 'NETWORK_ERROR',
      );
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// 3. Lấy danh sách Bảng Vinh Danh (Hall of Fame) hiển thị trong App
  static Future<List<Map<String, dynamic>>> fetchHallOfFame({
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(Uri.parse('$scriptUrl?mode=leaderboard'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['leaderboard'] ?? []);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Lỗi tải Bảng Vinh Danh: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
    return [];
  }
}
