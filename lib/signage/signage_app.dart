import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../common/devices.dart';
import '../common/log.dart';
import '../common/signage_launcher.dart';
import '../common/ui.dart';
import '../src/rust/api/config.dart' as rcfg;
import '../src/rust/api/eew.dart';
import '../src/rust/api/models.dart';
import '../src/rust/api/scheduler.dart';
import 'eew_alert_view.dart';
import 'signage_player.dart';

/// サイネージ表示ウィンドウを起動する
Future<void> startSignage(List<String> args) async {
  rcfg.writeSignagePid(pid: pid);
  final config = rcfg.loadConfig();
  SignageLog.write('サイネージ起動 (pid=$pid)');

  const options = WindowOptions(
    title: 'Deginage Signage',
    backgroundColor: Colors.black,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await _placeOnMonitor(config.display);
    await windowManager.show();
    await windowManager.focus();
  });

  final parentPid = _parseParentPid(args);
  runApp(SignageApp(initialConfig: config, parentPid: parentPid));
}

int? _parseParentPid(List<String> args) {
  for (final a in args) {
    if (a.startsWith('--parent-pid=')) {
      return int.tryParse(a.substring('--parent-pid='.length));
    }
  }
  return null;
}

Future<void> _placeOnMonitor(DisplaySettings display) async {
  final displays = await listDisplays();
  Display? target;
  if (display.monitorId.isNotEmpty) {
    target = displays.where((d) => d.id == display.monitorId).firstOrNull;
  }
  if (target == null && display.monitorName.isNotEmpty) {
    target = displays.where((d) => d.name == display.monitorName).firstOrNull;
  }
  target ??= displays.firstOrNull;

  await windowManager.setFullScreen(false);
  if (target != null) {
    final pos = target.visiblePosition ?? Offset.zero;
    await windowManager.setBounds(
      Rect.fromLTWH(pos.dx, pos.dy, target.size.width, target.size.height),
    );
  }
  await windowManager.setFullScreen(true);
}

class SignageApp extends StatelessWidget {
  const SignageApp({super.key, required this.initialConfig, this.parentPid});

  final AppConfig initialConfig;
  final int? parentPid;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deginage Signage',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness: Brightness.dark),
      home: SignageScreen(initialConfig: initialConfig, parentPid: parentPid),
    );
  }
}

class SignageScreen extends StatefulWidget {
  const SignageScreen({super.key, required this.initialConfig, this.parentPid});

  final AppConfig initialConfig;
  final int? parentPid;

  @override
  State<SignageScreen> createState() => _SignageScreenState();
}

class _SignageScreenState extends State<SignageScreen> with WindowListener {
  late AppConfig _config = widget.initialConfig;
  late String _activeDatasetId = resolveActiveDataset(config: _config);

  StreamSubscription<AppConfig>? _configSub;
  StreamSubscription<EewEvent>? _eewSub;
  StreamSubscription<bool>? _eewTestSub;
  Timer? _scheduleTimer;
  Timer? _parentWatchTimer;
  Timer? _alertClearTimer;

  EewReport? _alertReport;
  EewEvaluation? _alertEval;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    _configSub = rcfg.watchConfig().listen(_onConfigUpdated);
    _eewTestSub = rcfg.watchEewTest().listen((_) => _triggerTestAlert());
    _eewSub = startEewListener().listen(_onEewEvent);

    _scheduleTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshSchedule(),
    );
    final parent = widget.parentPid;
    if (parent != null) {
      _parentWatchTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!SignageLauncher.isProcessAlive(parent)) {
          SignageLog.write('設定画面が終了したためサイネージを終了します');
          _quit();
        }
      });
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _configSub?.cancel();
    _eewSub?.cancel();
    _eewTestSub?.cancel();
    _scheduleTimer?.cancel();
    _parentWatchTimer?.cancel();
    _alertClearTimer?.cancel();
    stopEewListener();
    rcfg.clearSignagePid();
    super.dispose();
  }

  @override
  void onWindowClose() {
    rcfg.clearSignagePid();
  }

  void _onConfigUpdated(AppConfig next) {
    final monitorChanged =
        next.display.monitorId != _config.display.monitorId ||
        next.display.monitorName != _config.display.monitorName;
    setState(() {
      _config = next;
      _activeDatasetId = resolveActiveDataset(config: _config);
      if (!_config.eew.enabled && !(_alertReport?.isTest ?? false)) {
        _clearAlert();
      }
    });
    if (monitorChanged) {
      _placeOnMonitor(_config.display);
    }
  }

  void _refreshSchedule() {
    final nextId = resolveActiveDataset(config: _config);
    if (nextId != _activeDatasetId && mounted) {
      setState(() => _activeDatasetId = nextId);
    }
  }

  void _onEewEvent(EewEvent event) {
    final report = event.report;
    if (report == null || !mounted) return;
    if (!_config.eew.enabled) return;

    if (report.isCancel) {
      if (_alertReport?.eventId == report.eventId) {
        setState(_clearAlert);
      }
      return;
    }

    final eval = evaluateEew(report: report, settings: _config.eew);
    if (eval.affects) {
      _showAlert(report, eval, durationSec: _config.eew.alertDurationSec);
    }
  }

  void _triggerTestAlert() {
    if (!mounted) return;
    final report = sampleEewReport(settings: _config.eew);
    final eval = evaluateEew(report: report, settings: _config.eew);
    _showAlert(report, eval, durationSec: 20);
  }

  void _showAlert(
    EewReport report,
    EewEvaluation eval, {
    required int durationSec,
  }) {
    _alertClearTimer?.cancel();
    setState(() {
      _alertReport = report;
      _alertEval = eval;
    });
    _alertClearTimer = Timer(Duration(seconds: durationSec.clamp(5, 3600)), () {
      if (mounted) setState(_clearAlert);
    });
  }

  void _clearAlert() {
    _alertClearTimer?.cancel();
    _alertReport = null;
    _alertEval = null;
  }

  Dataset get _currentDataset {
    for (final d in _config.datasets) {
      if (d.id == _activeDatasetId) return d;
    }
    return _config.datasets.first;
  }

  Future<void> _quit() async {
    rcfg.clearSignagePid();
    await windowManager.close();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final showingAlert = _alertReport != null && _alertEval != null;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true): _quit,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_alertReport?.isTest ?? false) {
            setState(_clearAlert);
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Color(_config.display.backgroundColor),
          body: Stack(
            fit: StackFit.expand,
            children: [
              SignagePlayer(
                dataset: _currentDataset,
                display: _config.display,
                paused: showingAlert,
              ),
              if (showingAlert)
                GestureDetector(
                  onTap: () {
                    if (_alertReport?.isTest ?? false) {
                      setState(_clearAlert);
                    }
                  },
                  child: EewAlertView(
                    report: _alertReport!,
                    evaluation: _alertEval!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
