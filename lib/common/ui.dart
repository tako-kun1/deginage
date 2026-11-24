import 'package:flutter/material.dart';

import '../src/rust/api/models.dart';

/// アプリケーションのバージョン
const String kAppVersion = '1.0.0';

/// 日本語表示用のフォントフォールバック
const List<String> kFontFallback = [
  'Yu Gothic UI',
  'Meiryo',
  'Noto Sans CJK JP',
  'Noto Sans JP',
  'IPAexGothic',
  'TakaoPGothic',
];

ThemeData buildTheme({Brightness brightness = Brightness.light}) {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1565C0),
      brightness: brightness,
    ),
    useMaterial3: true,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: kFontFallback),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamilyFallback: kFontFallback,
    ),
  );
}

String transitionLabel(TransitionKind k) => switch (k) {
  TransitionKind.none => 'なし',
  TransitionKind.crossFade => 'クロスフェード',
  TransitionKind.fadeThroughBlack => '黒フェード',
  TransitionKind.slideLeft => 'スライド（左へ）',
  TransitionKind.slideRight => 'スライド（右へ）',
  TransitionKind.slideUp => 'スライド（上へ）',
  TransitionKind.slideDown => 'スライド（下へ）',
  TransitionKind.zoomIn => 'ズームイン',
  TransitionKind.zoomOut => 'ズームアウト',
  TransitionKind.wipe => 'ワイプ',
};

String fitLabel(FitMode f) => switch (f) {
  FitMode.contain => '全体を表示',
  FitMode.cover => '画面を埋める',
  FitMode.fill => '引き伸ばし',
};

BoxFit toBoxFit(FitMode f) => switch (f) {
  FitMode.contain => BoxFit.contain,
  FitMode.cover => BoxFit.cover,
  FitMode.fill => BoxFit.fill,
};

const List<String> kWeekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

String weekdayMaskLabel(int mask) {
  if (mask & 0x7F == 0 || mask & 0x7F == 0x7F) return '毎日';
  if (mask & 0x7F == 0x1F) return '平日';
  if (mask & 0x7F == 0x60) return '土日';
  return [
    for (var i = 0; i < 7; i++)
      if (mask & (1 << i) != 0) kWeekdayLabels[i],
  ].join('・');
}

const List<String> kImageExtensions = [
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
];

const List<String> kVideoExtensions = [
  'mp4',
  'm4v',
  'mov',
  'mkv',
  'webm',
  'avi',
  'wmv',
  'mpg',
  'mpeg',
  'ts',
];

MediaKind? mediaKindForPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = path.substring(dot + 1).toLowerCase();
  if (kImageExtensions.contains(ext)) return MediaKind.image;
  if (kVideoExtensions.contains(ext)) return MediaKind.video;
  return null;
}

String fileNameOf(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}
