import 'dart:async';

import 'package:flutter/material.dart';

import '../common/config_controller.dart';
import '../signage/eew_alert_view.dart';
import '../src/rust/api/config.dart' as rcfg;
import '../src/rust/api/eew.dart';
import '../src/rust/api/intensity.dart';
import 'datasets_page.dart' show NumberField;
import 'prefectures.dart';

/// 地震速報（Wolfx Open API）連携の設定画面
class EewPage extends StatefulWidget {
  const EewPage({super.key, required this.controller});

  final ConfigController controller;

  @override
  State<EewPage> createState() => _EewPageState();
}

class _EewPageState extends State<EewPage> {
  StreamSubscription<EewEvent>? _sub;
  EewConnectionStatus _status = EewConnectionStatus.disconnected;
  String _statusMessage = '未接続';
  EewReport? _lastReport;
  DateTime? _lastAt;

  ConfigController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _sub = startEewListener().listen((e) {
      if (!mounted) return;
      setState(() {
        _status = e.status;
        _statusMessage = e.message;
        if (e.report != null) {
          _lastReport = e.report;
          _lastAt = DateTime.now();
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    stopEewListener();
    super.dispose();
  }

  void _preview() {
    final report = sampleEewReport(settings: c.config.eew);
    final eval = evaluateEew(report: report, settings: c.config.eew);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          body: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Stack(
              children: [
                Positioned.fill(
                  child: EewAlertView(report: report, evaluation: eval),
                ),
                const Positioned(
                  right: 16,
                  top: 16,
                  child: Chip(label: Text('プレビュー（クリックで閉じる）')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.config.eew;
        final prefNames = kPrefectures.map((p) => p.name).toSet();
        final levels = intensityLevels();
        final last = _lastReport;
        final lastEval = last == null
            ? null
            : evaluateEew(report: last, settings: s);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: SwitchListTile(
                value: s.enabled,
                onChanged: (v) => c.update((_) => s.enabled = v),
                title: const Text('緊急地震速報で警告画面に切り替える'),
                subtitle: const Text(
                  'Wolfx Open API (wss://ws-api.wolfx.jp/jma_eew) から気象庁の緊急地震速報を受信します',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.circle,
                  size: 16,
                  color: switch (_status) {
                    EewConnectionStatus.connected => Colors.green,
                    EewConnectionStatus.connecting => Colors.orange,
                    EewConnectionStatus.disconnected => Colors.red,
                  },
                ),
                title: Text('接続状態: $_statusMessage'),
                subtitle: last == null
                    ? const Text('この画面を開いてから受信した速報はありません')
                    : Text(
                        '最終受信 ${_lastAt?.toLocal().toString().substring(0, 19)}: '
                        '${last.title} 第${last.serial}報 ${last.hypocenter} '
                        'M${last.magnitude.toStringAsFixed(1)} 最大震度${intensityLabel(raw: last.maxIntensity)}'
                        '${last.isCancel ? '（取消）' : ''}\n'
                        '判定: ${lastEval!.affects ? '警告対象' : '対象外'} - ${lastEval.reason}',
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Text('所在地', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: prefNames.contains(s.prefecture)
                          ? s.prefecture
                          : null,
                      decoration: const InputDecoration(
                        labelText: '都道府県（選択すると県庁所在地の座標と地域キーワードを自動入力）',
                      ),
                      items: [
                        for (final p in kPrefectures)
                          DropdownMenuItem(value: p.name, child: Text(p.name)),
                      ],
                      onChanged: (v) {
                        final p = kPrefectures.firstWhere((x) => x.name == v);
                        c.update((_) {
                          s.prefecture = p.name;
                          s.latitude = p.latitude;
                          s.longitude = p.longitude;
                          s.areaKeywords = p.keywords;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: NumberField(
                            key: ValueKey('lat-${s.prefecture}'),
                            label: '緯度',
                            value: s.latitude,
                            min: 20,
                            max: 50,
                            onChanged: (v) => c.update((_) => s.latitude = v),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: NumberField(
                            key: ValueKey('lon-${s.prefecture}'),
                            label: '経度',
                            value: s.longitude,
                            min: 120,
                            max: 155,
                            onChanged: (v) => c.update((_) => s.longitude = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _KeywordField(
                      key: ValueKey('kw-${s.prefecture}'),
                      value: s.areaKeywords,
                      onChanged: (v) => c.update((_) => s.areaKeywords = v),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '緊急地震速報の対象地域名（例:「石川県能登」「東京都２３区」）とカンマ区切りのキーワードを前方一致で照合します。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('警告画面を表示する条件', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('所在地の予測震度が'),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: levels.contains(s.intensityThreshold)
                              ? s.intensityThreshold
                              : '4',
                          items: [
                            for (final l in levels)
                              DropdownMenuItem(
                                value: l,
                                child: Text('震度${intensityLabel(raw: l)}'),
                              ),
                          ],
                          onChanged: (v) =>
                              c.update((_) => s.intensityThreshold = v ?? '4'),
                        ),
                        const SizedBox(width: 12),
                        const Text('以上の場合'),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: s.useWarnArea,
                      onChanged: (v) => c.update((_) => s.useWarnArea = v),
                      title: const Text('速報の対象地域で判定する'),
                      subtitle: const Text('所在地の地域が速報の対象地域に含まれ、その予測震度がしきい値以上'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: s.useEstimation,
                      onChanged: (v) => c.update((_) => s.useEstimation = v),
                      title: const Text('震源と規模から所在地の震度を推定して判定する'),
                      subtitle: const Text('司・翠川(1999)の距離減衰式による簡易推定'),
                    ),
                    if (s.useEstimation)
                      Row(
                        children: [
                          const Text('地盤増幅率'),
                          Expanded(
                            child: Slider(
                              value: s.siteAmplification.clamp(0.5, 3.0),
                              min: 0.5,
                              max: 3.0,
                              divisions: 25,
                              label: s.siteAmplification.toStringAsFixed(1),
                              onChanged: (v) =>
                                  c.update((_) => s.siteAmplification = v),
                            ),
                          ),
                          Text(s.siteAmplification.toStringAsFixed(1)),
                          const SizedBox(width: 8),
                          const Tooltip(
                            message: '地盤が軟らかい地域ほど大きくします（標準 1.4）',
                            child: Icon(Icons.help_outline, size: 18),
                          ),
                        ],
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: s.showTraining,
                      onChanged: (v) => c.update((_) => s.showTraining = v),
                      title: const Text('訓練報でも警告画面を表示する'),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 280,
                      child: NumberField(
                        label: '警告画面の表示時間（最終受信からの秒数）',
                        value: s.alertDurationSec.toDouble(),
                        min: 10,
                        max: 3600,
                        decimal: false,
                        onChanged: (v) =>
                            c.update((_) => s.alertDurationSec = v.round()),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '取消報を受信した場合は直ちに通常表示へ戻ります。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('テスト', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _preview,
                  icon: const Icon(Icons.preview),
                  label: const Text('警告画面をプレビュー'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    c.saveNow();
                    rcfg.requestEewTest();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('表示中のサイネージにテスト表示を要求しました')),
                    );
                  },
                  icon: const Icon(Icons.campaign),
                  label: const Text('サイネージでテスト表示'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              '※ 本機能は非公式の Wolfx Open API を利用した参考情報です。'
              '公式の緊急地震速報・防災情報を代替するものではありません。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

class _KeywordField extends StatefulWidget {
  const _KeywordField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_KeywordField> createState() => _KeywordFieldState();
}

class _KeywordFieldState extends State<_KeywordField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      decoration: const InputDecoration(
        labelText: '対象地域キーワード（カンマ区切り）',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: widget.onChanged,
    );
  }
}
