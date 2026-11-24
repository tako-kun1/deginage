import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:screen_retriever/screen_retriever.dart';

/// 接続中のモニター一覧
Future<List<Display>> listDisplays() async {
  try {
    return await screenRetriever.getAllDisplays();
  } catch (_) {
    return [];
  }
}

String displayLabel(Display d, int index) {
  final name = (d.name == null || d.name!.isEmpty)
      ? 'モニター ${index + 1}'
      : d.name!;
  final w = d.size.width.round();
  final h = d.size.height.round();
  final pos = d.visiblePosition;
  final p = pos == null ? '' : ' @(${pos.dx.round()}, ${pos.dy.round()})';
  return '$name  ${w}x$h$p';
}

/// 音声出力デバイス一覧（mpv が認識するデバイス）
Future<List<AudioDevice>> listAudioDevices() async {
  final player = Player();
  try {
    var devices = player.state.audioDevices;
    if (devices.length <= 1) {
      devices = await player.stream.audioDevices
          .firstWhere((d) => d.length > 1)
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () => player.state.audioDevices,
          );
    }
    return devices;
  } catch (_) {
    return [AudioDevice.auto()];
  } finally {
    await player.dispose();
  }
}

String audioDeviceLabel(AudioDevice d) {
  if (d.name == 'auto') return '既定のデバイス（自動）';
  if (d.description.isEmpty) return d.name;
  return d.description;
}
