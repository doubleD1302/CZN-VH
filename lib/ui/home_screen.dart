import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/native_bridge.dart';
import '../services/notice_policy.dart';
import '../services/patch_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Map<String, dynamic> _status = {}, _game = {};
  ReleaseInfo? _bundled, _remote;
  bool _busy = false, _checking = false, _downloading = false;
  String _message = 'Đang chuẩn bị ứng dụng…', _onlineMessage = '';
  double _progress = 0;
  bool _refreshPending = false, _noticeOpen = false, _noticeRequested = true;
  String? _noticeShown;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
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
        _message = 'Sẵn sàng';
      });
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
                (_status['appCode'] as int? ?? 10401);
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
        }
      }
    }
  }

  Future<void> _maybeNotice({bool force = false}) async {
    final data = _remote?.data;
    final notice = CommunityNotice.fromChannel(
      data != null && data.containsKey('notice') ? data : _bundled?.data ?? {},
    );
    if (!mounted || _noticeOpen || notice == null) return;
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

  String _error(Object e) => e is PlatformException
      ? (e.message ?? 'Thao tác chưa hoàn tất.')
      : e.toString().replaceFirst('Exception: ', '');
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
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _message = 'Đang chuẩn bị…';
    });
    final subscription = NativeBridge.progress.receiveBroadcastStream().listen((
      event,
    ) {
      if (mounted) {
        final data = Map<String, dynamic>.from(event as Map);
        setState(() {
          _message = data['label'] as String;
          _progress = (data['percent'] as num).toDouble() / 100;
        });
      }
    }, onError: (_) {});
    try {
      final response = await operation();
      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Thao tác chưa hoàn tất.');
      }
      final game = scanGame ? await NativeBridge.map('scanGame') : _game;
      if (mounted) {
        setState(() {
          _game = game;
          _message =
              response['message'] as String? ??
              (response.containsKey('version')
                  ? 'Đã cài tiếng Việt ${response['version']}. Chọn 日本語 trong game.'
                  : 'Đã khôi phục đầy đủ dữ liệu trước cài.');
          _progress = 1;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = _error(e));
    } finally {
      await subscription.cancel();
      if (mounted) {
        try {
          _status = await NativeBridge.map('status');
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _downloading = false;
        });
      }
    }
  }

  Future<void> _install() async {
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
    if (confirm == true) await _run(() => NativeBridge.map('restore'));
  }

  Future<void> _updateApp() async {
    final release = _remote;
    if (release == null) return;
    await _run(() async {
      setState(() => _downloading = true);
      final path = await NativeBridge.download(release.data, apk: true);
      if (mounted) setState(() => _downloading = false);
      await NativeBridge.action('installApp', {'path': path});
      return {
        'success': true,
        'message': 'Đã mở trình cài cập nhật ứng dụng. Xác nhận trên màn hình Android.',
      };
    }, scanGame: false);
  }

  Future<void> _settings() async {
    final controller = TextEditingController(
      text: _status['channel'] as String?,
    );
    bool auto = _status['autoDownload'] != false;
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Cập nhật tự động'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tự tải bản mới qua Wi-Fi'),
                  subtitle: const Text(
                    'Kiểm tra mỗi 12 giờ. Thông báo khi đã tải xong; bấm cài để áp dụng.',
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

  Future<void> _copyReport() async {
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert({
          'app': _status['appVersion'] ?? '1.4.1',
          'status': _status,
          'game': _game,
          'message': _message,
        }),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã sao chép báo cáo để gửi hỗ trợ.')),
      );
    }
  }

  Widget _step(
    int n,
    String title,
    String description,
    Widget? action, {
    bool done = false,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: done ? const Color(0xFF34D399) : Colors.white54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$n. $title',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(color: Colors.white70, height: 1.5),
          ),
          if (action != null) ...[const SizedBox(height: 14), action],
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final access = _status['accessGranted'] == true;
    final installed =
        _game['files_match'] == true && _game['installed_version'] != null;
    final recovery =
        _game['recovery_required'] == true ||
        _status['recoveryPending'] == true;
    final latest =
        _remote != null && (_bundled == null || _remote!.code >= _bundled!.code)
        ? _remote
        : _bundled;
    final hasUpdate =
        latest != null &&
        latest.newerThan((_game['installed_code'] as int?) ?? 0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('CZN Việt Hóa'),
        actions: [
          IconButton(
            tooltip: 'Thông báo cộng đồng',
            onPressed: _busy ? null : () => _maybeNotice(force: true),
            icon: const Icon(Icons.campaign_outlined),
          ),
          IconButton(
            tooltip: 'Kiểm tra cập nhật',
            onPressed: _busy || _checking ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Cài đặt cập nhật',
            onPressed: _busy ? null : _settings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            'Chơi CZN bằng tiếng Việt',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Thiết lập một lần. Bản dịch mới được tự tải qua Wi-Fi.',
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
          const SizedBox(height: 20),
          if (installed)
            Card(
              color: const Color(0xFF16372E),
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
            access ? 'Đã cấp quyền. App có thể kiểm tra dữ liệu game.' : 'Cài Shizuku, khởi động bằng gỡ lỗi không dây rồi cấp quyền cho CZN Việt Hóa. Android 8–10 cần máy tính để khởi động Shizuku.',
            access
                ? null
                : FilledButton.tonal(
                    onPressed: _busy ? null : _access,
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
                    onChanged: _busy
                        ? null
                        : (pkg) async {
                            await NativeBridge.action('selectGame', {
                              'package': pkg,
                            });
                            if (mounted) setState(() => _game = {});
                            await _refresh();
                          },
                  ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          try {
                            final opened = await NativeBridge.action(
                              'launchGame',
                            );
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
                    child: const Text('Sao chép báo cáo lỗi bước 2'),
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
                      _bundled == null ||
                      _status['package'] == null ||
                      _game['success'] != true ||
                      recovery
                  ? null
                  : _install,
              icon: const Icon(Icons.download_done),
              label: Text(
                installed
                    ? (hasUpdate ? 'Cập nhật bản dịch' : 'Cài lại bản dịch')
                    : 'Cài tiếng Việt',
              ),
            ),
            done: installed,
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(_message, style: const TextStyle(height: 1.5)),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress),
            if (_downloading)
              TextButton(
                onPressed: () => NativeBridge.action('cancelDownload'),
                child: const Text('Hủy tải'),
              ),
          ],
          if (_checking) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (_onlineMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_onlineMessage, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _local,
                icon: const Icon(Icons.folder_open),
                label: const Text('Cài từ gói tải sẵn'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || !access ? null : _restore,
                icon: const Icon(Icons.restore),
                label: Text(recovery ? 'Phục hồi giao dịch' : 'Khôi phục gốc'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy || _checking ? null : _refresh,
            icon: const Icon(Icons.system_update_alt),
            label: const Text('Kiểm tra cập nhật'),
          ),
          if (_remote != null &&
              _remote!.code >
                  (_game['installed_code'] as int? ?? _bundled?.code ?? 0))
            FilledButton.tonal(
              onPressed: _busy || _status['package'] == null ? null : _install,
              child: const Text('Tải và cập nhật bản dịch'),
            ),
          if (_remote != null &&
              (_remote!.data['app_code'] as int? ?? 0) >
                  (_status['appCode'] as int? ?? 10400)) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _busy ? null : _updateApp,
              child: const Text('Cập nhật ứng dụng'),
            ),
          ],
          const SizedBox(height: 20),
          Card(
            child: ExpansionTile(
              title: const Text('Hướng dẫn và trợ giúp'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                      child: const Text('Dự án và bản phát hành'),
                    ),
                    TextButton(
                      onPressed: () => showLicensePage(
                        context: context,
                        applicationName: 'CZN Việt Hóa',
                        applicationVersion:
                            _status['appVersion'] as String? ?? '1.4.1',
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
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'CZN Việt Hóa · 1.4.1',
              style: TextStyle(color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }
}
