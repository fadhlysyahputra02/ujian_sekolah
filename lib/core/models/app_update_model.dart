class AppUpdateInfo {
  final String latestVersion;
  final int latestBuildNumber;
  final String apkUrl;
  final String releaseNotes;
  final bool forceUpdate;
  final int minBuildNumber;

  AppUpdateInfo({
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.apkUrl,
    required this.releaseNotes,
    this.forceUpdate = false,
    this.minBuildNumber = 0,
  });

  factory AppUpdateInfo.fromMap(Map<String, dynamic> map) {
    return AppUpdateInfo(
      latestVersion: map['latest_version'] ?? '1.0.0',
      latestBuildNumber: (map['latest_build_number'] ?? 0) is int
          ? (map['latest_build_number'] ?? 0)
          : int.tryParse(map['latest_build_number'].toString()) ?? 0,
      apkUrl: map['apk_url'] ?? '',
      releaseNotes: map['release_notes'] ?? 'Pembaruan aplikasi terbaru tersedia.',
      forceUpdate: map['force_update'] ?? false,
      minBuildNumber: (map['min_build_number'] ?? 0) is int
          ? (map['min_build_number'] ?? 0)
          : int.tryParse(map['min_build_number'].toString()) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latest_version': latestVersion,
      'latest_build_number': latestBuildNumber,
      'apk_url': apkUrl,
      'release_notes': releaseNotes,
      'force_update': forceUpdate,
      'min_build_number': minBuildNumber,
    };
  }
}
