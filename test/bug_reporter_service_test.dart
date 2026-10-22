import 'dart:convert';
import 'dart:io';

import 'package:czn_patcher/services/bug_reporter_service.dart';
import 'package:czn_patcher/ui/bug_report_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'last_bug_reporter_name': 'Thuyền Trưởng Test',
    });
  });

  group('BugReporterService Chunk & Image Reporting Tests', () {
    test('submitChunkReport sends required title and metadata', () async {
      String? interceptedBody;

      final mockClient = MockClient((request) async {
        interceptedBody = request.body;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'message': 'Đã lưu báo lỗi thành công',
            'report_id': 'req_test_123',
            'row_number': 15,
            'is_duplicate': false,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await BugReporterService.submitChunkReport(
        chunkName: 'base_b08_0.ssrc',
        senderName: 'Captain Test',
        userNotes: 'Phần tin nhắn Messenger bị sót tiếng Hàn',
        metadata: {
          'game_version': '1.0.837',
          'game_package': 'com.smilegate.chaoszero.stove.google',
          'related_slots': ['db/story_char_messenger_chat_261021@story.db'],
        },
        requestId: 'req_test_123',
        client: mockClient,
      );

      expect(result.success, isTrue);
      expect(result.reportId, 'req_test_123');
      expect(result.rowNumber, 15);
      expect(result.isDuplicate, isFalse);

      expect(interceptedBody, isNotNull);
      final bodyJson = jsonDecode(interceptedBody!) as Map<String, dynamic>;
      expect(bodyJson['report_type'], 'missing_translation');
      expect(bodyJson['chunk_name'], 'base_b08_0.ssrc');
      expect(bodyJson['sender'], 'Captain Test');
      expect(
        (bodyJson['description'] as String).startsWith(
          'Chunk base_b08_0.ssrc chưa được dịch',
        ),
        isTrue,
      );
      expect(bodyJson['metadata']['game_version'], '1.0.837');
    });

    test('submitChunkReport handles duplicate receipt gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'message': 'Báo cáo này đã được ghi nhận trước đó (Idempotent).',
            'report_id': 'req_dup_001',
            'row_number': 8,
            'is_duplicate': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await BugReporterService.submitChunkReport(
        chunkName: 'base_b03_0.ssrc',
        senderName: 'Captain A',
        requestId: 'req_dup_001',
        client: mockClient,
      );

      expect(result.success, isTrue);
      expect(result.isDuplicate, isTrue);
      expect(result.rowNumber, 8);
    });

    test('submitChunkReport rejects empty chunk name without sending request',
        () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response('{}', 200);
      });

      final result = await BugReporterService.submitChunkReport(
        chunkName: '   ',
        senderName: 'Captain',
        client: mockClient,
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'EMPTY_CHUNK_NAME');
      expect(requestCount, 0);
    });

    test('submitChunkReport rejects HTML login/error responses', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          '<!DOCTYPE html><html><head><title>Google Accounts</title></head><body>Sign in</body></html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      final result = await BugReporterService.submitChunkReport(
        chunkName: 'base_b08_0.ssrc',
        senderName: 'Captain',
        client: mockClient,
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'HTML_RESPONSE');
    });

    test('submitChunkReport rejects server error responses', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'status': 'error', 'message': 'Sheet quota exceeded'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await BugReporterService.submitChunkReport(
        chunkName: 'base_b08_0.ssrc',
        senderName: 'Captain',
        client: mockClient,
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'SERVER_ERROR');
      expect(result.message, 'Sheet quota exceeded');
    });

    test('submitBugReport returns error when image does not exist', () async {
      final result = await BugReporterService.submitBugReport(
        imageFile: File('non_existent_file.jpg'),
        senderName: 'Captain',
        description: 'Lỗi',
      );

      expect(result.success, isFalse);
      expect(result.errorCode, 'IMAGE_NOT_FOUND');
    });

    testWidgets('BugReportDialog in Chunk Mode renders required title',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BugReportDialog.forChunk(chunkName: 'base_b08_0.ssrc'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Báo Cho Nhóm Dịch'), findsOneWidget);
      expect(
        find.text('Chunk base_b08_0.ssrc chưa được dịch'),
        findsOneWidget,
      );
      expect(find.text('Thuyền Trưởng Test'), findsOneWidget);
      expect(find.text('Đính kèm ảnh minh họa (Tùy chọn)'), findsOneWidget);
      expect(find.text('Gửi Cho Nhóm Dịch'), findsOneWidget);
    });
  });
}
