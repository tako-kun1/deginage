import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../common/config_controller.dart';
import '../common/signage_launcher.dart';
import '../common/ui.dart';
import '../src/rust/api/simple.dart';
import 'datasets_page.dart';
import 'display_page.dart';
import 'eew_page.dart';
import 'schedule_page.dart';

/// 設定画面を起動する
Future<void> startSettings() async {
  const options = WindowOptions(
    size: Size(1280, 820),
    minimumSize: Size(960, 640),
    center: true,
    title: 'Deginage 設定 v$kAppVersion',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(SettingsApp(controller: ConfigController()));
}

class SettingsApp extends StatelessWidget {
  const SettingsApp({super.key, required this.controller});

  final ConfigController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deginage 設定',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('ja'),
      home: SettingsShell(controller: controller),
    );
  }
}

class SettingsShell extends StatefulWidget {
  const SettingsShell({super.key, required this.controller});

  final ConfigController controller;

  @override
  State<SettingsShell> createState() => _SettingsShellState();
}

class _SettingsShellState extends State<SettingsShell> with WindowListener {
  int _index = 0;
  bool _running = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    _refreshStatus();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshStatus(),
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    widget.controller.saveNow();
    await SignageLauncher.stop();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  void _refreshStatus() {
    final r = SignageLauncher.isRunning();
    if (r != _running && mounted) setState(() => _running = r);
  }

  Future<void> _toggleSignage() async {
    widget.controller.saveNow();
    if (_running) {
      await SignageLauncher.stop();
    } else {
      await SignageLauncher.start();
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final pages = <Widget>[
      DatasetsPage(controller: c),
      SchedulePage(controller: c),
      DisplayPage(controller: c),
      EewPage(controller: c),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Deginage デジタルサイネージ 設定'),
            const SizedBox(width: 10),
            Text(
              'v$kAppVersion',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          ListenableBuilder(
            listenable: c,
            builder: (context, _) => c.lastError == null
                ? const SizedBox.shrink()
                : Tooltip(
                    message: c.lastError!,
                    child: const Icon(Icons.error, color: Colors.red),
                  ),
          ),
          const SizedBox(width: 12),
          Chip(
            avatar: Icon(
              Icons.circle,
              size: 12,
              color: _running ? Colors.green : Colors.grey,
            ),
            label: Text(_running ? 'サイネージ表示中' : 'サイネージ停止中'),
          ),
          const SizedBox(width: 8),
          if (_running)
            IconButton(
              tooltip: 'サイネージを再起動（モニター設定を反映）',
              onPressed: () async {
                c.saveNow();
                await SignageLauncher.restart();
                _refreshStatus();
              },
              icon: const Icon(Icons.restart_alt),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              style: _running
                  ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700)
                  : null,
              onPressed: _toggleSignage,
              icon: Icon(_running ? Icons.stop : Icons.play_arrow),
              label: Text(_running ? 'サイネージ停止' : 'サイネージ開始'),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.video_library_outlined),
                selectedIcon: Icon(Icons.video_library),
                label: Text('コンテンツ'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.schedule_outlined),
                selectedIcon: Icon(Icons.schedule),
                label: Text('スケジュール'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.monitor_outlined),
                selectedIcon: Icon(Icons.monitor),
                label: Text('表示・音声'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.warning_amber_outlined),
                selectedIcon: Icon(Icons.warning_amber),
                label: Text('地震速報'),
              ),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextButton(
                    onPressed: () => showAboutDialog(
                      context: context,
                      applicationName: 'Deginage',
                      applicationVersion:
                          'v$kAppVersion (Rust コア v${coreVersion()})',
                      children: const [
                        Text('Windows / Linux 向けデジタルサイネージソフトウェア'),
                      ],
                    ),
                    child: const Text('v$kAppVersion'),
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages[_index]),
        ],
      ),
    );
  }
}
