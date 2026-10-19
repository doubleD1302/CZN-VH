import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dịch vụ vá tiếng Việt và quản lý cập nhật dành riêng cho Windows PC.
/// Phiên bản ứng dụng tách khỏi phiên bản bản dịch trong kênh đã ký.
class WindowsPatchService {
  static const currentVersion = '2.1.17';
  static const currentVersionCode = 20117;
  static const channelUrl =
      'https://github.com/doubleD1302/CZN-VH/releases/download/releases-1.0/windows-channel.json';

  final _progress = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get progressStream => _progress.stream;
  Process? _download;

  String get appDir => File(Platform.resolvedExecutable).parent.path;
  String get home =>
      '${Platform.environment['LOCALAPPDATA']}/DoubleD1302_Launcher/state';

  String get bundle {
    final candidate1 = '$appDir/catalog';
    if (Directory(candidate1).existsSync()) return candidate1;
    const candidate2 =
        r'C:\ProgramData\Smilegate\Games\ChaosZeroNightmare\CZN_VietHoa_Project\data\releases\windows-v1.4.0\catalog';
    if (Directory(candidate2).existsSync()) return candidate2;
    return candidate1;
  }

  String get core {
    final c1 = '$appDir/czn_windows_core.exe';
    if (File(c1).existsSync()) return c1;
    const c2 =
        r'C:\ProgramData\Smilegate\Games\ChaosZeroNightmare\CZN_VietHoa_Project\data\releases\windows-v1.4.0\core\czn_windows_core.exe';
    if (File(c2).existsSync()) return c2;
    return c1;
  }

  /// Kiểm tra tính hợp lệ của thư mục game CZN
  bool isValidGameDir(String dir) {
    if (dir.trim().isEmpty) return false;
    final clean = dir.trim().replaceAll('/', '\\');
    final manifest = File(
      '$clean\\bin\\appdata\\cznlive\\gameres\\manifest.ssra',
    );
    final exe = File('$clean\\ucldr_chaoszeronightmare.exe');
    final chunk1 = File(
      '$clean\\bin\\appdata\\cznlive\\gameres\\chunks\\base_b21_0.ssrc',
    );
    final chunk2 = File('$clean\\chunks\\base_b21_0.ssrc');
    return manifest.existsSync() ||
        exe.existsSync() ||
        chunk1.existsSync() ||
        chunk2.existsSync();
  }

  /// Kiểm tra xem thư mục game đã tải gói Tiếng Nhật (lang_ja_b01_0.ssrc) chưa
  bool hasJapanesePackage(String dir) {
    if (dir.trim().isEmpty) return false;
    final clean = dir.trim().replaceAll('/', '\\');
    final chunk1 = File(
      '$clean\\bin\\appdata\\cznlive\\gameres\\chunks\\lang_ja_b01_0.ssrc',
    );
    final chunk2 = File('$clean\\chunks\\lang_ja_b01_0.ssrc');
    return chunk1.existsSync() || chunk2.existsSync();
  }

  /// Danh sách ứng viên tự động dò tìm
  List<String> get candidateGameDirectories => [
    r'C:\ProgramData\Smilegate\Games\ChaosZeroNightmare',
    r'C:\Program Files\Smilegate\Games\ChaosZeroNightmare',
    r'C:\Program Files (x86)\Smilegate\Games\ChaosZeroNightmare',
    r'C:\Smilegate\Games\ChaosZeroNightmare',
    Directory.current.path,
    File(Platform.resolvedExecutable).parent.path,
    File(Platform.resolvedExecutable).parent.parent.path,
    for (final drive in ['C', 'D', 'E', 'F', 'G']) ...[
      '$drive:\\Games\\ChaosZeroNightmare',
      '$drive:\\Smilegate\\Games\\ChaosZeroNightmare',
      '$drive:\\Program Files\\Smilegate\\Games\\ChaosZeroNightmare',
    ],
  ];

