import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../common/log.dart';
import '../common/ui.dart';
import '../src/rust/api/models.dart';
import 'transition_switcher.dart';

/// 表示中（またはトランジション中）の 1 コンテンツ
class _Slide {
  _Slide(this.item, this.serial) : key = GlobalObjectKey('slide-$serial');

  final ContentItem item;
  final int serial;
  final GlobalKey key;
  Player? player;
  VideoController? controller;
  final List<StreamSubscription<dynamic>> subs = [];

  Future<void> dispose() async {
    for (final s in subs) {
      await s.cancel();
    }
    subs.clear();
    final p = player;
    player = null;
    controller = null;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }
}

/// 1つのデータセットをループ再生するサイネージプレイヤー
class SignagePlayer extends StatefulWidget {
  const SignagePlayer({
    super.key,
    required this.dataset,
    required this.display,
    required this.paused,
  });

  final Dataset dataset;
  final DisplaySettings display;

  /// 地震速報表示中など、再生を一時停止したい場合に true
  final bool paused;

  @override
  State<SignagePlayer> createState() => _SignagePlayerState();
}

class _SignagePlayerState extends State<SignagePlayer> {
  int _index = 0;
  int _serial = 0;
  _Slide? _current;
  final List<_Slide> _retiring = [];
  Timer? _advanceTimer;
  Timer? _watchdog;
  TransitionSetting _transition = TransitionSetting(
    kind: TransitionKind.none,
    durationMs: 0,
  );

