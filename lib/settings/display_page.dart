import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:screen_retriever/screen_retriever.dart';

import '../common/config_controller.dart';
import '../common/devices.dart';

/// 表示モニター・音声出力先の設定画面
class DisplayPage extends StatefulWidget {
  const DisplayPage({super.key, required this.controller});

  final ConfigController controller;

  @override
  State<DisplayPage> createState() => _DisplayPageState();
}

class _DisplayPageState extends State<DisplayPage> {
  List<Display> _displays = [];
  List<AudioDevice> _audio = [];
  bool _loadingDisplays = true;
  bool _loadingAudio = true;

  ConfigController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _refreshDisplays();
    _refreshAudio();
  }

  Future<void> _refreshDisplays() async {
    setState(() => _loadingDisplays = true);
    final d = await listDisplays();
    if (mounted) {
      setState(() {
        _displays = d;
        _loadingDisplays = false;
      });
    }
  }

  Future<void> _refreshAudio() async {
    setState(() => _loadingAudio = true);
    final a = await listAudioDevices();
    if (mounted) {
      setState(() {
        _audio = a;
        _loadingAudio = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final disp = c.config.display;
        final monitorIds = _displays.map((d) => d.id).toSet();
        final selectedMonitor = monitorIds.contains(disp.monitorId)
            ? disp.monitorId
            : '';
        final audioNames = _audio.map((a) => a.name).toSet();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('表示モニター', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedMonitor,
                            key: ValueKey(
                              'mon-$selectedMonitor-${_displays.length}',
                            ),
                            decoration: const InputDecoration(
                              labelText: 'サイネージを表示するモニター',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('プライマリモニター（自動）'),
                              ),
                              for (final (i, d) in _displays.indexed)
                                DropdownMenuItem(
                                  value: d.id,
                                  child: Text(displayLabel(d, i)),
                                ),
                            ],
                            onChanged: (v) => c.update((cfg) {
                              cfg.display.monitorId = v ?? '';
                              cfg.display.monitorName =
                                  _displays
                                      .where((d) => d.id == v)
                                      .firstOrNull
                                      ?.name ??
                                  '';
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '再読み込み',
                          onPressed: _loadingDisplays ? null : _refreshDisplays,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (disp.monitorId.isNotEmpty && selectedMonitor.isEmpty)
                      Text(
                        '※ 保存されているモニター（${disp.monitorName.isEmpty ? disp.monitorId : disp.monitorName}）が見つかりません。'
                        'サイネージはプライマリモニターに表示されます。',
                        style: const TextStyle(color: Colors.orange),
                      ),
                    Text(
                      'モニターの変更は、サイネージ表示中でも自動的に反映されます。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('音声出力先', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _loadingAudio
                              ? const LinearProgressIndicator()
                              : DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    'aud-${disp.audioDevice}-${_audio.length}',
                                  ),
                                  initialValue:
                                      audioNames.contains(disp.audioDevice)
                                      ? disp.audioDevice
                                      : 'auto',
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: '動画の音声を出力するデバイス',
                                  ),
                                  items: [
                                    if (!audioNames.contains('auto'))
                                      const DropdownMenuItem(
                                        value: 'auto',
                                        child: Text('既定のデバイス（自動）'),
                                      ),
                                    for (final a in _audio)
                                      DropdownMenuItem(
                                        value: a.name,
                                        child: Text(
                                          audioDeviceLabel(a),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) => c.update(
                                    (cfg) =>
                                        cfg.display.audioDevice = v ?? 'auto',
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '再読み込み',
                          onPressed: _loadingAudio ? null : _refreshAudio,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    if (!_loadingAudio &&
                        disp.audioDevice != 'auto' &&
                        !audioNames.contains(disp.audioDevice))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '※ 保存されているデバイス（${disp.audioDevice}）が見つかりません。',
                          style: const TextStyle(color: Colors.orange),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('背景色', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (label, color) in const [
                  ('黒', 0xFF000000),
                  ('白', 0xFFFFFFFF),
                  ('グレー', 0xFF303030),
                  ('ネイビー', 0xFF0D1B2A),
                ])
                  ChoiceChip(
                    avatar: CircleAvatar(backgroundColor: Color(color)),
                    label: Text(label),
                    selected: disp.backgroundColor == color,
                    onSelected: (_) =>
                        c.update((cfg) => cfg.display.backgroundColor = color),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text('操作方法・自動起動', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SelectableText(
                  '・サイネージ画面は Ctrl + Q で終了できます。\n'
                  '・PC 起動時に自動でサイネージを表示するには、'
                  '実行ファイルを引数 --signage 付きで起動するよう設定してください。\n'
                  '    Windows: スタートアップフォルダに「deginage.exe --signage」のショートカットを配置\n'
                  '    Linux: ~/.config/autostart に Exec=deginage --signage の .desktop ファイルを配置',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
