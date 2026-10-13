import 'package:flutter/material.dart';

import '../services/patch_service.dart';
import 'czn_theme.dart';

class AppUpdateCard extends StatelessWidget {
  const AppUpdateCard({
    super.key,
    required this.currentVersion,
    required this.update,
    required this.checking,
    required this.updating,
    required this.pending,
    required this.message,
    required this.progress,
    required this.onCheck,
    required this.onUpdate,
    required this.onCancel,
  });
  final String currentVersion, message;
  final AppUpdateInfo? update;
  final bool checking, updating, pending;
  final double progress;
  final VoidCallback? onCheck, onUpdate, onCancel;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('app-update-card'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.system_update_alt,
                color: CznColors.red,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cập nhật toàn bộ ứng dụng',
                      style: TextStyle(
                        color: CznColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      update != null
                          ? '$currentVersion → ${update!.version} · ${update!.sizeLabel}'
                          : 'Phiên bản đang dùng: $currentVersion',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              message.isNotEmpty
                  ? message
                  : update != null
                  ? 'Bao gồm giao diện, icon, chức năng và gói đi kèm. Xác nhận cài APK để nhận đầy đủ thay đổi.'
                  : checking
                  ? 'Đang kiểm tra phiên bản mới…'
                  : 'App tự kiểm tra khi mở; khi bật Wi-Fi tự tải, cả APK và bản dịch đều được tải sẵn.',
            ),
          ),
          if (updating) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            if (onCancel != null)
              TextButton(onPressed: onCancel, child: const Text('Hủy tải APK')),
          ] else if (update != null || pending) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('app-update-button'),
              onPressed: onUpdate,
              icon: const Icon(Icons.download_outlined),
              label: Text(
                pending
                    ? 'Tiếp tục cập nhật'
                    : 'Tải và cập nhật ${update!.version}',
              ),
            ),
          ],
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: onCheck,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(checking ? 'Đang kiểm tra…' : 'Kiểm tra cập nhật'),
          ),
        ],
      ),
    ),
  );
}
