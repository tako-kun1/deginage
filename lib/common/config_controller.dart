import 'dart:async';

import 'package:flutter/foundation.dart';

import '../src/rust/api/config.dart' as rcfg;
import '../src/rust/api/models.dart';

/// 設定の保持と自動保存を担うコントローラー（設定画面用）
class ConfigController extends ChangeNotifier {
  ConfigController() : config = rcfg.loadConfig();

  AppConfig config;
  String? lastError;
  Timer? _saveTimer;

  /// 設定を変更して通知し、少し待ってから保存する
  void update(void Function(AppConfig c) fn) {
    fn(config);
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), saveNow);
  }

  void saveNow() {
    _saveTimer?.cancel();
    try {
      rcfg.saveConfig(config: config);
      lastError = null;
    } catch (e) {
      lastError = '設定の保存に失敗しました: $e';
      notifyListeners();
    }
  }

  Dataset? datasetById(String id) {
    for (final d in config.datasets) {
      if (d.id == id) return d;
    }
    return null;
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) saveNow();
    super.dispose();
  }
}

/// frb の構造体を複製するヘルパー
TransitionSetting copyTransition(TransitionSetting t) =>
    TransitionSetting(kind: t.kind, durationMs: t.durationMs);

ContentItem copyItem(ContentItem i, {bool newId = false}) => ContentItem(
  id: newId ? rcfg.newId() : i.id,
  path: i.path,
  kind: i.kind,
  durationSec: i.durationSec,
  playFullVideo: i.playFullVideo,
  volume: i.volume,
  muted: i.muted,
  fit: i.fit,
  transition: copyTransition(i.transition),
);

Dataset copyDataset(Dataset d, {bool newId = false, String? name}) => Dataset(
  id: newId ? rcfg.newId() : d.id,
  name: name ?? d.name,
  items: [for (final i in d.items) copyItem(i, newId: newId)],
);

ScheduleRule copyRule(ScheduleRule r) => ScheduleRule(
  id: r.id,
  name: r.name,
  enabled: r.enabled,
  datasetId: r.datasetId,
  weekdayMask: r.weekdayMask,
  startTime: r.startTime,
  endTime: r.endTime,
  startDate: r.startDate,
  endDate: r.endDate,
  priority: r.priority,
);

ContentItem newContentItem(String path, MediaKind kind) => ContentItem(
  id: rcfg.newId(),
  path: path,
  kind: kind,
  durationSec: 10,
  playFullVideo: true,
  volume: 100,
  muted: false,
  fit: FitMode.contain,
  transition: TransitionSetting(
    kind: TransitionKind.crossFade,
    durationMs: 800,
  ),
);
