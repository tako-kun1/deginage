import 'dart:io';

import '../src/rust/api/config.dart' as rcfg;

/// サイネージ表示プロセスの起動・停止を管理する
class SignageLauncher {
  SignageLauncher._();

  /// サイネージが動作中か
  static bool isRunning() {
    final targetPid = rcfg.readSignagePid();
    if (targetPid == null) return false;
    if (isProcessAlive(targetPid, requireSignageArg: true)) return true;
    rcfg.clearSignagePid();
    return false;
  }

  static bool isProcessAlive(int targetPid, {bool requireSignageArg = false}) {
    try {
      if (Platform.isLinux) {
        final cmd = File('/proc/$targetPid/cmdline');
        if (!cmd.existsSync()) return false;
        return !requireSignageArg ||
            cmd.readAsStringSync().contains('--signage');
      }
      if (Platform.isWindows) {
        final r = Process.runSync('tasklist', [
          '/FI',
          'PID eq $targetPid',
          '/NH',
          '/FO',
          'CSV',
        ]);
        return r.stdout.toString().contains('"$targetPid"');
      }
    } catch (_) {}
    return false;
  }

  /// サイネージを起動する（既に起動していれば何もしない）
  static Future<void> start() async {
    if (isRunning()) return;
    await Process.start(Platform.resolvedExecutable, [
      '--signage',
      '--parent-pid=$pid',
    ], mode: ProcessStartMode.detached);
  }

  /// サイネージを停止する
  static Future<void> stop() async {
    final targetPid = rcfg.readSignagePid();
    if (targetPid != null &&
        isProcessAlive(targetPid, requireSignageArg: true)) {
      Process.killPid(targetPid);
    }
    rcfg.clearSignagePid();
  }

  static Future<void> restart() async {
    await stop();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await start();
  }
}
