import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/windows_patch_service.dart';
import '../services/notice_policy.dart';
import 'companion_dialog.dart';
import 'czn_companion.dart';
import 'czn_landing.dart';
import 'donate_screen.dart';
import 'czn_tools_backdrop.dart';
import 'czn_tools_design.dart';
import 'czn_tools_preferences.dart';
import 'czn_wallpaper.dart';
import 'windows_game_path_dialog.dart';

ThemeData get windowsLauncherTheme => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: 'CznSans',
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFFE0C88F),
    onPrimary: Color(0xFF14171F),
    secondary: Color(0xFF8AD6B0),
    surface: Color(0xFF19212D),
  ),
  scaffoldBackgroundColor: const Color(0xFF10151D),
);

class WindowsHome extends StatefulWidget {
  const WindowsHome({super.key, this.healthToken, this.service});
  final String? healthToken;
  final WindowsPatchService? service;
  @override
  State<WindowsHome> createState() => _WindowsHomeState();
}

class _WindowsHomeState extends State<WindowsHome> with WidgetsBindingObserver {
  late final WindowsPatchService service =
      widget.service ?? WindowsPatchService();
  StreamSubscription<Map<String, dynamic>>? subscription;

  Map<String, dynamic> game = {},
      translation = {},
      channel = {},
      operation = {};
  String gameDir = '',
      message = 'Đang kiểm tra dữ liệu…',
      online = 'Đang kiểm tra cập nhật…';
  bool busy = true, downloading = false, checking = true;
  double progress = 0;
  bool autoUpdate = true;
  bool showCompanion = true;

  // Quản lý modal công cụ 4 tab (Thiết lập, Cập nhật, Thông báo, Cài đặt)
  bool _controlsOpen = false;
  int _toolsTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    subscription = service.progressStream.listen((data) {
      if (mounted) {
        setState(() {
          message = data['label'] as String? ?? message;
          progress = ((data['percent'] as num? ?? 0) / 100).clamp(0, 1);
        });
      }
    });
    unawaited(start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscription?.cancel();
    super.dispose();
  }

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    autoUpdate = prefs.getBool('windows_auto_update') ?? true;
    showCompanion = prefs.getBool('companion_visible') ?? true;

    if (widget.healthToken != null) {
      translation = await service.translationInfo();
      await WidgetsBinding.instance.endOfFrame;
      await service.run('ready', token: widget.healthToken);
    }

    await refresh();

