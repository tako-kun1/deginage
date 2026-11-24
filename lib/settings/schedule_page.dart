import 'dart:async';

import 'package:flutter/material.dart';

import '../common/config_controller.dart';
import '../common/ui.dart';
import '../src/rust/api/config.dart' as rcfg;
import '../src/rust/api/models.dart';
import '../src/rust/api/scheduler.dart';

/// スケジュール（表示データセットの切り替え条件）設定画面
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key, required this.controller});

  final ConfigController controller;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  Timer? _timer;

  ConfigController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _datasetName(String id) => c.datasetById(id)?.name ?? '（削除済み）';

  Future<void> _edit(ScheduleRule? original) async {
    final rule = original == null
        ? ScheduleRule(
            id: rcfg.newId(),
            name: '新しいルール',
            enabled: true,
            datasetId: c.config.datasets.first.id,
            weekdayMask: 0,
            startTime: '09:00',
            endTime: '18:00',
            startDate: null,
            endDate: null,
            priority: 0,
          )
        : copyRule(original);
    final result = await showDialog<ScheduleRule>(
      context: context,
      builder: (context) =>
          _RuleDialog(rule: rule, datasets: c.config.datasets),
    );
    if (result == null) return;
    c.update((cfg) {
      if (original == null) {
        cfg.rules = [...cfg.rules, result];
      } else {
        cfg.rules = [
          for (final r in cfg.rules) r.id == original.id ? result : r,
        ];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final activeId = resolveActiveDataset(config: c.config);
        final activeRule = resolveActiveRule(config: c.config);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              color: theme.colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.play_circle),
                title: Text('現在表示されるデータセット: ${_datasetName(activeId)}'),
                subtitle: Text(
                  activeRule == null
                      ? 'どのルールにも該当しないため、デフォルトを表示します'
                      : 'ルール「${c.config.rules.firstWhere((r) => r.id == activeRule).name}」が適用中',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('デフォルトのデータセット: '),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: c.config.defaultDatasetId,
                  items: [
                    for (final d in c.config.datasets)
                      DropdownMenuItem(value: d.id, child: Text(d.name)),
                  ],
                  onChanged: (v) {
                    if (v != null) c.update((cfg) => cfg.defaultDatasetId = v);
                  },
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _edit(null),
                  icon: const Icon(Icons.add),
                  label: const Text('ルールを追加'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '曜日・時間帯・期間の条件に一致したルールのデータセットを表示します。'
              '複数一致した場合は優先度が高いもの（同じ場合は上にあるもの）が適用されます。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (c.config.rules.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('ルールはまだありません')),
              ),
            for (final (i, r) in c.config.rules.indexed)
              Card(
                child: ListTile(
                  leading: Switch(
                    value: r.enabled,
                    onChanged: (v) => c.update((_) => r.enabled = v),
                  ),
                  title: Row(
                    children: [
                      Text(r.name),
                      if (r.id == activeRule) ...[
                        const SizedBox(width: 8),
                        const Chip(
                          label: Text('適用中'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${weekdayMaskLabel(r.weekdayMask)}  '
                    '${r.startTime == r.endTime ? '終日' : '${r.startTime}〜${r.endTime}'}'
                    '${r.startDate != null || r.endDate != null ? '  期間: ${r.startDate ?? ''}〜${r.endDate ?? ''}' : ''}'
                    '\n→ ${_datasetName(r.datasetId)}  (優先度 ${r.priority})',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '上へ',
                        onPressed: i == 0
                            ? null
                            : () => c.update((cfg) {
                                final l = [...cfg.rules];
                                l.insert(i - 1, l.removeAt(i));
                                cfg.rules = l;
                              }),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: '下へ',
                        onPressed: i == c.config.rules.length - 1
                            ? null
                            : () => c.update((cfg) {
                                final l = [...cfg.rules];
                                l.insert(i + 1, l.removeAt(i));
                                cfg.rules = l;
                              }),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      IconButton(
                        tooltip: '編集',
                        onPressed: () => _edit(r),
                        icon: const Icon(Icons.edit),
                      ),
                      IconButton(
                        tooltip: '削除',
                        onPressed: () => c.update(
                          (cfg) => cfg.rules = cfg.rules
                              .where((x) => x.id != r.id)
                              .toList(),
                        ),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({required this.rule, required this.datasets});

  final ScheduleRule rule;
  final List<Dataset> datasets;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final ScheduleRule r = widget.rule;
  late final TextEditingController _name = TextEditingController(text: r.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  TimeOfDay _parse(String s) {
    final p = s.split(':');
    return TimeOfDay(
      hour: int.tryParse(p[0]) ?? 0,
      minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
    );
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<String?> _pickTime(String current) async {
    final t = await showTimePicker(
      context: context,
      initialTime: _parse(current),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    return t == null ? null : _fmtTime(t);
  }

  Future<String?> _pickDate(String? current) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(current ?? '') ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    return d == null ? null : _fmtDate(d);
  }

  @override
  Widget build(BuildContext context) {
    final allDay = r.startTime == r.endTime;
    return AlertDialog(
      title: const Text('スケジュールルール'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'ルール名'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: widget.datasets.any((d) => d.id == r.datasetId)
                    ? r.datasetId
                    : widget.datasets.first.id,
                decoration: const InputDecoration(labelText: '表示するデータセット'),
                items: [
                  for (final d in widget.datasets)
                    DropdownMenuItem(value: d.id, child: Text(d.name)),
                ],
                onChanged: (v) =>
                    setState(() => r.datasetId = v ?? r.datasetId),
              ),
              const SizedBox(height: 16),
              const Text('曜日（未選択の場合は毎日）'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (var i = 0; i < 7; i++)
                    FilterChip(
                      label: Text(kWeekdayLabels[i]),
                      selected: r.weekdayMask & (1 << i) != 0,
                      onSelected: (v) => setState(
                        () => r.weekdayMask = v
                            ? r.weekdayMask | (1 << i)
                            : r.weekdayMask & ~(1 << i),
                      ),
                    ),
                  const SizedBox(width: 8),
                  ActionChip(
                    label: const Text('平日'),
                    onPressed: () => setState(() => r.weekdayMask = 0x1F),
                  ),
                  ActionChip(
                    label: const Text('土日'),
                    onPressed: () => setState(() => r.weekdayMask = 0x60),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: allDay,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        r.endTime = r.startTime = '00:00';
                      } else {
                        r.startTime = '09:00';
                        r.endTime = '18:00';
                      }
                    }),
                  ),
                  const Text('終日'),
                  const SizedBox(width: 24),
                  if (!allDay) ...[
                    OutlinedButton(
                      onPressed: () async {
                        final t = await _pickTime(r.startTime);
                        if (t != null) setState(() => r.startTime = t);
                      },
                      child: Text('開始 ${r.startTime}'),
                    ),
                    const Text('  〜  '),
                    OutlinedButton(
                      onPressed: () async {
                        final t = await _pickTime(r.endTime);
                        if (t != null) setState(() => r.endTime = t);
                      },
                      child: Text('終了 ${r.endTime}'),
                    ),
                  ],
                ],
              ),
              if (!allDay &&
                  _parse(r.endTime).hour * 60 + _parse(r.endTime).minute <
                      _parse(r.startTime).hour * 60 +
                          _parse(r.startTime).minute)
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Text('※ 日をまたぐ時間帯として扱います（開始日の曜日で判定）'),
                ),
              const SizedBox(height: 16),
              const Text('有効期間（任意）'),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final d = await _pickDate(r.startDate);
                      if (d != null) setState(() => r.startDate = d);
                    },
                    child: Text('開始日 ${r.startDate ?? '指定なし'}'),
                  ),
                  if (r.startDate != null)
                    IconButton(
                      onPressed: () => setState(() => r.startDate = null),
                      icon: const Icon(Icons.clear),
                    ),
                  const Text('  〜  '),
                  OutlinedButton(
                    onPressed: () async {
                      final d = await _pickDate(r.endDate);
                      if (d != null) setState(() => r.endDate = d);
                    },
                    child: Text('終了日 ${r.endDate ?? '指定なし'}'),
                  ),
                  if (r.endDate != null)
                    IconButton(
                      onPressed: () => setState(() => r.endDate = null),
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('優先度'),
                  Expanded(
                    child: Slider(
                      value: r.priority.toDouble().clamp(0, 100),
                      max: 100,
                      divisions: 100,
                      label: '${r.priority}',
                      onChanged: (v) => setState(() => r.priority = v.round()),
                    ),
                  ),
                  SizedBox(width: 36, child: Text('${r.priority}')),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            r.name = _name.text.trim().isEmpty ? 'ルール' : _name.text.trim();
            if (!widget.datasets.any((d) => d.id == r.datasetId)) {
              r.datasetId = widget.datasets.first.id;
            }
            Navigator.pop(context, r);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