  List<ContentItem> get _items => widget.dataset.items;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _show(0, useTransition: false);
    });
  }

  @override
  void didUpdateWidget(covariant SignagePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.display.audioDevice != oldWidget.display.audioDevice) {
      final p = _current?.player;
      if (p != null) _applyAudioDevice(p);
    }
    if (widget.paused != oldWidget.paused) {
      if (widget.paused) {
        _advanceTimer?.cancel();
        _watchdog?.cancel();
        _current?.player?.pause();
      } else {
        _resume();
      }
    }
    if (widget.dataset.id != oldWidget.dataset.id ||
        _itemsChanged(oldWidget.dataset.items, widget.dataset.items)) {
      SignageLog.write('データセット更新: ${widget.dataset.name}');
      _show(0, useTransition: false);
    }
  }

  bool _itemsChanged(List<ContentItem> a, List<ContentItem> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.id != y.id ||
          x.path != y.path ||
          x.kind != y.kind ||
          x.durationSec != y.durationSec ||
          x.playFullVideo != y.playFullVideo ||
          x.volume != y.volume ||
          x.muted != y.muted ||
          x.fit != y.fit ||
          x.transition.kind != y.transition.kind ||
          x.transition.durationMs != y.transition.durationMs) {
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _watchdog?.cancel();
    _current?.dispose();
    for (final s in _retiring) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _applyAudioDevice(Player p) async {
    final target = widget.display.audioDevice;
    try {
      if (target.isEmpty || target == 'auto') {
        await p.setAudioDevice(AudioDevice.auto());
      } else {
        await p.setAudioDevice(AudioDevice(target, ''));
      }
    } catch (e) {
      SignageLog.write('音声出力デバイスの設定に失敗: $target $e');
    }
  }

  void _scheduleAdvance(double sec) {
    _advanceTimer?.cancel();
    final ms = (sec * 1000).round().clamp(500, 24 * 3600 * 1000);
    _advanceTimer = Timer(Duration(milliseconds: ms), _advance);
  }

  void _resume() {
    final slide = _current;
    if (slide == null) return;
    final item = slide.item;
    if (item.kind == MediaKind.video) {
      slide.player?.play();
      if (!item.playFullVideo) _scheduleAdvance(item.durationSec);
    } else {
      _scheduleAdvance(item.durationSec);
    }
  }

  void _advance() {
    if (!mounted || _items.isEmpty || widget.paused) return;
    final prev = _current?.item;
    final next = (_index + 1) % _items.length;
    // 1 件のみの画像は切り替え不要
    if (_items.length == 1 && prev?.kind == MediaKind.image) {
      _scheduleAdvance(prev!.durationSec);
      return;
    }
    _show(next, useTransition: true);
  }

  Future<void> _show(int start, {required bool useTransition}) async {
    _advanceTimer?.cancel();
    _watchdog?.cancel();
    if (_items.isEmpty) {
      await _retireCurrent(immediately: true);
      if (mounted) setState(() {});
      return;
    }

    // 存在するファイルを最大 1 周探索
    int? idx;
    for (var o = 0; o < _items.length; o++) {
      final c = (start + o) % _items.length;
      if (File(_items[c].path).existsSync()) {
        idx = c;
        break;
      } else {
        SignageLog.write('ファイルが見つかりません: ${_items[c].path}');
      }
    }
    if (idx == null) {
      await _retireCurrent(immediately: true);
      if (mounted) setState(() {});
      return;
    }

    final prevItem = _current?.item;
    _transition = useTransition && prevItem != null
        ? prevItem.transition
        : TransitionSetting(kind: TransitionKind.none, durationMs: 0);

    _index = idx;
    final item = _items[idx];
    final slide = _Slide(item, ++_serial);
    if (item.kind == MediaKind.video) {
      _initVideoSlide(slide);
    } else if (!widget.paused) {
      _scheduleAdvance(item.durationSec);
    }

    final old = _current;
    if (old != null) _retiring.add(old);
    _current = slide;
    setState(() {});
    // ウィンドウが非アクティブでも VideoController の postFrameCallback が確実に走るようフレームを要求
    WidgetsBinding.instance.scheduleFrame();

    if (item.kind == MediaKind.video) {
      unawaited(_openVideo(slide));
    }

    if (_transition.kind == TransitionKind.none ||
        _transition.durationMs <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _disposeRetiring());
    }
  }

  void _initVideoSlide(_Slide slide) {
    final item = slide.item;
    final player = Player(
      configuration: const PlayerConfiguration(
        title: 'Deginage',
        logLevel: MPVLogLevel.warn,
      ),
    );
    final controller = VideoController(player);
    slide.player = player;
    slide.controller = controller;
    final serial = slide.serial;

    slide.subs.addAll([
      player.stream.completed.listen((done) {
        if (done && _current?.serial == serial && !widget.paused && mounted) {
          SignageLog.write('動画の再生完了: ${fileNameOf(item.path)}');
          _advance();
        }
      }),
      player.stream.error.listen((e) {
        SignageLog.write('動画エラー: ${fileNameOf(item.path)}: $e');
      }),
      player.stream.log.listen((l) {
        SignageLog.write('mpv[${l.level}] ${l.prefix}: ${l.text}');
      }),
      player.stream.duration.listen((d) {
        if (d > Duration.zero) {
          _watchdog?.cancel();
          SignageLog.write(
            '動画読み込み完了: ${fileNameOf(item.path)} 長さ=${d.inMilliseconds}ms',
          );
        }
      }),
    ]);
  }

  Future<void> _openVideo(_Slide slide) async {
    final player = slide.player;
    if (player == null) return;
    final item = slide.item;
    final serial = slide.serial;

    try {
      await _applyAudioDevice(player);
      if (!mounted || _current?.serial != serial) return;
      await player.setVolume(item.muted ? 0.0 : item.volume.clamp(0.0, 100.0));
      // 1 件のみ、または秒数指定の場合はループ再生
      await player.setPlaylistMode(
        (!item.playFullVideo || _items.length == 1)
            ? PlaylistMode.single
            : PlaylistMode.none,
      );
      if (!mounted || _current?.serial != serial) return;
      SignageLog.write('動画を開きます: ${item.path}');
      await player.open(Media(item.path), play: !widget.paused);
    } catch (e) {
      SignageLog.write('動画の開始に失敗: ${item.path}: $e');
      if (mounted && _current?.serial == serial) _advance();
      return;
    }

    if (mounted && _current?.serial == serial && !widget.paused) {
      if (!item.playFullVideo) _scheduleAdvance(item.durationSec);
      // 読み込めない動画で停止し続けないよう監視
      _watchdog = Timer(const Duration(seconds: 15), () {
        if (_current?.serial == serial &&
            (player.state.duration == Duration.zero)) {
          SignageLog.write('動画を読み込めないためスキップ: ${item.path}');
          _advance();
        }
      });
    }
  }

  Future<void> _retireCurrent({bool immediately = false}) async {
    final old = _current;
    _current = null;
    if (old != null) {
      if (immediately) {
        await old.dispose();
      } else {
        _retiring.add(old);
      }
    }
  }

  void _disposeRetiring() {
    final list = [..._retiring];
    _retiring.clear();
    for (final s in list) {
      s.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = Color(widget.display.backgroundColor);
    final slide = _current;
    if (_items.isEmpty) {
      return _emptyView(bg, 'データセット「${widget.dataset.name}」にコンテンツがありません');
    }
    if (slide == null) {
      return _emptyView(bg, '再生可能なファイルが見つかりません');
    }
    return ColoredBox(
      color: bg,
      child: TransitionSwitcher(
        transition: _transition,
        backgroundColor: bg,
        onTransitionCompleted: _disposeRetiring,
        child: _buildSlide(slide, bg),
      ),
    );
  }

  Widget _buildSlide(_Slide slide, Color bg) {
    final item = slide.item;
    final Widget child;
    if (item.kind == MediaKind.video && slide.controller != null) {
      child = Video(
        controller: slide.controller!,
        fit: toBoxFit(item.fit),
        fill: bg,
        controls: NoVideoControls,
        pauseUponEnteringBackgroundMode: false,
        wakelock: true,
      );
    } else {
      child = Image.file(
        File(item.path),
        fit: toBoxFit(item.fit),
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            _emptyView(bg, '画像を読み込めませんでした: ${fileNameOf(item.path)}'),
      );
    }
    return KeyedSubtree(
      key: slide.key,
      child: ColoredBox(
        color: bg,
        child: SizedBox.expand(child: child),
      ),
    );
  }

  Widget _emptyView(Color bg, String message) {
    final isDark = bg.computeLuminance() < 0.5;
    return Container(
      color: bg,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.tv_off,
            size: 64,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 22,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '設定画面からコンテンツを追加してください（Ctrl + Q で終了）',
            style: TextStyle(
              fontSize: 15,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }
}
