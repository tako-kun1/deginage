import 'dart:io';

import '../src/rust/api/config.dart' as rcfg;

/// サイネージの動作ログ（設定ディレクトリの signage.log に追記）
class SignageLog {
  SignageLog._();

  static File? _file;
  static const int _maxBytes = 1024 * 1024;

  static File get _logFile {
    final f = _file ??= File(
      '${rcfg.configDirectory()}${Platform.pathSeparator}signage.log',
    );
    return f;
  }

  static void write(String message) {
    try {
      final f = _logFile;
      if (f.existsSync() && f.lengthSync() > _maxBytes) {
        f.writeAsStringSync('');
      }
      final ts = DateTime.now().toIso8601String();
      f.writeAsStringSync('$ts $message\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}
