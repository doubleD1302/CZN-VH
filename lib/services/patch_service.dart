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
