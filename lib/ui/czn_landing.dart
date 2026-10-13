import 'package:flutter/material.dart';

import 'czn_glass.dart';
import 'czn_theme.dart';

/// Transparent controls over the shared full-screen artwork.
class CznLanding extends StatelessWidget {
  const CznLanding({
    super.key,
    required this.patchVersion,
    required this.appVersion,
    required this.access,
    required this.ready,
    required this.installed,
    required this.busy,
    required this.checking,
    required this.message,
    this.showMessage = false,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onSetup,
    required this.onUpdates,
    required this.onHelp,
    this.onSettings,
    this.onNotice,
  });
  final String patchVersion, appVersion, message, primaryLabel;
  final bool access, ready, installed, busy, checking, showMessage;
  final VoidCallback? onPrimary,
      onSetup,
      onUpdates,
      onHelp,
      onSettings,
      onNotice;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, bounds) {
        final landscape = bounds.maxWidth > bounds.maxHeight;
        final compact = bounds.maxHeight < 700 || landscape;
        final header = Tooltip(
          message: 'Chaos Zero Nightmare Việt Hóa · Ứng dụng $appVersion',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const CznGameLogo(showVietnamese: false),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Bản dịch $patchVersion',
                  style: const TextStyle(
                    color: glassIvory,
                    fontSize: 10,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ),
            ],
          ),
        );
        final utilities = [
          CznGlassUtility(
            key: const Key('open-setup'),
            label: 'Thiết lập',
            icon: Icons.settings_outlined,
            onPressed: onSetup,
            compact: compact,
          ),
          CznGlassUtility(
            key: const Key('open-updates'),
            label: 'Cập nhật',
            icon: Icons.notifications_none,
            onPressed: onUpdates,
            compact: compact,
          ),
          CznGlassUtility(
            key: const Key('open-help'),
            label: 'Trợ giúp',
            icon: Icons.help_outline,
            onPressed: onHelp,
            compact: compact,
          ),
        ];
        final status = busy || checking
            ? 'Đang xử lý…'
            : installed
            ? 'Đã cài tiếng Việt'
            : !access
            ? 'Chưa kết nối Shizuku'
            : !ready
            ? 'Chưa có dữ liệu game'
            : 'Sẵn sàng';
        final statusLine = Semantics(
          liveRegion: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: access && ready ? CznColors.green : CznColors.amber,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: glassIvory,
                    fontSize: 11,
                    shadows: [Shadow(color: Colors.black, blurRadius: 5)],
                  ),
                ),
              ),
            ],
          ),
        );
        final primary = CznGlassPrimary(
          key: const Key('landing-primary'),
          label: primaryLabel,
          onPressed: onPrimary,
          compact: compact,
        );
        final information = busy || checking || showMessage
            ? Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xCC171524),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: glassIvory.withValues(alpha: .45),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy || checking) const LinearProgressIndicator(),
                      Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: glassIvory, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink();
        final topActions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CznGlassIcon(
              tooltip: 'Thông báo cộng đồng',
              icon: Icons.notifications_none,
              onPressed: onNotice,
            ),
            CznGlassIcon(
              tooltip: 'Cài đặt',
              icon: Icons.settings_outlined,
              onPressed: onSettings,
            ),
          ],
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(
            landscape ? 20 : 14,
            8,
            landscape ? 20 : 14,
            compact ? 0 : 18,
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 230),
                          child: header,
                        ),
                      ),
                    ),
                    topActions,
                  ],
                ),
              ),
              if (landscape) ...[
                Positioned(
                  left: 0,
                  bottom: 0,
                  width: bounds.maxWidth * .42,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      information,
                      primary,
                      const SizedBox(height: 8),
                      statusLine,
                    ],
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  width: bounds.maxWidth * .50,
                  child: Row(
                    children: [
                      for (final utility in utilities) Expanded(child: utility),
                    ],
                  ),
                ),
              ] else
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    key: const Key('landing-controls'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      information,
                      primary,
                      SizedBox(height: compact ? 6 : 16),
                      Row(
                        children: [
                          for (final utility in utilities)
                            Expanded(child: utility),
                        ],
                      ),
                      SizedBox(height: compact ? 4 : 13),
                      statusLine,
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
