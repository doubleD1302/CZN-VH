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
import 'czn_tools_design.dart';
import 'czn_tools_preferences.dart';
import 'czn_tools_workflow.dart';
import 'czn_tools_backdrop.dart';
import 'czn_companion.dart';
import 'czn_landing.dart';
import 'companion_dialog.dart';
import 'local_adb_dialog.dart';

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
  CommunityNotice? _currentNotice;
  bool _noticeOriginOpen = false, _settingsOriginOpen = false;
  int _noticeOriginTab = 0, _settingsOriginTab = 0;
  bool get _isPc => _status['package'] == 'smilegate.czn.pc';

  void _openTools(int tab) {
    if (!mounted || _busy) return;
    setState(() {
      _toolsTab = tab;
      _controlsOpen = true;
      if (tab != 2) _noticeOpen = false;
    });
  }

  void _closeTools() {
    if (!mounted || _busy) return;
    setState(() {
      _controlsOpen = false;
      _noticeOpen = false;
    });
  }

  void _selectToolsTab(CznToolsTab tab) {
    if (_busy) return;
    if (tab == CznToolsTab.settings) {
      unawaited(_settings());
    } else if (tab == CznToolsTab.notice) {
      unawaited(_maybeNotice(force: true));
    } else {
      _openTools(tab.index);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadCompanionSetting());
    if (!WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      NativeBridge.channel.setMethodCallHandler((call) async {
        if (call.method == 'openCompanionDialog') {
          if (mounted) {
            _showCompanionChat();
          }
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowExitGameNotice();
        _checkCompanionIntent();
      });
    }
    _refresh();
  }

  Future<void> _checkCompanionIntent() async {
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return;
    try {
      final shouldOpen = await NativeBridge.checkCompanionLaunchIntent();
      if (shouldOpen && mounted) {
        _showCompanionChat();
      }
    } catch (_) {}
  }

  Future<void> _checkAndShowExitGameNotice() async {
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final snoozeUntil = prefs.getInt('dismiss_exit_game_notice_until') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now < snoozeUntil) {
        return;
      }
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF14171F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFC5A059), width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFE5A93C),
                size: 26,
              ),
              SizedBox(width: 8),
              Text(
                'LƯU Ý QUAN TRỌNG',
                style: TextStyle(
                  color: Color(0xFFF0E6D2),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: const Text(
            'Để tránh bị lỗi - Đảm bảo bạn đã thoát game hoàn toàn trước khi cài Việt Hóa nha !',
            style: TextStyle(
              color: Color(0xFFE2D9C8),
              fontSize: 15,
              height: 1.45,
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final p = await SharedPreferences.getInstance();
                await p.setInt(
                  'dismiss_exit_game_notice_until',
                  DateTime.now()
                      .add(const Duration(hours: 24))
                      .millisecondsSinceEpoch,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text(
                'Tắt 24 giờ',
                style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC5A059),
                foregroundColor: Colors.black,
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (_) {}
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
    if (state == AppLifecycleState.resumed) {
      _checkCompanionIntent();
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
        if (mounted && last.isNotEmpty && _lastOperation.isEmpty) {
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
              _game = {
                'success': false,
                'message': _error(e),
                'error_code': e is PlatformException ? e.code : 'APP_ERROR',
                if (e is PlatformException) 'diagnostics': e.details,
              };
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
                !_isPc &&
                (channel.data['app_code'] as int? ?? 0) >
                    (_status['appCode'] as int? ?? 10612);
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
    if (!mounted || _busy || _status['pendingAppUpdate'] == true) {
      return;
    }
    if (_noticeOpen) {
      // A cached bulletin can be replaced by the signed channel while open.
      if (_currentNotice?.id != notice?.id ||
          _currentNotice?.title != notice?.title ||
          _currentNotice?.body != notice?.body) {
        setState(() {
          _currentNotice = notice;
          if (notice != null) _noticeShown = notice.id;
        });
      }
      return;
    }
    // Keep unsaved preference edits on screen until the user leaves them.
    if (!force && _controlsOpen && _toolsTab == 3) return;
    if (!force &&
        (notice == null ||
            (!_noticeRequested && _noticeShown == notice.id ||
                notice.isSnoozed(_status, DateTime.now())))) {
      return;
    }
    _noticeOriginOpen = _controlsOpen;
    _noticeOriginTab = _toolsTab;
    setState(() {
      _currentNotice = notice;
      _noticeOpen = true;
      _noticeRequested = false;
      if (notice != null) _noticeShown = notice.id;
      _controlsOpen = true;
      _toolsTab = 2;
    });
  }

  Future<void> _dismissNotice(bool snooze) async {
    if (_busy) return;
    final notice = _currentNotice;
    if (snooze && notice != null) {
      try {
        await NativeBridge.action('snoozeNotice', {'id': notice.id});
        final status = await NativeBridge.map('status');
        if (mounted) setState(() => _status = status);
      } catch (e) {
        if (mounted) {
          setState(() => _message = _error(e));
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(_message)));
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _noticeOpen = false;
      _noticeRequested = false;
      if (notice != null) _noticeShown = notice.id;
      _controlsOpen = _noticeOriginOpen;
      _toolsTab = _noticeOriginTab == 2 ? 0 : _noticeOriginTab;
    });
  }

  String _error(Object e) {
    _lastErrorCode = e is PlatformException ? e.code : 'APP_ERROR';
    return e is PlatformException
        ? (e.message ?? 'Thao tác chưa hoàn tất.')
        : e.toString().replaceFirst('Exception: ', '');
  }

  bool _isConnectionOrShizukuError(String msg) {
    final lower = msg.toLowerCase();
    return lower.contains('kết nối') ||
        lower.contains('shizuku') ||
        lower.contains('timeout') ||
        lower.contains('thời gian chờ');
  }

  void _showShizukuTroubleshoot() {
    LocalAdbDialog.show(context, onConnected: () {
      _refresh();
    });
  }

  Future<void> _access() async {
    LocalAdbDialog.show(context, onConnected: () {
      _refresh();
    });
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
    final subscription = NativeBridge.progressEvents.listen((event) {
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
      if (mounted) {
        try {
          _status = await NativeBridge.map('status');
        } catch (_) {}
        setState(() {
          _lastOperation = {
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
            if (!success && !_isPc && _isConnectionOrShizukuError(_message))
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE8C170),
                  foregroundColor: const Color(0xFF161526),
                ),
                icon: const Icon(Icons.build_circle_outlined, size: 16),
                label: const Text('Hướng dẫn sửa lỗi'),
                onPressed: () {
                  Navigator.pop(c);
                  _showShizukuTroubleshoot();
                },
              ),
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
    if (!_isPc &&
        AppUpdateInfo.fromChannel(
              _remote?.data,
              _status['appCode'] as int? ?? 10612,
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
        try {
          setState(() => _downloading = true);
          final path = await NativeBridge.download(_remote!.data);
          if (!mounted) {
            throw Exception('Ứng dụng đã đóng; gói tải được giữ để cài sau.');
          }
          setState(() => _downloading = false);
          return await NativeBridge.map('installPatch', {'path': path});
        } catch (e) {
          if (_isPc) {
            setState(() => _downloading = false);
            return NativeBridge.map('installBundled');
          }
          rethrow;
        }
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
    if (_isPc) {
      final release = _remote;
      final rawUrl = release?.data['app_url'] as String?;
      if (rawUrl != null && rawUrl.isNotEmpty) {
        final uri = Uri.tryParse(rawUrl);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      return;
    }
    final release = _remote;
    if (!resume &&
        AppUpdateInfo.fromChannel(
              release?.data,
              _status['appCode'] as int? ?? 10612,
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
    final subscription = NativeBridge.progressEvents.listen((event) {
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
    if (_busy || !mounted) return;
    if (!(_controlsOpen && _toolsTab == 3)) {
      _settingsOriginOpen = _controlsOpen;
      _settingsOriginTab = _toolsTab;
    }
    _openTools(3);
  }

  void _cancelSettings() {
    if (!mounted || _busy) return;
    setState(() {
      _controlsOpen = _settingsOriginOpen;
      _toolsTab = _settingsOriginTab == 3 ? 0 : _settingsOriginTab;
      _noticeOpen = _controlsOpen && _toolsTab == 2;
    });
  }

  Future<bool> _saveSettings(bool companion, bool auto, String channel) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      final saved = await NativeBridge.action('saveSettings', {
        'channel': channel.trim(),
        'autoDownload': auto,
      });
      if (!saved) throw StateError('Chưa lưu được cài đặt.');
      await _setCompanionVisible(companion);
      final status = await NativeBridge.map('status');
      if (!mounted) return true;
      setState(() {
        _status = status;
        _message = 'Đã lưu cài đặt.';
        _busy = false;
      });
      _cancelSettings();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã lưu cài đặt.')));
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _message = _error(e));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message)));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _copyReport() async {
    try {
      // Startup log capture finishes asynchronously after a failed service bind.
      // Read current diagnostics rather than the UI's earlier status snapshot.
      Map<String, dynamic> reportStatus = _status;
      try {
        reportStatus = await NativeBridge.map('status');
      } catch (_) {}
      await Clipboard.setData(
        ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert({
            'app': reportStatus['appVersion'] ?? '1.6.12',
            'report_time': DateTime.now().toUtc().toIso8601String(),
            'error_code':
                (_lastErrorCode.isNotEmpty ? _lastErrorCode : null) ??
                _game['error_code'] ??
                _lastOperation['error_code'] ??
                'CHUA_CO_LOI',
            'status': reportStatus,
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

  Future<void> _showCompanionChat() async {
    await showDialog<void>(
      context: context,
      builder: (_) => CompanionDialog(
        onCopyError: _copyReport,
        onOpenDeveloper: _openDeveloperProfile,
        onTroubleshoot: _isPc ? null : _showShizukuTroubleshoot,
        onLaunchOverlay: () async {
          try {
            final canDraw = await NativeBridge.canDrawOverlays();
            if (!canDraw) {
              await NativeBridge.requestOverlayPermission();
            } else {
              await NativeBridge.startChibiOverlay();
            }
          } catch (_) {}
        },
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
          if (!didPop && !_busy) _closeTools();
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
        !_isPc &&
        AppUpdateInfo.fromChannel(
              _remote?.data,
              _status['appCode'] as int? ?? 10612,
            ) !=
            null;
    final patchHasUpdate =
        _remote != null &&
        (_game['installed_code'] as int? ?? 0) > 0 &&
        _remote!.code > (_game['installed_code'] as int);
    final label = appNew
        ? 'Cập nhật toàn bộ'
        : recovery
        ? 'Phục hồi dữ liệu'
        : !access || !ready
        ? (_isPc ? 'Chọn thư mục game' : 'Cài tiếng Việt')
        : installed
        ? (_isPc
              ? (patchHasUpdate ? 'Cập nhật bản dịch' : 'VÀO GAME CZN')
              : 'Cập nhật bản dịch')
        : 'Cài tiếng Việt';
    return Scaffold(
      body: CznCompanion(
        // Allow dragging across the screen while keeping the sprite visible.
        dragRegion: (size) {
          final padding = MediaQuery.paddingOf(context);
          return Rect.fromLTRB(
            8,
            padding.top + 8,
            size.width - 8,
            size.height - padding.bottom - 8,
          );
        },
        visible: _showCompanion && !_busy,
        onHide: _hideCompanion,
        onTap: _showCompanionChat,
        child: CznLanding(
          isPc: _isPc,
          patchVersion: latest?.version ?? 'Đang đọc…',
          appVersion: _status['appVersion'] as String? ?? '1.6.12',
          access: access,
          ready: ready,
          installed: installed,
          busy: _busy,
          checking: _checking,
          message: _appUpdateMessage.isNotEmpty ? _appUpdateMessage : _message,
          showMessage:
              _appUpdateMessage.isNotEmpty || _lastErrorCode.isNotEmpty,
          onTroubleshoot: _isPc ? null : _showShizukuTroubleshoot,
          primaryLabel: label,
          onPrimary: _busy || _checking
              ? null
              : () {
                  if (appNew) {
                    unawaited(_updateApp());
                  } else if (recovery && access) {
                    unawaited(_restore());
                  } else if (!access || !ready) {
                    if (_isPc) {
                      NativeBridge.action('chooseGameDir')
                          .then((_) => _refresh());
                    } else {
                      _openTools(0);
                    }
                  } else if (installed && _isPc) {
                    if (patchHasUpdate) {
                      unawaited(_install());
                    } else {
                      unawaited(_launchGame());
                    }
                  } else {
                    unawaited(_install());
                  }
                },
          onSetup: _busy ? null : () => _openTools(0),
          onUpdates: _busy ? null : () => _openTools(1),
          onHelp: _showToolsHelp,
          onSettings: _busy || _checking ? null : _settings,
          onNotice: _busy ? null : () => _maybeNotice(force: true),
        ),
      ),
    );
  }

  Future<void> _launchGame() async {
    try {
      if (!WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
        final prefs = await SharedPreferences.getInstance();
        final overlayPref = prefs.getBool('companion_overlay') ?? true;
        if (overlayPref) {
          final canDraw = await NativeBridge.canDrawOverlays();
          if (canDraw) {
            unawaited(NativeBridge.startChibiOverlay());
          }
        }
      }
      final opened = await NativeBridge.action('launchGame');
      if (!opened) {
        await launchUrl(
          Uri.parse(
            'https://play.google.com/store/apps/details?id=com.smilegate.chaoszero.stove.google',
          ),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = _error(e));
    }
  }

  Future<void> _selectGame(String package) async {
    try {
      await NativeBridge.action('selectGame', {'package': package});
      if (mounted) setState(() => _game = {});
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _message = _error(e));
    }
  }

  Future<void> _showToolsHelp() async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Hướng dẫn và trợ giúp'),
        content: const Text(
          'Sau khi cài, mở game và giữ ngôn ngữ văn bản 日本語. '
          'Khởi động lại Shizuku sau khi điện thoại khởi động. '
          'Khi game cập nhật, app sẽ kiểm tra lại dữ liệu và chờ gói tương thích.',
        ),
        actions: [
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse('https://shizuku.rikka.app/guide/setup/'),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Hướng dẫn Shizuku'),
          ),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse('https://github.com/doubleD1302/CZN-VH'),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Trang dự án'),
          ),
          TextButton(
            onPressed: () => showLicensePage(
              context: c,
              applicationName: 'Chaos Zero Nightmare Việt Hóa',
              applicationVersion: _status['appVersion'] as String? ?? '1.6.12',
            ),
            child: const Text('Giấy phép'),
          ),
          TextButton(
            onPressed: _copyReport,
            child: const Text('Sao chép báo cáo'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
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
    final appVersion = _status['appVersion'] as String? ?? '1.6.12';
    final patchVersion = latest?.version ?? 'Đang đọc…';
    final appUpdate = AppUpdateInfo.fromChannel(
      _remote?.data,
      _status['appCode'] as int? ?? 10612,
    );
    final enabled = !_busy && !_checking;
    final canInstall =
        enabled &&
        access &&
        ready &&
        _bundled != null &&
        _status['package'] != null &&
        !recovery;
    final tab = CznToolsTab.values[_toolsTab];
    final body = switch (tab) {
      CznToolsTab.setup => CznToolsSetupPage(
        status: _status,
        game: _game,
        lastOperation: _lastOperation,
        patchVersion: latest?.version,
        installed: installed,
        recovery: recovery,
        busy: _busy,
        checking: _checking,
        downloading: _downloading,
        progress: _progress,
        message: _message,
        onlineMessage: _onlineMessage,
        onAccess: enabled ? _access : null,
        onCheckGame: enabled ? (access ? _refresh : _access) : null,
        onLaunchGame: enabled ? _launchGame : null,
        onSelectGame: enabled ? (pkg) => unawaited(_selectGame(pkg)) : null,
        onInstall: canInstall ? _install : null,
        onRestore: enabled && access ? _restore : null,
        onLocal: enabled ? _local : null,
        onCopyReport: _copyReport,
        onHelp: _showToolsHelp,
        onCancelDownload: _downloading
            ? () => NativeBridge.action('cancelDownload')
            : null,
      ),
      CznToolsTab.updates => CznToolsUpdatePage(
        appVersion: appVersion,
        patchVersion: patchVersion,
        update: appUpdate,
        pending: _status['pendingAppUpdate'] == true,
        checking: _checking,
        updating: _appUpdating,
        message: _appUpdateMessage,
        onlineMessage: _onlineMessage,
        progress: _progress,
        isPc: _isPc,
        onCheck: enabled ? _refresh : null,
        onUpdate: enabled
            ? () => _updateApp(resume: _status['pendingAppUpdate'] == true)
            : null,
        onCancel: _downloading
            ? () => NativeBridge.action('cancelDownload')
            : null,
      ),
      CznToolsTab.notice => CznToolsNoticePage(
        notice: _currentNotice,
        appVersion: appVersion,
        busy: _busy,
        onDismiss: (snooze) => unawaited(_dismissNotice(snooze)),
      ),
      CznToolsTab.settings => CznToolsSettingsPage(
        companionVisible: _showCompanion,
        autoDownload: _status['autoDownload'] != false,
        channel: _status['channel'] as String? ?? 'https://github.com/doubleD1302/CZN-VH/releases/latest/download/channel.json',
        appVersion: appVersion,
        patchVersion: patchVersion,
        busy: _busy,
        overlayActive: _status['overlayRunning'] == true,
        onSave: _saveSettings,
        onCancel: _cancelSettings,
      ),
    };
    const titles = ['THIẾT LẬP', 'CẬP NHẬT', 'THÔNG BÁO', 'CÀI ĐẶT'];
    const subtitles = [
      'Chuẩn bị để cài tiếng Việt',
      'Ứng dụng và bản dịch',
      'Bản tin cộng đồng',
      'Tùy chỉnh ứng dụng',
    ];
    return CznToolsBackdrop(
      child: CznToolsScaffold(
        activeTab: tab,
        title: titles[_toolsTab],
        subtitle: subtitles[_toolsTab],
        appVersion: appVersion,
        navigationEnabled: !_busy,
        onBack: _closeTools,
        onTabChanged: _selectToolsTab,
        child: body,
      ),
    );
  }
}
