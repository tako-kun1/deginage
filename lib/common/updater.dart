import 'dart:convert';
import 'dart:io';

import 'ui.dart';

/// GitHub Releases の最新リリース情報
class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.hasUpdate,
  });

  final String tagName;
  final String version;
  final String name;
  final String body;
  final String htmlUrl;
  final bool hasUpdate;
}

/// GitHub Release ページからアップデートを確認するユーティリティ
class AppUpdater {
  AppUpdater._();

  static const String repoOwner = 'tako-kun1';
  static const String repoName = 'deginage';
  static const String releasesPageUrl =
      'https://github.com/$repoOwner/$repoName/releases';

  static final Uri _latestApiUri = Uri.https(
    'api.github.com',
    '/repos/$repoOwner/$repoName/releases/latest',
  );

  /// 最新リリースを取得し、現在のバージョンより新しいか判定する。
  /// リリースが未公開 (404) の場合は `null` を返す。
  static Future<ReleaseInfo?> checkForUpdate({
    String currentVersion = kAppVersion,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'Deginage/$currentVersion';
    try {
      final req = await client.getUrl(_latestApiUri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode == HttpStatus.notFound) {
        return null;
      }
      if (res.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub API エラー (HTTP ${res.statusCode})');
      }
      final raw = await res.transform(utf8.decoder).join();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String? ?? '').trim();
      if (tag.isEmpty) return null;
      final version = normalizeVersion(tag);
      final htmlUrl = (json['html_url'] as String? ?? releasesPageUrl).trim();
      final name = (json['name'] as String? ?? tag).trim();
      final body = (json['body'] as String? ?? '').trim();
      return ReleaseInfo(
        tagName: tag,
        version: version,
        name: name.isEmpty ? tag : name,
        body: body,
        htmlUrl: htmlUrl.isEmpty ? releasesPageUrl : htmlUrl,
        hasUpdate: isNewerVersion(currentVersion, version),
      );
    } finally {
      client.close(force: true);
    }
  }

  /// 先頭の `v` / `V` やビルドメタデータ `+...` を除いたバージョン文字列を返す
  static String normalizeVersion(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1);
    }
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    return s;
  }

  /// `latest` が `current` より新しいバージョンか判定する
  static bool isNewerVersion(String current, String latest) {
    final c = _parseSemver(current);
    final l = _parseSemver(latest);
    for (var i = 0; i < 3; i++) {
      if (l.nums[i] != c.nums[i]) return l.nums[i] > c.nums[i];
    }
    // 同じメジャー.マイナー.パッチなら、プレリリース無し（正式版）の方が新しい
    if (c.pre.isNotEmpty && l.pre.isEmpty) return true;
    if (c.pre.isEmpty && l.pre.isNotEmpty) return false;
    return l.pre.compareTo(c.pre) > 0;
  }

  static ({List<int> nums, String pre}) _parseSemver(String raw) {
    final s = normalizeVersion(raw);
    final dash = s.indexOf('-');
    final core = dash >= 0 ? s.substring(0, dash) : s;
    final pre = dash >= 0 ? s.substring(dash + 1) : '';
    final parts = core.split('.');
    final nums = List<int>.generate(
      3,
      (i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0,
    );
    return (nums: nums, pre: pre);
  }

  /// OS の既定ブラウザで URL を開く
  static Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [url]);
    }
  }
}
