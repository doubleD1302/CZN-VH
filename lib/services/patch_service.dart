class ReleaseInfo {
  final String version;
  final int code;
  final String changelog;
  final Map<String, dynamic> data;
  ReleaseInfo({
    required this.version,
    required this.code,
    required this.changelog,
    required this.data,
  });
  factory ReleaseInfo.bundled(Map<String, dynamic> data) => ReleaseInfo(
    version: data['version'] as String,
    code: data['version_code'] as int,
    changelog: data['changelog'] as String,
    data: data,
  );
  factory ReleaseInfo.channel(Map<String, dynamic> data) => ReleaseInfo(
    version: data['patch_version'] as String,
    code: data['patch_code'] as int,
    changelog: data['changelog'] as String,
    data: data,
  );
  bool newerThan(int installed) => code > installed;
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.code,
    required this.size,
  });
  final String version;
  final int code, size;
  String get sizeLabel => '${(size / 1048576).toStringAsFixed(1)} MB';

  static AppUpdateInfo? fromChannel(
    Map<String, dynamic>? data,
    int installedCode,
  ) {
    if (data == null) return null;
    final version = data['app_version'],
        code = data['app_code'],
        size = data['app_size'];
    final rawUrl = data['app_url'];
    if (rawUrl is! String) return null;
    final url = Uri.tryParse(rawUrl);
    final hash = data['app_sha256'];
    if (version is! String ||
        version.trim().isEmpty ||
        code is! int ||
        code <= installedCode ||
        code > 2147483647 ||
        size is! int ||
        size <= 0 ||
        size > 157286400 ||
        url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      return null;
    }
    return AppUpdateInfo(version: version, code: code, size: size);
  }
}
