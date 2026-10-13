import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/native_bridge.dart';
import '../services/notice_policy.dart';
import '../services/patch_service.dart';
import 'czn_components.dart';
import 'czn_glass.dart';
import 'czn_tools_backdrop.dart';
import 'czn_raster.dart';
import 'czn_theme.dart';
import 'czn_companion.dart';
import 'app_update_card.dart';
import 'czn_landing.dart';
import 'companion_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Map<String, dynamic> _status = {}, _game = {}, _lastOperation = {};
  ReleaseInfo? _bundled, _remote;
  bool _busy = false, _checking = false, _downloading = false;
  String _message = 'Đang chuẩn bị ứng dụng…', _onlineMessage = '';
  double _progress = 0;
  bool _refreshPending = false, _noticeOpen = false, _noticeRequested = true;
  String? _noticeShown;
  bool _showCompanion = true;
  bool _appUpdating = false;
  String _appUpdateMessage = '';
  String _lastErrorCode = '';
  bool _controlsOpen = false;
  int _toolsTab = 0;
  void _openTools(int tab) => setState(() {
    _toolsTab = tab;
    _controlsOpen = true;
  });
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadCompanionSetting());
    _refresh();
  }

  Future<void> _loadCompanionSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(
          () => _showCompanion = prefs.getBool('companion_visible') ?? true,
        );
      }
    } catch (_) {}
  }

  Future<void> _setCompanionVisible(bool visible) async {
    if (mounted) setState(() => _showCompanion = visible);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('companion_visible', visible);
    } catch (_) {}
  }

  void _hideCompanion() {
    unawaited(_setCompanionVisible(false));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Đã ẩn nhân vật. Bạn có thể bật lại trong Cài đặt.',
        ),
        action: SnackBarAction(
          label: 'Hiện lại',
          onPressed: () => _setCompanionVisible(true),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _noticeRequested = true;
      _noticeShown = null;
    }
    if (state == AppLifecycleState.resumed && _appUpdating) {
      _refreshPending = true;
    }
    if (state == AppLifecycleState.resumed && !_busy) {
      if (_checking) {
        _refreshPending = true;
      } else {
        _refresh();
      }
    }
  }

  Future<void> _refresh() async {
    if (_busy || _checking) return;
    setState(() => _checking = true);
    try {
      final status = await NativeBridge.map('status');
      final bundle = ReleaseInfo.bundled(await NativeBridge.map('bundledInfo'));
      if (!mounted) return;
      setState(() {
        _status = status;
        _bundled = bundle;
        if (_lastOperation.isEmpty) _message = 'Sẵn sàng';
      });
      try {
        final last = await NativeBridge.map('lastOperation');
        if (mounted && last.isNotEmpty) {
          setState(() {
            _lastOperation = last;
            _message =
                last['message'] as String? ??
                (last['success'] == true
                    ? 'Lần cài gần nhất đã được xác minh.'
                    : 'Lần cài gần nhất chưa hoàn tất.');
          });
        }
      } catch (_) {}
      try {
        final cache = await NativeBridge.map('cachedChannel');
        if (cache.containsKey('patch_code') && mounted) {
          setState(() => _remote = ReleaseInfo.channel(cache));
          _maybeNotice();
        }
      } catch (_) {}
      _maybeNotice();
      if (status['accessGranted'] == true && status['package'] != null) {
        try {
          final game = await NativeBridge.map('scanGame');
          if (mounted) {
            setState(() {
              _game = game;
              if (game['success'] != true) {
                _message =
                    game['message'] as String? ??
                    'Chưa nhận diện được dữ liệu game.';
              }
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _game = {'success': false, 'message': _error(e)};
              _message = _error(e);
            });
          }
        }
        final freshStatus = await NativeBridge.map('status');
        if (mounted) setState(() => _status = freshStatus);
      }
      try {
        final channel = ReleaseInfo.channel(
          await NativeBridge.map('checkUpdate'),
        );
        if (mounted) {
          setState(() {
            _remote = channel;
            final appNew =
                (channel.data['app_code'] as int? ?? 0) >
                (_status['appCode'] as int? ?? 10610);
            final patchNew =
                channel.code >
                (_game['installed_code'] as int? ?? _bundled?.code ?? 0);
            _onlineMessage = appNew || patchNew
                ? 'Có bản mới. Chọn cập nhật bên dưới.'
                : 'Đã kiểm tra: bạn đang có gói và ứng dụng mới nhất.';
          });
          _maybeNotice();
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => _onlineMessage =
                'Chưa kết nối được kênh cập nhật. Bản đi kèm vẫn có thể cài.',
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _message = _error(e));
    } finally {
      if (mounted) {
        setState(() => _checking = false);
        if (_refreshPending && !_busy) {
          _refreshPending = false;
          _refresh();
        } else if (_status['pendingAppUpdate'] == true &&
            _status['appInstallAllowed'] == true &&
            !_busy) {
          unawaited(_updateApp(resume: true));
        }
      }
    }
  }

  Future<void> _maybeNotice({bool force = false}) async {
    final data = _remote?.data;
    final notice = CommunityNotice.fromChannel(
      data != null && data.containsKey('notice') ? data : _bundled?.data ?? {},
    );
    if (!mounted ||
        _busy ||
        _status['pendingAppUpdate'] == true ||
        _noticeOpen ||
        notice == null) {
      return;
    }
    if (!force &&
        (!_noticeRequested && _noticeShown == notice.id ||
            notice.isSnoozed(_status, DateTime.now()))) {
      return;
    }
    _noticeOpen = true;
    _noticeRequested = false;
    _noticeShown = notice.id;
    final snooze = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(notice.title),
        content: SingleChildScrollView(child: SelectableText(notice.body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Tắt'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Tắt trong 24 giờ'),
          ),
        ],
      ),
    );
    if (snooze == true) {
      try {
        await NativeBridge.action('snoozeNotice', {'id': notice.id});
        if (mounted) _status = await NativeBridge.map('status');
      } catch (e) {
        if (mounted) setState(() => _message = _error(e));
      }
    }
    _noticeOpen = false;
  }

  String _error(Object e) {
    _lastErrorCode = e is PlatformException ? e.code : 'APP_ERROR';
    return e is PlatformException
        ? (e.message ?? 'Thao tác chưa hoàn tất.')
        : e.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _access() async {
    try {
      if (_status['shizukuRunning'] != true) {
        final opened = await NativeBridge.action('openShizuku');
        if (!opened) {
          await launchUrl(
            Uri.parse('https://shizuku.rikka.app/download/'),
            mode: LaunchMode.externalApplication,
          );
        }
        return;
      }
      await NativeBridge.action('requestAccess');
      if (_status['autoDownload'] != false) {
        await NativeBridge.action('requestNotifications');
      }
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _message = _error(e));
    }
  }

  Future<void> _run(
    Future<Map<String, dynamic>> Function() operation, {
    bool scanGame = true,
    String action = 'install',
  }) async {
    if (_busy || _checking) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _message = 'Đang chuẩn bị…';
    });
    var finished = false;
    Map<String, dynamic> response = {};
    final subscription = NativeBridge.progress.receiveBroadcastStream().listen((
      event,
    ) {
      if (mounted && !finished) {
        final data = Map<String, dynamic>.from(event as Map);
        setState(() {
          _message = data['label'] as String;
          _progress = (data['percent'] as num).toDouble() / 100;
        });
      }
    }, onError: (_) {});
    bool success = false;
    try {
      response = await operation();
      final post = response['post_install'];
      final game = !scanGame
          ? _game
          : post is Map
          ? Map<String, dynamic>.from(post)
          : await NativeBridge.map('scanGame');
      if (mounted && scanGame) setState(() => _game = game);
      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Thao tác chưa hoàn tất.');
      }
      if (scanGame && game['success'] != true) {
        throw Exception(
          game['message'] ?? 'Không đọc lại được dữ liệu sau thao tác. Chưa xác nhận thành công.',
        );
      }
      if (action == 'install' &&
          (game['files_match'] != true ||
              (game['installed_version'] as String? ?? '').isEmpty ||
              ((game['installed_code'] as int?) ?? 0) <= 0 ||
              game['recovery_required'] == true ||
              (response['version_code'] != null &&
                  game['installed_code'] != response['version_code']) ||
              (response['version'] != null &&
                  game['installed_version'] != response['version']))) {
        throw Exception(
          'Dữ liệu sau cài chưa khớp bản dịch. Chưa xác nhận cài thành công. Bấm Sao chép lỗi để gửi báo cáo.',
        );
      }
      finished = true;
      success = true;
      if (mounted) {
        setState(() {
          _game = game;
          _message =
              response['message'] as String? ??
              (action == 'install'
                  ? 'Cài thành công bản ${game['installed_version']}. Dữ liệu sau cài đã khớp. Chọn 日本語 trong game.'
                  : 'Đã khôi phục đầy đủ dữ liệu trước cài.');
          _progress = 1;
        });
      }
    } catch (e) {
      finished = true;
      if (mounted) {
        setState(() {
          _message = _error(e);
          if (scanGame && response['post_install'] is! Map) _game = {};
        });
      }
    } finally {
      finished = true;
      unawaited(subscription.cancel().catchError((Object _) {}));
      Map<String, dynamic> last = {};
      try {
        if (action != 'appUpdate') {
          last = await NativeBridge.map('lastOperation');
        }
      } catch (_) {}
      if (mounted) {
        try {
          _status = await NativeBridge.map('status');
        } catch (_) {}
        setState(() {
          _lastOperation = {
            ...last,
            ...response,
            'action': action,
            'phase': success ? 'completed' : 'failed',
            'success': success,
            'message': _message,
          };
          _busy = false;
          _downloading = false;
        });
      }
    }
    if (mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: Text(
            success
                ? (action == 'install'
                      ? 'Cài Việt hóa thành công'
                      : action == 'restore'
                      ? 'Đã khôi phục bản gốc'
                      : 'Đã mở trình cài APK')
                : action == 'install'
                ? 'Chưa cài được Việt hóa'
                : 'Thao tác chưa hoàn tất',
          ),
          content: SingleChildScrollView(child: Text(_message)),
          actions: [
            if (!success)
              TextButton(
                onPressed: _copyReport,
                child: const Text('Sao chép lỗi'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _install() async {
    if (AppUpdateInfo.fromChannel(
          _remote?.data,
          _status['appCode'] as int? ?? 10610,
        ) !=
        null) {
      await _updateApp();
      return;
    }
    if (_status['accessGranted'] != true) {
      await _access();
      return;
    }
    await _run(() async {
      if (_remote != null &&
          _bundled != null &&
          _remote!.code > _bundled!.code) {
        setState(() => _downloading = true);
        final path = await NativeBridge.download(_remote!.data);
        if (!mounted) {
          throw Exception('Ứng dụng đã đóng; gói tải được giữ để cài sau.');
        }
        setState(() => _downloading = false);
        return NativeBridge.map('installPatch', {'path': path});
      }
      return NativeBridge.map('installBundled');
    });
  }

  Future<void> _local() async {
    if (_status['accessGranted'] != true) {
      await _access();
      return;
    }
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['cznpatch', 'zip'],
    );
    if (picked.isEmpty || picked.first.path == null || !mounted) return;
    await _run(() async {
      final source = File(picked.first.path!);
      if (await source.length() > 33554432) {
        throw Exception('Gói vượt 32 MB. Gói cũ 210 MB không còn được hỗ trợ.');
      }
      final cache = await getApplicationSupportDirectory();
      final temp = File('${cache.path}/local.cznpatch');
      await source.copy(temp.path);
      return NativeBridge.map('installPatch', {'path': temp.path});
    });
  }

  Future<void> _restore() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Khôi phục dữ liệu gốc?'),
        content: const Text(
          'Ứng dụng sẽ đóng CZN và phục hồi các file đã sao lưu. Nếu game đã cập nhật, app sẽ kiểm tra và từ chối ghi bản sao lưu cũ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Khôi phục'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _run(() => NativeBridge.map('restore'), action: 'restore');
    }
  }

  Future<void> _updateApp({bool resume = false}) async {
    if (_busy || _checking) return;
    final release = _remote;
    if (!resume &&
        AppUpdateInfo.fromChannel(
              release?.data,
              _status['appCode'] as int? ?? 10610,
            ) ==
            null) {
      return;
    }
    setState(() {
      _busy = true;
      _appUpdating = true;
      _downloading = !resume;
      _progress = 0;
      _appUpdateMessage = resume
          ? 'Đang mở trình cài cập nhật…'
          : 'Đang tải APK cập nhật…';
    });
    var finished = false;
    final subscription = NativeBridge.progress.receiveBroadcastStream().listen((
      event,
    ) {
      if (!mounted || finished) return;
      final data = Map<String, dynamic>.from(event as Map);
      setState(() {
        _appUpdateMessage = data['label'] as String;
        _progress = (data['percent'] as num).toDouble() / 100;
      });
    }, onError: (_) {});
    try {
      Map<String, dynamic> result;
      if (resume) {
        result = await NativeBridge.map('resumeAppUpdate');
      } else {
        final path = await NativeBridge.download(release!.data, apk: true);
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _progress = 1;
          _appUpdateMessage = 'Đã tải và kiểm tra APK. Đang mở trình cài…';
        });
        result = await NativeBridge.map('installApp', {'path': path});
      }
      if (result['state'] != 'installer_opened' &&
          result['state'] != 'permission_required') {
        throw Exception('Chưa mở được trình cài cập nhật của Android.');
      }
      finished = true;
      if (mounted) {
        setState(
          () => _appUpdateMessage = result['state'] == 'permission_required'
              ? 'Bật “Cho phép từ nguồn này”, rồi quay lại app. APK đã tải sẽ được dùng để tiếp tục cập nhật.'
              : 'Xác nhận Cập nhật trên màn hình Android. App sẽ hiển thị phiên bản đang dùng khi bạn mở lại.',
        );
      }
    } catch (e) {
      finished = true;
      if (mounted) {
        setState(() => _appUpdateMessage = _error(e));
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Chưa cập nhật được ứng dụng'),
            content: SingleChildScrollView(child: Text(_appUpdateMessage)),
            actions: [
              TextButton(
                onPressed: _copyReport,
                child: const Text('Sao chép lỗi'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
    } finally {
      finished = true;
      unawaited(subscription.cancel().catchError((Object _) {}));
      if (mounted) {
        try {
          _status = await NativeBridge.map('status');
        } catch (_) {}
        if (mounted) {
          setState(() {
            _busy = false;
            _appUpdating = false;
            _downloading = false;
          });
          if (_refreshPending) {
            _refreshPending = false;
            unawaited(_refresh());
          }
        }
      }
    }
  }

  Future<void> _settings() async {
    final controller = TextEditingController(
      text: _status['channel'] as String?,
    );
    bool auto = _status['autoDownload'] != false;
    bool companion = _showCompanion;
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Cài đặt'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hiện nhân vật đồng hành'),
                  subtitle: const Text(
                    'Hiện trên trang hình nền. Kéo trong vùng trống; nhấn giữ để ẩn.',
                  ),
                  value: companion,
                  onChanged: (v) => update(() => companion = v),
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tự tải bản mới qua Wi-Fi'),
                  subtitle: const Text(
                    'Kiểm tra khoảng mỗi 12 giờ qua Wi-Fi. Tự tải cả ứng dụng (giao diện, icon, chức năng) và bản dịch. Android sẽ hỏi xác nhận cài APK.',
                  ),
                  value: auto,
                  onChanged: (v) => update(() => auto = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ kênh cập nhật',
                    helperText: 'Chỉ nhận bản được dự án ký xác thực.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      await _setCompanionVisible(companion);
      try {
        await NativeBridge.action('saveSettings', {
          'channel': controller.text.trim(),
          'autoDownload': auto,
        });
        await _refresh();
      } catch (e) {
        if (mounted) setState(() => _message = _error(e));
      }
    }
    // The dialog exit animation may still use its controller; disposal follows it.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    controller.dispose();
  }

  Future<bool> _copyReport() async {
    try {
      await Clipboard.setData(
        ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert({
            'app': _status['appVersion'] ?? '1.6.10',
            'error_code':
                _lastOperation['error_code'] ??
                _game['error_code'] ??
                (_lastErrorCode.isEmpty ? 'CHUA_CO_LOI' : _lastErrorCode),
            'status': _status,
            'game': _game,
            'lastOperation': _lastOperation,
            'message': _message,
            'appUpdateMessage': _appUpdateMessage,
          }),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã copy mã lỗi và báo cáo để gửi hỗ trợ.'),
          ),
        );
      }
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa copy được mã lỗi. Thử lại nhé.')),
        );
      }
      return false;
    }
  }

  Widget _step(
    int n,
    String title,
    String description,
    Widget? action, {
    bool done = false,
  }) {
    final active =
        !done &&
        (n == 1 || _status['accessGranted'] == true) &&
        (n < 3 || _game['success'] == true);
    final accent = done
        ? CznColors.green
        : active
        ? CznColors.red
        : CznColors.border;
    return Container(
      decoration: BoxDecoration(
        color: CznColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: done || active ? .45 : 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    key: Key('step-$n-status'),
                    done
                        ? Icons.check_circle
                        : [Icons.key_outlined, Icons.radar, Icons.translate][n -
                              1],
                    size: 19,
                    color: done
                        ? CznColors.green
                        : active
                        ? CznColors.red
                        : CznColors.muted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BƯỚC 0$n  /  ${done ? 'HOÀN TẤT' : 'THIẾT LẬP'}',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color: done ? CznColors.green : CznColors.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$n. $title',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(description, style: Theme.of(context).textTheme.bodyMedium),
            if (action != null) ...[const SizedBox(height: 14), action],
          ],
        ),
      ),
    );
  }

  Future<void> _showCompanionChat() async {
    await showDialog<void>(
      context: context,
      builder: (_) => CompanionDialog(
        onCopyError: _copyReport,
        onOpenDeveloper: _openDeveloperProfile,
      ),
    );
  }

  Future<void> _openDeveloperProfile() async {
    try {
      final opened = await launchUrl(
        Uri.parse('https://www.facebook.com/datnguyen.kei/'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa mở được trang Dev. Thử lại sau nhé.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa mở được trang Dev. Thử lại sau nhé.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controlsOpen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !_busy) setState(() => _controlsOpen = false);
        },
        child: _buildControls(context),
      );
    }
    final access = _status['accessGranted'] == true;
    final ready = _game['success'] == true;
    final recovery =
        _game['recovery_required'] == true ||
        _status['recoveryPending'] == true;
    final installed =
        ready &&
        _game['files_match'] == true &&
        (_game['installed_code'] as int? ?? 0) > 0 &&
        !recovery;
    final latest =
        _remote != null && (_bundled == null || _remote!.code >= _bundled!.code)
        ? _remote
        : _bundled;
    final appNew =
        AppUpdateInfo.fromChannel(
          _remote?.data,
          _status['appCode'] as int? ?? 10610,
        ) !=
        null;
    final label = appNew
        ? 'Cập nhật toàn bộ'
        : recovery
        ? 'Phục hồi dữ liệu'
        : !access || !ready
        ? 'Cài tiếng Việt'
        : installed
        ? 'Cập nhật bản dịch'
        : 'Cài tiếng Việt';
    return Scaffold(
      body: CznCompanion(
        // Keep the sprite in empty artwork, away from faces and actions.
        dragRegion: (size) {
          final top = MediaQuery.paddingOf(context).top;
          if (size.width > size.height) {
            if (size.height - MediaQuery.paddingOf(context).vertical < 340) {
              return Rect.zero;
            }
            return Rect.fromLTRB(14, top + 88, 160, top + 180);
          }
          return Rect.fromLTRB(
            size.width * .65,
            top + 62,
            size.width - 8,
            top + 172,
          );
        },
        visible: _showCompanion && !_busy,
        onHide: _hideCompanion,
        onTap: _showCompanionChat,
        child: CznLanding(
          patchVersion: latest?.version ?? 'Đang đọc…',
          appVersion: _status['appVersion'] as String? ?? '1.6.10',
          access: access,
          ready: ready,
          installed: installed,
          busy: _busy,
          checking: _checking,
          message: _appUpdateMessage.isNotEmpty ? _appUpdateMessage : _message,
          showMessage:
              _appUpdateMessage.isNotEmpty || _lastErrorCode.isNotEmpty,
          primaryLabel: label,
          onPrimary: _busy || _checking
              ? null
              : () {
                  if (appNew) {
                    unawaited(_updateApp());
                  } else if (recovery && access) {
                    unawaited(_restore());
                  } else if (!access || !ready) {
                    _openTools(0);
                  } else {
                    unawaited(_install());
                  }
                },
          onSetup: _busy ? null : () => _openTools(0),
          onUpdates: _busy ? null : () => _openTools(1),
          onHelp: _showCompanionChat,
          onSettings: _busy || _checking ? null : _settings,
          onNotice: _busy ? null : () => _maybeNotice(force: true),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final access = _status['accessGranted'] == true;
    final recovery =
        _game['recovery_required'] == true ||
        _status['recoveryPending'] == true;
    final installed =
        _game['success'] == true &&
        _game['files_match'] == true &&
        (_game['installed_version'] as String? ?? '').isNotEmpty &&
        ((_game['installed_code'] as int?) ?? 0) > 0 &&
        !recovery;
    final latest =
        _remote != null && (_bundled == null || _remote!.code >= _bundled!.code)
        ? _remote
        : _bundled;
    final hasUpdate =
        latest != null &&
        latest.newerThan((_game['installed_code'] as int?) ?? 0);
    final appUpdate = AppUpdateInfo.fromChannel(
      _remote?.data,
      _status['appCode'] as int? ?? 10610,
    );
    return CznToolsBackdrop(
      child: DefaultTabController(
        key: ValueKey(_toolsTab),
        length: 2,
        initialIndex: _toolsTab,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Về hình nền',
              icon: const CznImageIcon(Icons.arrow_back),
              onPressed: _busy
                  ? null
                  : () => setState(() => _controlsOpen = false),
            ),
            toolbarHeight: 66,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: AbsorbPointer(
                  absorbing: _busy,
                  child: TabBar(
                    onTap: _busy
                        ? null
                        : (tab) => setState(() => _toolsTab = tab),
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: const Color(0x99501A2A),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: glassIvory),
                    ),
                    labelColor: glassIvory,
                    unselectedLabelColor: Colors.white70,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    tabs: const [
                      Tab(key: Key('tools-setup-tab'), text: 'Thiết lập'),
                      Tab(key: Key('tools-update-tab'), text: 'Cập nhật'),
                    ],
                  ),
                ),
              ),
            ),
            title: const CznGameLogo(showVietnamese: false),
            actions: [
              IconButton(
                tooltip: 'Thông báo cộng đồng',
                onPressed: _busy ? null : () => _maybeNotice(force: true),
                icon: const CznImageIcon(Icons.campaign_outlined),
              ),
              IconButton(
                tooltip: 'Cài đặt',
                onPressed: _busy || _checking ? null : _settings,
                icon: const CznImageIcon(Icons.settings_outlined),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: CznCompanion(
              visible: false,
              onHide: _hideCompanion,
              onTap: _showCompanionChat,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    children: [
                      if (_toolsTab == 1) ...[
                        const CznSectionLabel('CẬP NHẬT TOÀN BỘ'),
                        AppUpdateCard(
                          currentVersion:
                              _status['appVersion'] as String? ?? '1.6.10',
                          update: appUpdate,
                          checking: _checking,
                          updating: _appUpdating,
                          pending: _status['pendingAppUpdate'] == true,
                          message: _appUpdateMessage,
                          progress: _progress,
                          onCheck: _busy || _checking ? null : _refresh,
                          onUpdate: _busy || _checking
                              ? null
                              : () => _updateApp(
                                  resume: _status['pendingAppUpdate'] == true,
                                ),
                          onCancel: _downloading
                              ? () => NativeBridge.action('cancelDownload')
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Bản dịch ${latest?.version ?? "Đang đọc…"}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Giao diện, icon và chức năng đi theo APK mới. Bản dịch được tải riêng; Android yêu cầu xác nhận khi nâng ứng dụng.',
                                  style: TextStyle(height: 1.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_toolsTab == 0) ...[
                        CznStatusStrip(
                          access: access,
                          ready: _game['success'] == true,
                          installed: installed,
                        ),
                        if (recovery) ...[
                          Card(
                            color: const Color(0xC730241D),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Cần phục hồi dữ liệu',
                                    style: TextStyle(
                                      color: CznColors.amber,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Lần cài trước chưa hoàn tất. Phục hồi giao dịch trước khi cài tiếp hoặc mở game.',
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: _busy || _checking || !access
                                        ? null
                                        : _restore,
                                    icon: const CznImageIcon(Icons.restore),
                                    label: const Text('Phục hồi giao dịch'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        const CznSectionLabel(
                          'THIẾT LẬP TIẾNG VIỆT',
                          trailing: '03 bước',
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Chọn 日本語 trong game. Hoàn tất ba bước dưới đây để cài bản dịch.',
                          ),
                        ),
                        if (_lastOperation.isNotEmpty && !_busy)
                          Card(
                            key: const Key('operation-result'),
                            color: _lastOperation['success'] == true
                                ? const Color(0xFF152A27)
                                : const Color(0xFF322025),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _lastOperation['phase'] == 'running'
                                        ? 'Lần cài trước chưa có kết quả xác minh'
                                        : 'Kết quả thao tác gần nhất',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _lastOperation['message'] as String? ??
                                        _message,
                                  ),
                                  if (_lastOperation['success'] != true)
                                    TextButton(
                                      onPressed: _copyReport,
                                      child: const Text('Sao chép lỗi cài đặt'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (installed)
                          Card(
                            color: const Color(0xFF152A27),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Đã cài bản ${_game['installed_version']} · Dữ liệu đã kiểm tra',
                              ),
                            ),
                          ),
                        if (_game['installed_version'] != null && !installed)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'Dữ liệu game đã thay đổi. Hoàn tất cập nhật game trước khi cài lại.',
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        _step(
                          1,
                          'Kết nối Shizuku',
                          access
                              ? 'Đã cấp quyền. App có thể kiểm tra dữ liệu game.'
                              : 'Khởi động Shizuku bằng gỡ lỗi không dây, rồi cấp quyền cho app. Android 8–10 cần máy tính để khởi động Shizuku.',
                          access
                              ? null
                              : FilledButton.tonal(
                                  onPressed: _busy || _checking
                                      ? null
                                      : _access,
                                  child: Text(
                                    _status['shizukuRunning'] == true
                                        ? 'Cấp quyền cho app'
                                        : 'Mở / tải Shizuku',
                                  ),
                                ),
                          done: access,
                        ),
                        const SizedBox(height: 12),
                        _step(
                          2,
                          'Chuẩn bị game',
                          !access
                              ? 'Cấp quyền Shizuku ở bước 1 để app kiểm tra dữ liệu. Mở game, chọn 日本語 và chờ tải xong; sau đó quay lại bấm Kiểm tra lại.'
                              : _status['package'] == null
                              ? 'Chưa nhận diện được gói CZN được hỗ trợ. Game từ TapTap cũng được nhận theo mã gói. Cài game cùng hồ sơ Android với patcher; gửi báo cáo nếu vẫn không thấy game.'
                              : (_game['success'] == true
                                    ? 'Đã tìm thấy dữ liệu CZN. App sẽ đóng game trước khi cài.'
                                    : (_game['message'] as String? ??
                                          'Mở CZN, tải đủ dữ liệu và chọn 日本語 trong cài đặt ngôn ngữ.')),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if ((_status['games'] as List? ?? []).length > 1)
                                DropdownButtonFormField<String>(
                                  initialValue: _status['package'] as String?,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Bản game muốn cài',
                                  ),
                                  items: (_status['games'] as List)
                                      .map(
                                        (g) => DropdownMenuItem<String>(
                                          value: g['package'] as String,
                                          child: Text(g['package'] as String),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _busy || _checking
                                      ? null
                                      : (pkg) async {
                                          await NativeBridge.action(
                                            'selectGame',
                                            {'package': pkg},
                                          );
                                          if (mounted) {
                                            setState(() => _game = {});
                                          }
                                          await _refresh();
                                        },
                                ),
                              OutlinedButton.icon(
                                onPressed: _busy || _checking
                                    ? null
                                    : () async {
                                        try {
                                          final opened =
                                              await NativeBridge.action(
                                                'launchGame',
                                              );
                                          if (!opened) {
                                            await launchUrl(
                                              Uri.parse(
                                                'https://play.google.com/store/apps/details?id=com.smilegate.chaoszero.stove.google',
                                              ),
                                              mode: LaunchMode
                                                  .externalApplication,
                                            );
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            setState(
                                              () => _message = _error(e),
                                            );
                                          }
                                        }
                                      },
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Mở CZN'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy || _checking
                                    ? null
                                    : (access ? _refresh : _access),
                                icon: const Icon(Icons.search),
                                label: const Text('Kiểm tra lại dữ liệu game'),
                              ),
                              if (_status['package'] != null)
                                Text(
                                  'Bản game: ${_status['package']}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (_game['success'] == false)
                                TextButton(
                                  onPressed: _copyReport,
                                  child: const Text(
                                    'Sao chép báo cáo lỗi bước 2',
                                  ),
                                ),
                            ],
                          ),
                          done: _game['success'] == true,
                        ),
                        const SizedBox(height: 12),
                        _step(
                          3,
                          'Cài tiếng Việt',
                          latest == null
                              ? 'Đang đọc bản dịch đi kèm…'
                              : ('Bản ${latest.version}. Có sao lưu và kiểm tra dữ liệu sau cài. Nếu nguồn Nhật đã thay đổi, app sẽ chờ gói tương thích.'),
                          FilledButton.icon(
                            onPressed:
                                _busy ||
                                    _checking ||
                                    _bundled == null ||
                                    _status['package'] == null ||
                                    _game['success'] != true ||
                                    recovery
                                ? null
                                : _install,
                            icon: const CznImageIcon(Icons.download_done),
                            label: Text(
                              installed
                                  ? (hasUpdate
                                        ? 'Cập nhật bản dịch'
                                        : 'Cài lại bản dịch')
                                  : 'Cài tiếng Việt',
                            ),
                          ),
                          done: installed,
                        ),
                        const CznSectionLabel('TRẠNG THÁI'),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _message,
                                    style: const TextStyle(
                                      color: CznColors.text,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                                if (_busy) ...[
                                  const SizedBox(height: 12),
                                  LinearProgressIndicator(value: _progress),
                                  if (_downloading)
                                    TextButton(
                                      onPressed: () =>
                                          NativeBridge.action('cancelDownload'),
                                      child: const Text('Hủy tải'),
                                    ),
                                ],
                                if (_checking) ...[
                                  const SizedBox(height: 8),
                                  const LinearProgressIndicator(),
                                ],
                                if (_onlineMessage.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _onlineMessage,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const CznSectionLabel('QUẢN LÝ BẢN DỊCH'),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy || _checking ? null : _local,
                              icon: const CznImageIcon(Icons.folder_open),
                              label: const Text('Cài từ gói tải sẵn'),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _busy || _checking || !access
                                  ? null
                                  : _restore,
                              icon: const CznImageIcon(Icons.restore),
                              label: const Text('Khôi phục gốc'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_remote != null &&
                            _remote!.code >
                                (_game['installed_code'] as int? ??
                                    _bundled?.code ??
                                    0))
                          FilledButton.tonal(
                            onPressed:
                                _busy ||
                                    _checking ||
                                    _status['package'] == null ||
                                    !access ||
                                    _game['success'] != true ||
                                    recovery
                                ? null
                                : _install,
                            child: const Text('Tải và cập nhật bản dịch'),
                          ),
                        const SizedBox(height: 20),
                        Card(
                          child: ExpansionTile(
                            title: const Text('Hướng dẫn và trợ giúp'),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              16,
                            ),
                            children: [
                              const Text(
                                'Sau khi cài, mở game và đặt ngôn ngữ văn bản là 日本語. Bản dịch dùng slot tiếng Nhật; giọng lồng tiếng tùy bạn chọn.\n\nGame cập nhật có thể làm nguồn JP thay đổi. App sẽ kiểm tra lại và chờ bản dịch phù hợp. Shizuku cần được khởi động lại sau khi điện thoại khởi động.\n\nBản vá thay tài nguyên cục bộ. Kiểm tra checksum không phải xác nhận an toàn tài khoản từ nhà phát hành.',
                                style: TextStyle(height: 1.5),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: () => launchUrl(
                                      Uri.parse(
                                        'https://shizuku.rikka.app/guide/setup/',
                                      ),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                    child: const Text('Hướng dẫn Shizuku'),
                                  ),
                                  TextButton(
                                    onPressed: () => launchUrl(
                                      Uri.parse(
                                        'https://github.com/doubleD1302/CZN-VH',
                                      ),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                    child: const Text('Trang dự án'),
                                  ),
                                  TextButton(
                                    onPressed: () => showLicensePage(
                                      context: context,
                                      applicationName:
                                          'Chaos Zero Nightmare Việt Hóa',
                                      applicationVersion:
                                          _status['appVersion'] as String? ??
                                          '1.6.10',
                                    ),
                                    child: const Text('Giấy phép thư viện'),
                                  ),
                                  TextButton(
                                    onPressed: _copyReport,
                                    child: const Text('Sao chép báo cáo'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'Chaos Zero Nightmare Việt Hóa · ${_status['appVersion'] ?? '1.6.10'}',
                          style: const TextStyle(
                            color: CznColors.muted,
                            fontSize: 11,
                            letterSpacing: .5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