  /// Lấy thư mục game hiện tại (ưu tiên saved > auto-detect)
  Future<String> getGameDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('windows_game_dir');
      if (saved != null && isValidGameDir(saved)) return saved;
    } catch (_) {}

    for (final dir in candidateGameDirectories) {
      if (isValidGameDir(dir)) {
        await setGameDirectory(dir);
        return dir;
      }
    }
    return r'C:\ProgramData\Smilegate\Games\ChaosZeroNightmare';
  }

  /// Lưu thủ công đường dẫn thư mục game
  Future<bool> setGameDirectory(String path) async {
    final clean = path.trim();
    if (!isValidGameDir(clean)) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('windows_game_dir', clean);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Tự động dò tìm thư mục game trên máy tính
  Future<String?> autoDetectGameDirectory() async {
    for (final dir in candidateGameDirectories) {
      if (isValidGameDir(dir)) {
        await setGameDirectory(dir);
        return dir;
      }
    }
    return null;
  }

  /// Mở hộp thoại chọn thư mục (Folder Picker)
  Future<String?> chooseGameDirectory() async {
    final current = await getGameDirectory();
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Chọn thư mục cài đặt ChaosZeroNightmare',
      initialDirectory: Directory(current).existsSync() ? current : null,
    );
    if (dir == null) return null;
    if (!isValidGameDir(dir)) {
      throw Exception(
        'Thư mục này không có dữ liệu game CZN. Hãy chọn thư mục chứa bin/appdata hoặc ucldr_chaoszeronightmare.exe.',
      );
    }
    await setGameDirectory(dir);
    return dir;
  }

  /// Thực thi các tác vụ backend (status, check, install, restore, translation...)
  Future<Map<String, dynamic>> run(String command, {String? token}) async {
    final gameDirectory = await getGameDirectory();
    final coreExe = File(core);
    Process process;

    if (coreExe.existsSync()) {
      process = await Process.start(coreExe.path, [
        command,
        '--home',
        home,
        '--game',
        gameDirectory,
        '--bundle',
        bundle,
        '--parent-pid',
        '$pid',
        if (token != null) ...['--token', token],
      ]);
    } else {
      // Fallback khi chạy trong môi trường phát triển / debug chưa đóng gói core
      const pyScript =
          r'C:\ProgramData\Smilegate\Games\ChaosZeroNightmare\CZN_VietHoa_Project\tools\windows_launcher.py';
      if (!File(pyScript).existsSync()) {
        throw Exception(
          'Thiếu bộ xử lý Windows. Vui lòng đảm bảo tệp czn_windows_core.exe nằm cùng thư mục launcher.',
        );
      }
      process = await Process.start('python', [
        pyScript,
        command,
        '--home',
        home,
        '--game',
        gameDirectory,
        '--bundle',
        bundle,
        '--parent-pid',
        '$pid',
        if (token != null) ...['--token', token],
      ]);
    }

    if (['check', 'translation', 'update-launcher'].contains(command)) {
      _download = process;
    }

    Map<String, dynamic>? result;
    final errors = process.stderr.transform(utf8.decoder).join();
    try {
      await for (final line
          in process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        try {
          final data = jsonDecode(line) as Map<String, dynamic>;
          if (data['event'] == 'progress') _progress.add(data);
          if (data['event'] == 'result') result = data;
        } catch (_) {}
      }
      final code = await process.exitCode;
      final error = await errors;
      if (result == null) {
        throw Exception(
          error.isEmpty
              ? 'Thao tác dừng trước khi trả kết quả (mã $code).'
              : error,
        );
      }
      if (code != 0 || result['success'] != true) {
        throw Exception(result['message'] ?? 'Thao tác chưa hoàn tất.');
      }
      return result;
    } finally {
      if (identical(_download, process)) _download = null;
    }
  }

  void cancelDownload() {
    _download?.kill();
  }

  Future<Map<String, dynamic>> translationInfo() async {
    final active = File('$home/translation.json');
    final source = active.existsSync() ? active : File('$bundle/release.json');
    if (source.existsSync()) {
      try {
        return jsonDecode(await source.readAsString()) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {'version': '1.6.11', 'code': 10611};
  }

  Future<void> launchChibiOverlay() async {
    final currentDir = Directory.current.path;
    final candidates = [
      '$currentDir/czn_chibi_overlay.exe',
      '${Platform.environment['LOCALAPPDATA']}/DoubleD1302_Launcher/czn_chibi_overlay.exe',
      'C:/ProgramData/Smilegate/Games/ChaosZeroNightmare/CZN_VietHoa_Project/data/releases/windows-launcher-1.0/czn_chibi_overlay.exe',
    ];
    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) {
        await Process.start(file.path, [], workingDirectory: file.parent.path);
        return;
      }
    }
  }

  Future<void> launchGame({bool launchOverlay = true}) async {
    if (launchOverlay) {
      try {
        await launchChibiOverlay();
      } catch (_) {}
    }
    final game = await getGameDirectory();
    final exe = File('$game/ucldr_chaoszeronightmare.exe');
    if (exe.existsSync()) {
      await Process.start(exe.path, [], workingDirectory: game);
    } else {
      await Process.run('explorer.exe', ['stove://run/93']);
    }
  }
}
