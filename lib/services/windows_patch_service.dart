import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WindowsPatchService {
  static final WindowsPatchService instance = WindowsPatchService._();
  WindowsPatchService._();

  static const String currentVersion = '1.3.5';
  static const int currentVersionCode = 10305;

  String? _cachedGameDir;
  Map<String, dynamic> _lastOp = {};
  HttpClient? _downloadClient;

  final StreamController<Map<String, dynamic>> _progressController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get progressStream => _progressController.stream;

  void emitProgress(String label, [int percent = 50]) {
    _progressController.add({'label': label, 'percent': percent});
  }

  Future<String> getGameDirectory() async {
    if (_cachedGameDir != null && _cachedGameDir!.isNotEmpty) {
      if (isValidGameDir(_cachedGameDir!)) return _cachedGameDir!;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('game_dir');
    if (saved != null && saved.isNotEmpty && isValidGameDir(saved)) {
      _cachedGameDir = saved;
      return saved;
    }

    // Auto-detect standard candidates
    final candidates = [
      r'C:\ProgramData\Smilegate\Games\ChaosZeroNightmare',
      Directory.current.path,
      File(Platform.resolvedExecutable).parent.path,
      File(Platform.resolvedExecutable).parent.parent.path,
      File(Platform.resolvedExecutable).parent.parent.parent.path,
      r'D:\Games\ChaosZeroNightmare',
      r'E:\Games\ChaosZeroNightmare',
    ];

    for (final dir in candidates) {
      if (isValidGameDir(dir)) {
        _cachedGameDir = dir;
        await prefs.setString('game_dir', dir);
        return dir;
      }
    }

    _cachedGameDir = candidates.first;
    return candidates.first;
  }

  Future<void> setGameDirectory(String dir) async {
    _cachedGameDir = dir;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('game_dir', dir);
  }

  bool isValidGameDir(String path) {
    final manifest = File('$path/bin/appdata/cznlive/gameres/manifest.ssra');
    return manifest.existsSync();
  }

  Future<String?> chooseGameDirectory() async {
    final current = await getGameDirectory();
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: 'Chọn thư mục cài đặt Chaos Zero Nightmare',
      initialDirectory: current,
    );
    if (selected != null && selected.isNotEmpty) {
      await setGameDirectory(selected);
      return selected;
    }
    return null;
  }

  String _findProjectHome() {
    final appDir = File(Platform.resolvedExecutable).parent;
    final candidates = [
      r'C:\ProgramData\Smilegate\Games\ChaosZeroNightmare\CZN_VietHoa_Project',
      '${Directory.current.path}/CZN_VietHoa_Project',
      Directory.current.path,
      '${appDir.path}/CZN_VietHoa_Project',
      appDir.parent.path,
      appDir.parent.parent.path,
    ];
    for (final c in candidates) {
      if (File('$c/data/translations.json').existsSync()) {
        return c;
      }
    }
    return candidates.first;
  }

  String _findBackendExe() {
    final appDir = File(Platform.resolvedExecutable).parent;
    final candidates = [
      '${appDir.path}/czn_core.exe',
      '${appDir.path}/data/czn_core.exe',
      '${_findProjectHome()}/tools/czn_core.exe',
      r'C:\ProgramData\Smilegate\Games\ChaosZeroNightmare\CZN_VietHoa_Project\tools\czn_core.exe',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return '';
  }

  Future<ProcessResult> _runBackendCommand(String command, String gameDir) async {
    final projectHome = _findProjectHome();
    final backendExe = _findBackendExe();
    final scriptCandidate = File('$projectHome/tools/czn_cli.py');

    if (backendExe.isNotEmpty) {
      return await Process.run(
        backendExe,
        [command, '--game', gameDir, '--project', projectHome],
        runInShell: false,
      );
    }

    // Fallback to python
    return await Process.run(
      'python',
      [scriptCandidate.path, command, '--game', gameDir, '--project', projectHome],
      runInShell: true,
      environment: {
        'PYTHONPATH': '$projectHome/tools;$projectHome/tools/vendor',
      },
    );
  }

  Future<Map<String, dynamic>> getStatus() async {
    final gameDir = await getGameDirectory();
    final valid = isValidGameDir(gameDir);

    return {
      'accessGranted': true,
      'package': 'smilegate.czn.pc',
      'shizukuRunning': true,
      'appCode': 999999,
      'appVersion': currentVersion,
      'gameDir': gameDir,
      'ready': valid,
    };
  }

  Future<Map<String, dynamic>> getBundledInfo() async {
    return {
      'version': currentVersion,
      'version_code': currentVersionCode,
      'changelog':
          '• Việt hóa toàn bộ cốt truyện Chương 1, 2, 3, 4\n'
          '• Toàn bộ kỹ năng, thẻ bài, vật phẩm, hướng dẫn, hệ thống\n'
          '• Cơ chế cài đặt Atomic và phục hồi bản gốc an toàn 100%',
    };
  }

  Future<Map<String, dynamic>> scanGame() async {
    final gameDir = await getGameDirectory();
    if (!isValidGameDir(gameDir)) {
      return {
        'success': false,
        'installed': false,
        'message':
            'Chưa tìm thấy game tại: $gameDir. Bấm "Thiết lập" để chọn đúng thư mục cài đặt game.',
      };
    }

    try {
      final res = await _runBackendCommand('status', gameDir);
      if (res.exitCode == 0) {
        final lines = res.stdout.toString().trim().split('\n');
        for (final line in lines.reversed) {
          final trimmed = line.trim();
          if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
            try {
              final json = jsonDecode(trimmed) as Map<String, dynamic>;
              if (json['installed'] == true) {
                json['installed_version'] = currentVersion;
                json['installed_code'] = currentVersionCode;
                json['files_match'] = true;
                json['recovery_required'] = false;
              }
              return json;
            } catch (_) {}
          }
        }
      }
      return {
        'success': false,
        'installed': false,
        'message': 'Không thể kiểm tra file game: ${res.stderr}',
      };
    } catch (e) {
      return {
        'success': false,
        'installed': false,
        'message': 'Lỗi quét dữ liệu: $e',
      };
    }
  }

  Future<Map<String, dynamic>> getLastOperation() async => _lastOp;

  void cancelDownload() {
    _downloadClient?.close(force: true);
    _downloadClient = null;
  }

  Future<Map<String, dynamic>> getCachedChannel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('cached_channel');
      if (str != null && str.isNotEmpty) {
        return jsonDecode(str) as Map<String, dynamic>;
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> checkUpdate() async {
    try {
      final uri = Uri.parse(
        'https://github.com/doubleD1302/CZN-VH/releases/latest/download/channel.json',
      );
      final client = http.Client();
      final response = await client.get(
        uri,
        headers: {'User-Agent': 'CZN-Windows-Launcher'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final root = jsonDecode(response.body) as Map<String, dynamic>;
        Map<String, dynamic> channelData = {};
        if (root.containsKey('signed')) {
          final decoded = utf8.decode(base64Decode(root['signed'] as String));
          channelData = jsonDecode(decoded) as Map<String, dynamic>;
        } else {
          channelData = root;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_channel', jsonEncode(channelData));
        return channelData;
      }
    } catch (_) {}

    return await getCachedChannel();
  }

  Future<String> downloadPatch(Map<String, dynamic> info) async {
    final urlStr = info['patch_url'] as String? ?? '';
    if (urlStr.isEmpty) {
      throw Exception('Không tìm thấy đường dẫn tải gói cập nhật.');
    }
    final uri = Uri.parse(urlStr);
    final tempDir = Directory.systemTemp;
    final patchCode = info['patch_code']?.toString() ?? 'latest';
    final targetFile = File('${tempDir.path}/CZN_Update_$patchCode.cznpatch');

    emitProgress('Bắt đầu tải gói Việt hóa mới từ GitHub...', 5);
    final client = HttpClient();
    _downloadClient = client;

    try {
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'CZN-Windows-Launcher');
      final response = await request.close();

      if (response.statusCode != 200 && response.statusCode != 302) {
        throw Exception('Máy chủ GitHub phản hồi lỗi HTTP ${response.statusCode}');
      }

      // Handle redirect if any
      Stream<List<int>> byteStream = response;
      int totalBytes = response.contentLength;
      if (response.isRedirect) {
        final redirectUrl = response.headers.value(HttpHeaders.locationHeader);
        if (redirectUrl != null) {
          final redirectReq = await client.getUrl(Uri.parse(redirectUrl));
          final redirectResp = await redirectReq.close();
          totalBytes = redirectResp.contentLength;
          byteStream = redirectResp;
        }
      }

      var receivedBytes = 0;
      final sink = targetFile.openWrite();

      await for (final chunk in byteStream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final percent = ((receivedBytes / totalBytes) * 100).clamp(5, 95).toInt();
          final mbDownloaded = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
          emitProgress('Đang tải bản cập nhật: $mbDownloaded / $mbTotal MB ($percent%)', percent);
        } else {
          emitProgress('Đang tải dữ liệu: ${(receivedBytes / (1024 * 1024)).toStringAsFixed(1)} MB...', 50);
        }
      }
      await sink.flush();
      await sink.close();

      // Check SHA256 if provided
      final expectedSha = info['patch_sha256'] as String?;
      if (expectedSha != null && expectedSha.length == 64) {
        emitProgress('Đang xác minh tính toàn vẹn (SHA256)...', 98);
        final digest = sha256.convert(await targetFile.readAsBytes()).toString();
        if (digest.toLowerCase() != expectedSha.toLowerCase()) {
          throw Exception('Checksum SHA256 không khớp! File có thể bị lỗi khi tải.');
        }
      }

      emitProgress('Tải bản cập nhật hoàn tất!', 100);
      return targetFile.path;
    } finally {
      _downloadClient = null;
      client.close();
    }
  }

  Future<Map<String, dynamic>> installPatch({String? patchPath}) async {
    final gameDir = await getGameDirectory();
    final projectHome = _findProjectHome();
    final backendExe = _findBackendExe();
    final scriptCandidate = File('$projectHome/tools/czn_cli.py');
    emitProgress(patchPath != null ? 'Đang cài đặt bản cập nhật tải về...' : 'Đang chuẩn bị gói Việt hóa...', 10);

    final args = <String>[
      'install',
      '--game',
      gameDir,
      '--project',
      projectHome,
    ];
    if (patchPath != null && patchPath.isNotEmpty) {
      args.addAll(['--patch', patchPath]);
    }

    Process proc;
    if (backendExe.isNotEmpty) {
      proc = await Process.start(
        backendExe,
        args,
      );
    } else {
      proc = await Process.start(
        'python',
        [scriptCandidate.path, ...args],
        runInShell: true,
        environment: {
          'PYTHONPATH': '$projectHome/tools;$projectHome/tools/vendor',
        },
      );
    }

    var success = false;
    var message = '';

    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final trimmed = line.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        try {
          final map = jsonDecode(trimmed) as Map<String, dynamic>;
          if (map['event'] == 'progress') {
            final m = map['message'] as String? ?? '';
            emitProgress(m, 50);
          } else if (map['event'] == 'done' || map['event'] == 'error') {
            success = map['success'] == true;
            message = map['message'] as String? ?? '';
            emitProgress(message, success ? 100 : 0);
          }
        } catch (_) {}
      } else if (trimmed.isNotEmpty) {
        emitProgress(trimmed, 60);
      }
    });

    final exitCode = await proc.exitCode;
    success = success || (exitCode == 0);
    final msg = message.isNotEmpty
        ? message
        : (success
            ? 'Cài đặt tiếng Việt thành công! Vào game và chọn ngôn ngữ 日本語 để hiển thị.'
            : 'Cài đặt thất bại (mã thoát $exitCode)');

    _lastOp = {
      'success': success,
      'phase': 'done',
      'version': currentVersion,
      'version_code': currentVersionCode,
      'message': msg,
      'post_install': {
        'success': success,
        'installed': success,
        'installed_version': success ? currentVersion : null,
        'installed_code': success ? currentVersionCode : 0,
        'files_match': success,
        'recovery_required': false,
        'message': msg,
      },
    };
    return _lastOp;
  }

  Future<Map<String, dynamic>> restoreOriginal() async {
    final gameDir = await getGameDirectory();
    final projectHome = _findProjectHome();
    final backendExe = _findBackendExe();
    final scriptCandidate = File('$projectHome/tools/czn_cli.py');
    emitProgress('Đang khôi phục file tiếng Nhật gốc...', 20);

    Process proc;
    if (backendExe.isNotEmpty) {
      proc = await Process.start(
        backendExe,
        ['restore', '--game', gameDir, '--project', projectHome],
      );
    } else {
      proc = await Process.start(
        'python',
        [scriptCandidate.path, 'restore', '--game', gameDir, '--project', projectHome],
        runInShell: true,
        environment: {
          'PYTHONPATH': '$projectHome/tools;$projectHome/tools/vendor',
        },
      );
    }

    var success = false;
    var message = '';

    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final trimmed = line.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        try {
          final map = jsonDecode(trimmed) as Map<String, dynamic>;
          if (map['event'] == 'progress') {
            final m = map['message'] as String? ?? '';
            emitProgress(m, 50);
          } else if (map['event'] == 'done' || map['event'] == 'error') {
            success = map['success'] == true;
            message = map['message'] as String? ?? '';
            emitProgress(message, success ? 100 : 0);
          }
        } catch (_) {}
      }
    });

    final exitCode = await proc.exitCode;
    success = success || (exitCode == 0);
    final msg = message.isNotEmpty
        ? message
        : (success ? 'Đã khôi phục file tiếng Nhật gốc thành công!' : 'Khôi phục thất bại');

    _lastOp = {
      'success': success,
      'phase': 'done',
      'message': msg,
      'post_install': {
        'success': success,
        'installed': false,
        'installed_version': null,
        'installed_code': 0,
        'files_match': false,
        'recovery_required': false,
        'message': msg,
      },
    };
    return _lastOp;
  }

  Future<bool> launchGame() async {
    final gameDir = await getGameDirectory();
    final res = await _runBackendCommand('launch', gameDir);
    return res.exitCode == 0;
  }
}
