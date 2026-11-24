import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'settings/settings_app.dart';
import 'signage/signage_app.dart';
import 'src/rust/frb_generated.dart';

/// エントリーポイント
///
/// - 引数なし: 設定画面を起動
/// - `--signage`: サイネージ表示ウィンドウを起動
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await RustLib.init();
  await windowManager.ensureInitialized();

  if (args.contains('--signage')) {
    await startSignage(args);
  } else {
    await startSettings();
  }
}
