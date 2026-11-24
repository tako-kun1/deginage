import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/config_controller.dart';
import '../common/ui.dart';
import '../src/rust/api/models.dart';

/// コンテンツ（データセット）設定画面
class DatasetsPage extends StatefulWidget {
  const DatasetsPage({super.key, required this.controller});

  final ConfigController controller;

  @override
  State<DatasetsPage> createState() => _DatasetsPageState();
}

class _DatasetsPageState extends State<DatasetsPage> {
  String? _selectedId;
  bool _dragging = false;

  ConfigController get c => widget.controller;

  Dataset? get _selected {
    final ds = c.config.datasets;
    if (ds.isEmpty) return null;
    return c.datasetById(_selectedId ?? '') ?? ds.first;
  }

  Future<String?> _askName(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'データセット名'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _addDataset() async {
    final name = await _askName('データセットを追加', '新しいデータセット');
    if (name == null || name.trim().isEmpty) return;
    final ds = Dataset(id: '', name: name.trim(), items: []);
    final copy = copyDataset(ds, newId: true);
    c.update((cfg) => cfg.datasets = [...cfg.datasets, copy]);
    setState(() => _selectedId = copy.id);
  }

  Future<void> _duplicate(Dataset d) async {
    final name = await _askName('データセットを複製', '${d.name} のコピー');
    if (name == null || name.trim().isEmpty) return;
    final copy = copyDataset(d, newId: true, name: name.trim());
    c.update((cfg) => cfg.datasets = [...cfg.datasets, copy]);
    setState(() => _selectedId = copy.id);
  }

  Future<void> _rename(Dataset d) async {
    final name = await _askName('名前を変更', d.name);
    if (name == null || name.trim().isEmpty) return;
    c.update((_) => d.name = name.trim());
  }

  Future<void> _delete(Dataset d) async {
    if (c.config.datasets.length <= 1) {
      _snack('最後のデータセットは削除できません');
      return;
    }
    final used = c.config.rules.where((r) => r.datasetId == d.id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('データセットを削除'),
        content: Text(
          '「${d.name}」を削除しますか？'
          '${used > 0 ? '\nこのデータセットを使うスケジュールルール $used 件も削除されます。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    c.update((cfg) {
      cfg.datasets = cfg.datasets.where((x) => x.id != d.id).toList();
      cfg.rules = cfg.rules.where((r) => r.datasetId != d.id).toList();
      if (cfg.defaultDatasetId == d.id) {
        cfg.defaultDatasetId = cfg.datasets.first.id;
      }
    });
    setState(() => _selectedId = null);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addFiles(Dataset d) async {
    final files = await openFiles(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: '画像・動画',
          extensions: [...kImageExtensions, ...kVideoExtensions],
        ),
        const XTypeGroup(label: '画像', extensions: kImageExtensions),
        const XTypeGroup(label: '動画', extensions: kVideoExtensions),
      ],
      confirmButtonText: '追加',
    );
    if (files.isEmpty) return;
    _addPaths(d, files.map((f) => f.path).toList());
  }

  /// パス（ファイルまたはフォルダ）一覧からコンテンツを追加する
  void _addPaths(Dataset d, List<String> paths) {
    final files = <String>[];
    for (final p in paths) {
      if (FileSystemEntity.isDirectorySync(p)) {
        final inDir =
            Directory(p)
                .listSync(recursive: true)
                .whereType<File>()
                .map((f) => f.path)
                .where((f) => mediaKindForPath(f) != null)
                .toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        files.addAll(inDir);
      } else {
        files.add(p);
      }
    }
    final added = <ContentItem>[];
    var skipped = 0;
    for (final path in files) {
      final kind = mediaKindForPath(path);
      if (kind == null) {
        skipped++;
        continue;
      }
      final item = newContentItem(path, kind);
      // 直前のコンテンツと同じトランジションを引き継ぐ
      final last = added.isNotEmpty
          ? added.last
          : (d.items.isNotEmpty ? d.items.last : null);
      if (last != null) {
        item.transition = copyTransition(last.transition);
      }
      added.add(item);
    }
    if (added.isEmpty) {
      _snack('対応していないファイル形式です');
      return;
    }
    c.update((_) => d.items = [...d.items, ...added]);
    _snack(
      '${added.length} 件のコンテンツを追加しました'
      '${skipped > 0 ? '（非対応の $skipped 件はスキップ）' : ''}',
    );
  }

  Future<void> _bulkTransition(Dataset d) async {
    var kind = d.items.isNotEmpty
        ? d.items.first.transition.kind
        : TransitionKind.crossFade;
    var duration = d.items.isNotEmpty
        ? d.items.first.transition.durationMs
        : 800;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('トランジションを一括設定'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<TransitionKind>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: '種類'),
                  items: [
                    for (final k in TransitionKind.values)
                      DropdownMenuItem(
                        value: k,
                        child: Text(transitionLabel(k)),
                      ),
                  ],
                  onChanged: (v) => setLocal(() => kind = v ?? kind),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('時間'),
                    Expanded(
                      child: Slider(
                        value: duration.toDouble().clamp(100, 5000),
                        min: 100,
                        max: 5000,
                        divisions: 49,
                        label: '${(duration / 1000).toStringAsFixed(1)} 秒',
                        onChanged: (v) => setLocal(() => duration = v.round()),
                      ),
                    ),
                    Text('${(duration / 1000).toStringAsFixed(1)} 秒'),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('すべてに適用'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    c.update((_) {
      for (final item in d.items) {
        item.transition = TransitionSetting(kind: kind, durationMs: duration);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final selected = _selected;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 280, child: _buildDatasetList(selected)),
            const VerticalDivider(width: 1),
            Expanded(
              child: selected == null
                  ? const Center(child: Text('データセットがありません'))
                  : _buildEditor(selected),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDatasetList(Dataset? selected) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('データセット', style: theme.textTheme.titleMedium),
              ),
              IconButton(
                tooltip: 'データセットを追加',
                onPressed: _addDataset,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final d in c.config.datasets)
                ListTile(
                  selected: d.id == selected?.id,
                  leading: Icon(
                    d.id == c.config.defaultDatasetId
                        ? Icons.star
                        : Icons.playlist_play,
                    color: d.id == c.config.defaultDatasetId
                        ? Colors.amber.shade700
                        : null,
                  ),
                  title: Text(d.name),
                  subtitle: Text('${d.items.length} 件のコンテンツ'),
                  onTap: () => setState(() => _selectedId = d.id),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'rename':
                          _rename(d);
                        case 'dup':
                          _duplicate(d);
                        case 'default':
                          c.update((cfg) => cfg.defaultDatasetId = d.id);
                        case 'delete':
                          _delete(d);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: Text('名前を変更')),
                      PopupMenuItem(value: 'dup', child: Text('複製')),
                      PopupMenuItem(value: 'default', child: Text('デフォルトに設定')),
                      PopupMenuItem(value: 'delete', child: Text('削除')),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '★ はスケジュールに該当しない時に表示されるデフォルトです。',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _buildEditor(Dataset d) {
    final theme = Theme.of(context);
    final totalSec = d.items.fold<double>(
      0,
      (s, i) =>
          s +
          (i.kind == MediaKind.video && i.playFullVideo ? 0 : i.durationSec),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(d.name, style: theme.textTheme.headlineSmall),
              Text(
                '${d.items.length} 件 / 画像・秒数指定分 合計 ${totalSec.toStringAsFixed(0)} 秒',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 24),
              FilledButton.icon(
                onPressed: () => _addFiles(d),
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('画像・動画を追加'),
              ),
              OutlinedButton.icon(
                onPressed: d.items.isEmpty ? null : () => _bulkTransition(d),
                icon: const Icon(Icons.auto_awesome_motion),
                label: const Text('トランジション一括設定'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (detail) {
              setState(() => _dragging = false);
              _addPaths(d, detail.files.map((f) => f.path).toList());
            },
            child: Stack(
              children: [
                Positioned.fill(child: _buildItemList(d, theme)),
                if (_dragging)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.file_download,
                              size: 64,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'ここにドロップして「${d.name}」に追加',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemList(Dataset d, ThemeData theme) {
    return d.items.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_upload_outlined,
                  size: 64,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  '画像・動画ファイル（またはフォルダ）をここにドラッグ＆ドロップ\nまたは「画像・動画を追加」ボタンから追加してください',
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        : ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            buildDefaultDragHandles: false,
            itemCount: d.items.length,
            onReorderItem: (oldIndex, newIndex) {
              c.update((_) {
                final list = [...d.items];
                final item = list.removeAt(oldIndex);
                list.insert(newIndex, item);
                d.items = list;
              });
            },
            itemBuilder: (context, i) => _ContentCard(
              key: ValueKey(d.items[i].id),
              index: i,
              item: d.items[i],
              isLast: i == d.items.length - 1,
              controller: c,
              onDelete: () =>
                  c.update((_) => d.items = [...d.items]..removeAt(i)),
            ),
          );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({
    super.key,
    required this.index,
    required this.item,
    required this.isLast,
    required this.controller,
    required this.onDelete,
  });

  final int index;
  final ContentItem item;
  final bool isLast;
  final ConfigController controller;
  final VoidCallback onDelete;

  void _set(void Function() fn) => controller.update((_) => fn());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exists = File(item.path).existsSync();
    final isVideo = item.kind == MediaKind.video;
    return Column(
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.only(top: 18, right: 8),
                    child: Icon(Icons.drag_indicator),
                  ),
                ),
                _Thumbnail(item: item, exists: exists),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isVideo ? Icons.movie : Icons.image,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text('${index + 1}. '),
                          Expanded(
                            child: Text(
                              fileNameOf(item.path),
                              style: theme.textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        exists ? item.path : 'ファイルが見つかりません: ${item.path}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: exists ? null : Colors.red,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (isVideo)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: item.playFullVideo,
                                  onChanged: (v) =>
                                      _set(() => item.playFullVideo = v),
                                ),
                                const Text('最後まで再生'),
                              ],
                            ),
                          if (!isVideo || !item.playFullVideo)
                            SizedBox(
                              width: 150,
                              child: NumberField(
                                label: '表示時間（秒）',
                                value: item.durationSec,
                                min: 1,
                                onChanged: (v) =>
                                    _set(() => item.durationSec = v),
                              ),
                            ),
                          DropdownButton<FitMode>(
                            value: item.fit,
                            items: [
                              for (final f in FitMode.values)
                                DropdownMenuItem(
                                  value: f,
                                  child: Text(fitLabel(f)),
                                ),
                            ],
                            onChanged: (v) =>
                                _set(() => item.fit = v ?? item.fit),
                          ),
                          if (isVideo)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: item.muted ? 'ミュート解除' : 'ミュート',
                                  onPressed: () =>
                                      _set(() => item.muted = !item.muted),
                                  icon: Icon(
                                    item.muted
                                        ? Icons.volume_off
                                        : Icons.volume_up,
                                  ),
                                ),
                                SizedBox(
                                  width: 160,
                                  child: Slider(
                                    value: item.volume.clamp(0, 100),
                                    max: 100,
                                    divisions: 20,
                                    label: '${item.volume.round()}',
                                    onChanged: item.muted
                                        ? null
                                        : (v) => _set(() => item.volume = v),
                                  ),
                                ),
                                Text('${item.volume.round()}%'),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '削除',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
        _TransitionRow(
          item: item,
          isLast: isLast,
          onChanged: (kind, ms) => _set(() {
            item.transition = TransitionSetting(kind: kind, durationMs: ms);
          }),
        ),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.item, required this.exists});

  final ContentItem item;
  final bool exists;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (!exists) {
      child = const Icon(Icons.broken_image, color: Colors.white54);
    } else if (item.kind == MediaKind.image) {
      child = Image.file(
        File(item.path),
        fit: BoxFit.cover,
        cacheWidth: 256,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.broken_image, color: Colors.white54),
      );
    } else {
      child = const Icon(Icons.movie, color: Colors.white70, size: 36);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 128,
        height: 72,
        color: Colors.black87,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

class _TransitionRow extends StatelessWidget {
  const _TransitionRow({
    required this.item,
    required this.isLast,
    required this.onChanged,
  });

  final ContentItem item;
  final bool isLast;
  final void Function(TransitionKind kind, int ms) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = item.transition;
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 4, 16, 12),
      child: Row(
        children: [
          Icon(
            isLast ? Icons.replay : Icons.arrow_downward,
            size: 18,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Text(
            isLast ? '先頭へ戻るトランジション:' : '次へのトランジション:',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          DropdownButton<TransitionKind>(
            value: t.kind,
            isDense: true,
            items: [
              for (final k in TransitionKind.values)
                DropdownMenuItem(value: k, child: Text(transitionLabel(k))),
            ],
            onChanged: (v) => onChanged(v ?? t.kind, t.durationMs),
          ),
          const SizedBox(width: 16),
          if (t.kind != TransitionKind.none) ...[
            SizedBox(
              width: 180,
              child: Slider(
                value: t.durationMs.toDouble().clamp(100, 5000),
                min: 100,
                max: 5000,
                divisions: 49,
                label: '${(t.durationMs / 1000).toStringAsFixed(1)} 秒',
                onChanged: (v) => onChanged(t.kind, v.round()),
              ),
            ),
            Text(
              '${(t.durationMs / 1000).toStringAsFixed(1)} 秒',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// 数値入力フィールド（入力確定ごとに通知）
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min,
    this.max,
    this.decimal = true,
  });

  final String label;
  final double value;
  final double? min;
  final double? max;
  final bool decimal;
  final ValueChanged<double> onChanged;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: _fmt(widget.value),
  );

  String _fmt(double v) =>
      widget.decimal && v != v.roundToDouble() ? '$v' : '${v.round()}';

  @override
  void didUpdateWidget(covariant NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = double.tryParse(_ctrl.text);
    if (current != widget.value) _ctrl.text = _fmt(widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(widget.decimal ? r'[0-9.\-]' : r'[0-9\-]'),
        ),
      ],
      onChanged: (text) {
        var v = double.tryParse(text);
        if (v == null) return;
        if (widget.min != null && v < widget.min!) return;
        if (widget.max != null && v > widget.max!) v = widget.max!;
        widget.onChanged(v);
      },
    );
  }
}