    if (mounted && autoUpdate && widget.healthToken == null) {
      if (hasLauncherUpdate) {
        await perform('update-launcher', download: true);
      } else if (hasDownloadUpdate) {
        await perform('translation', download: true);
      }
    }
    await showNewNotice();
  }

  CommunityNotice? get playerNotice => CommunityNotice.fromChannel(
    channel.containsKey('notice') ? channel : translation,
  );

  Future<void> showNewNotice() async {
    final notice = playerNotice;
    if (!mounted || busy || notice == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('windows_notice_id') == notice.id &&
        (prefs.getInt('windows_notice_until') ?? 0) >
            DateTime.now().millisecondsSinceEpoch) {
      return;
    }
    _openTools(2);
  }

  Future<void> dismissNotice(bool snooze) async {
    final notice = playerNotice;
    if (notice != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('windows_notice_id', notice.id);
      await prefs.setInt(
        'windows_notice_until',
        DateTime.now()
            .add(
              snooze ? const Duration(hours: 24) : const Duration(days: 36500),
            )
            .millisecondsSinceEpoch,
      );
    }
    _closeTools();
  }

  Future<void> refresh() async {
    if (!mounted) return;
    setState(() {
      busy = true;
      checking = true;
    });
    try {
      gameDir = await service.getGameDirectory();
      translation = await service.translationInfo();
      try {
        game = await service.run('status');
      } catch (e) {
        game = {};
        message = clean(e);
      }
      if (game['success'] == true) {
        message = game['message'] as String? ?? 'Sẵn sàng';
      }
      if (mounted) setState(() {});
      try {
        final result = await service.run('check');
        channel = Map<String, dynamic>.from(result['channel'] as Map? ?? {});
        online = hasLauncherUpdate || hasTranslationUpdate
            ? 'Có bản mới đã xác thực. Bạn có thể cập nhật ngay.'
            : 'Đã kiểm tra · Bạn đang dùng phiên bản mới nhất.';
      } catch (e) {
        online = clean(e);
      }
    } catch (e) {
      message = clean(e);
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          checking = false;
        });
      }
    }
  }

  bool get access => service.isValidGameDir(gameDir);
  bool get installed =>
      game['installed'] == true && game['files_match'] == true;
  bool get recovery => game['recovery_required'] == true;
  bool get ready => game['success'] == true && !recovery;

  bool get hasLauncherUpdate =>
      (channel['launcher']?['code'] as int? ?? 0) >
      WindowsPatchService.currentVersionCode;

  bool get hasDownloadUpdate =>
      (channel['translation']?['code'] as int? ?? 0) >
      (translation['code'] as int? ?? 0);

  bool get hasInstallUpdate =>
      installed &&
      (game['installed_code'] is! int ||
          (translation['code'] as int? ?? 0) > (game['installed_code'] as int));

  bool get hasTranslationUpdate => hasDownloadUpdate || hasInstallUpdate;

  String clean(Object e) =>
      e.toString().replaceFirst(RegExp(r'^Exception: '), '');

  Future<bool> perform(String action, {bool download = false}) async {
    if (busy) return false;
    setState(() {
      busy = true;
      downloading = download;
      progress = 0;
      operation = {};
      message = download ? 'Đang kết nối máy chủ…' : 'Đang chuẩn bị…';
    });
    bool success = false;
    try {
      final result = await service.run(action);
      operation = {...result, 'action': action};
      if (result['post_install'] is Map) {
        game = Map<String, dynamic>.from(result['post_install'] as Map);
      }
      message = result['message'] as String? ?? 'Đã hoàn tất.';
      if (action == 'translation') {
        translation = await service.translationInfo();
      }
      success = true;
      if (action == 'update-launcher' &&
          result['state'] == 'restart_required') {
        exit(0);
      }
    } catch (e) {
      message = clean(e);
      operation = {
        'success': false,
        'action': action,
        'phase': 'failed',
        'message': message,
      };
      if (action == 'install' &&
          (message.contains('Tiếng Nhật') ||
              message.contains('lang_ja') ||
              message.contains('gói dữ liệu'))) {
        unawaited(showJapaneseMissingDialog());
      }
      if (action == 'install' || action == 'restore') {
        try {
          game = await service.run('status');
        } catch (_) {
          game = {};
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          downloading = false;
          progress = success ? 1 : 0;
        });
      }
    }
    return success;
  }

  Future<void> oneClick() async {
    if (busy) return;
    if (!access) {
      await openGamePathDialog();
      return;
    }
    if (recovery) {
      await restore();
      return;
    }
    if (installed) {
      if (hasTranslationUpdate) {
        if (hasDownloadUpdate &&
            !await perform('translation', download: true)) {
          return;
        }
        await perform('install');
      } else {
        await service.launchGame();
      }
      return;
    }

    if (!installed &&
        (!service.hasJapanesePackage(gameDir) ||
            game['missing_japanese'] == true)) {
      await showJapaneseMissingDialog();
      return;
    }

    if (hasDownloadUpdate && !await perform('translation', download: true)) {
      return;
    }
    await perform('install');
  }

  Future<void> openGamePathDialog() async {
    if (busy) return;
    final newPath = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          WindowsGamePathDialog(currentPath: gameDir, service: service),
    );
    if (newPath != null && mounted) {
      await refresh();
    }
  }

  Future<void> restore() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161A24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE0C88F), width: 1.5),
        ),
        title: const Text(
          'Khôi phục bản gốc?',
          style: TextStyle(
            color: Color(0xFFF0E6D2),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Hãy đảm bảo game đã đóng hoàn toàn trước khi tiếp tục. '
          'Launcher sẽ kiểm tra bản sao lưu và phục hồi dữ liệu tiếng Nhật gốc.',
          style: TextStyle(color: Color(0xFFC5CDE0), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Hủy',
              style: TextStyle(color: Color(0xFFA8B0BF)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE0C88F),
              foregroundColor: const Color(0xFF14171F),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Khôi phục',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (yes == true) await perform('restore');
  }

  Future<void> showJapaneseMissingDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161A24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE0C88F), width: 1.5),
        ),
        title: Row(
          children: const [
            Icon(
              Icons.info_outline_rounded,
              color: Color(0xFFE0C88F),
              size: 26,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Chưa tải gói Tiếng Nhật',
                style: TextStyle(
                  color: Color(0xFFE0C88F),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bản Việt Hóa cần tệp ngôn ngữ gốc (lang_ja_b01_0.ssrc) để áp dụng bản dịch.\n'
              'Hãy làm theo 3 bước sau để hoàn tất:',
              style: TextStyle(
                color: Color(0xFFC5CDE0),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2430),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '1. Mở game Chaos Zero Nightmare lên (từ STOVE).',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '2. Vào Cài đặt (bánh răng) ➔ Ngôn ngữ ➔ Chọn 日本語 (Tiếng Nhật) để game tải dữ liệu khoảng 1 phút.',
                    style: TextStyle(
                      color: Color(0xFF8AD6B0),
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '3. Tắt hẳn game, sau đó quay lại đây bấm "Cài tiếng Việt".',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE0C88F),
              foregroundColor: const Color(0xFF14171F),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Đã hiểu',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> copyReport() async {
    try {
      await Clipboard.setData(
        ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert({
            'platform': 'windows-x64',
            'launcher_version': WindowsPatchService.currentVersion,
            'launcher_code': WindowsPatchService.currentVersionCode,
            'patch_version': translation['version'] ?? '1.6.11',
            'gameDir': gameDir,
            'game': game,
            'lastOperation': operation,
            'message': message,
            'updateStatus': online,
          }),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void _openTools(int tab) {
    if (!mounted || busy) return;
    setState(() {
      _toolsTab = tab;
      _controlsOpen = true;
    });
  }

  void _closeTools() {
    if (!mounted || busy) return;
    setState(() => _controlsOpen = false);
  }

  void _showCompanionChat() {
    showDialog<void>(
      context: context,
      builder: (_) => CompanionDialog(
        onCopyError: copyReport,
        onLaunchOverlay: () => service.launchChibiOverlay(),
        onOpenDeveloper: () async {
          await launchUrl(
            Uri.parse('https://www.facebook.com/datnguyen.kei/'),
            mode: LaunchMode.externalApplication,
          );
        },
      ),
    );
  }

  void _showHelpDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161A24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE0C88F), width: 1.5),
        ),
        title: const Text(
          'HƯỚNG DẪN DÀNH CHO WINDOWS',
          style: TextStyle(
            color: Color(0xFFF0E6D2),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          '1. Chọn đúng thư mục cài đặt ChaosZeroNightmare (chứa bin\\appdata).\n'
          '2. Bấm [ Cài tiếng Việt ] một chạm để tự động vá dữ liệu.\n'
          '3. Mở game và giữ ngôn ngữ văn bản là 日本語 (tiếng Nhật).\n'
          '4. Khi game cập nhật, mở lại launcher và bấm Cập nhật là xong!',
          style: TextStyle(color: Color(0xFFC5CDE0), height: 1.6),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE0C88F),
              foregroundColor: const Color(0xFF14171F),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Đã hiểu',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final tab = CznToolsTab.values[_toolsTab];
    final titles = ['THIẾT LẬP', 'CẬP NHẬT', 'THÔNG BÁO', 'CÀI ĐẶT'];
    final subtitles = [
      'Đường dẫn game và sao lưu',
      'Cập nhật bản dịch và Launcher',
      'Bản tin cộng đồng',
      'Tùy chỉnh hệ thống',
    ];

    Widget body;
    switch (tab) {
      case CznToolsTab.setup:
        body = SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CznToolsPanel(
                variant: 1,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.folder_special_rounded,
                          color: Color(0xFFE0C88F),
                          size: 22,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'THƯ MỤC CÀI ĐẶT GAME',
                          style: TextStyle(
                            color: Color(0xFFF0E6D2),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1219),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF374151)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              gameDir.isNotEmpty
                                  ? gameDir
                                  : 'Chưa chọn thư mục game',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontFamily: 'Consolas',
                              ),
                            ),
                          ),
                          Icon(
                            access
                                ? Icons.check_circle
                                : Icons.warning_amber_rounded,
                            color: access
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFFFA726),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: busy ? null : openGamePathDialog,
                          icon: const Icon(
                            Icons.edit_location_alt_rounded,
                            size: 16,
                          ),
                          label: const Text('Đổi / Nhập đường dẫn thủ công'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE0C88F),
                            foregroundColor: const Color(0xFF14171F),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  final detected = await service
                                      .autoDetectGameDirectory();
                                  if (detected != null) await refresh();
                                },
                          icon: const Icon(
                            Icons.travel_explore_rounded,
                            size: 16,
                          ),
                          label: const Text('Tự động tìm kiếm'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE0C88F),
                            side: const BorderSide(color: Color(0xFFE0C88F)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Thẻ khôi phục & công cụ
              CznToolsPanel(
                variant: 2,
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Khôi phục dữ liệu gốc',
                            style: TextStyle(
                              color: Color(0xFFF0E6D2),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Hoàn tác bản dịch tiếng Việt, đưa game về dữ liệu tiếng Nhật ban đầu.',
                            style: TextStyle(
                              color: Color(0xFFA8B0BF),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy || !access ? null : restore,
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: const Text('Khôi phục gốc'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF8A80),
                        side: const BorderSide(color: Color(0xFFFF8A80)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        break;

      case CznToolsTab.updates:
        body = SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CznToolsPanel(
                variant: 1,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.system_update_rounded,
                          color: Color(0xFFE0C88F),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'PHIÊN BẢN HỆ THỐNG',
                          style: TextStyle(
                            color: Color(0xFFF0E6D2),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(
                            Icons.refresh,
                            color: Color(0xFFE0C88F),
                          ),
                          tooltip: 'Kiểm tra cập nhật',
                          onPressed: busy ? null : refresh,
                        ),
                      ],
                    ),
                    const Divider(color: Color(0x33E0C88F), height: 20),
                    // Hàng launcher
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Phiên bản Launcher (EXE):',
                          style: TextStyle(color: Color(0xFFC5CDE0)),
                        ),
                        Text(
                          WindowsPatchService.currentVersion,
                          style: const TextStyle(
                            color: Color(0xFFE0C88F),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Hàng bản dịch
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Phiên bản Bản Dịch (Catalog):',
                          style: TextStyle(color: Color(0xFFC5CDE0)),
                        ),
                        Text(
                          'v${translation['version'] ?? '1.6.11'}',
                          style: const TextStyle(
                            color: Color(0xFF8AD6B0),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      online,
                      style: TextStyle(
                        color: hasLauncherUpdate || hasTranslationUpdate
                            ? const Color(0xFFFFA726)
                            : const Color(0xFF81C784),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (hasTranslationUpdate || hasLauncherUpdate)
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          if (hasLauncherUpdate) {
                            await perform('update-launcher', download: true);
                          } else if (hasTranslationUpdate) {
                            await oneClick();
                          }
                        },
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    hasLauncherUpdate
                        ? 'Cập nhật Launcher mới'
                        : 'Tải & Cài bản dịch mới',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE0C88F),
                    foregroundColor: const Color(0xFF14171F),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        );
        break;

      case CznToolsTab.notice:
        body = CznToolsNoticePage(
          appVersion: WindowsPatchService.currentVersion,
          notice: playerNotice,
          busy: busy,
          onDismiss: (snooze) => unawaited(dismissNotice(snooze)),
        );
        break;

      case CznToolsTab.settings:
        body = CznToolsSettingsPage(
          companionVisible: showCompanion,
          autoDownload: autoUpdate,
          channel: WindowsPatchService.channelUrl,
          appVersion: WindowsPatchService.currentVersion,
          patchVersion: 'v${translation['version'] ?? '1.6.11'}',
          busy: busy,
          overlayActive: false,
          onSave: (comp, auto, chan, overlay) async {
            setState(() {
              showCompanion = comp;
              autoUpdate = auto;
            });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('companion_visible', comp);
            await prefs.setBool('windows_auto_update', auto);
            return true;
          },
          onCancel: _closeTools,
        );
        break;
    }

    return CznToolsBackdrop(
      child: CznToolsScaffold(
        activeTab: tab,
        title: titles[_toolsTab],
        subtitle: subtitles[_toolsTab],
        appVersion: WindowsPatchService.currentVersion,
        navigationEnabled: !busy,
        onBack: _closeTools,
        onTabChanged: (newTab) => setState(() => _toolsTab = newTab.index),
        child: body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controlsOpen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !busy) _closeTools();
        },
        child: _buildControls(context),
      );
    }

    final primaryLabel = !access
        ? 'Chọn thư mục game'
        : recovery
        ? 'Phục hồi dữ liệu'
        : installed
        ? (hasTranslationUpdate ? 'Cập nhật bản dịch' : 'VÀO GAME CZN')
        : 'Cài tiếng Việt';

    return Scaffold(
      body: CznWallpaper(
        child: CznCompanion(
          visible: showCompanion,
          onHide: () async {
            setState(() => showCompanion = false);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('companion_visible', false);
          },
          onTap: _showCompanionChat,
          child: CznLanding(
            isPc: true,
            patchVersion: 'v${translation['version'] ?? '1.6.11'}',
            appVersion: WindowsPatchService.currentVersion,
            access: access,
            ready: ready,
            installed: installed,
            busy: busy,
            checking: checking,
            message: message,
            showMessage: true,
            primaryLabel: primaryLabel,
            onPrimary: busy ? null : oneClick,
            onSetup: busy ? null : () => _openTools(0),
            onUpdates: busy ? null : () => _openTools(1),
            onHelp: _showHelpDialog,
            onDonate: busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DonateScreen(),
                    ),
                  ),
            onSettings: busy ? null : () => _openTools(3),
            onNotice: busy ? null : () => _openTools(2),
          ),
        ),
      ),
    );
  }
}
