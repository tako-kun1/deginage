import 'package:flutter/material.dart';

import '../src/rust/api/models.dart';

/// 2つのコンテンツ間を指定のトランジションで切り替えるウィジェット
class TransitionSwitcher extends StatefulWidget {
  const TransitionSwitcher({
    super.key,
    required this.child,
    required this.transition,
    this.backgroundColor = Colors.black,
    this.onTransitionCompleted,
  });

  final Widget child;
  final TransitionSetting transition;
  final Color backgroundColor;
  final VoidCallback? onTransitionCompleted;

  @override
  State<TransitionSwitcher> createState() => _TransitionSwitcherState();
}

class _TransitionSwitcherState extends State<TransitionSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) {
          setState(() => _previous = null);
        }
        widget.onTransitionCompleted?.call();
      }
    });

  Widget? _previous;
  late Widget _current = widget.child;
  TransitionKind _activeKind = TransitionKind.none;

  @override
  void didUpdateWidget(covariant TransitionSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.child.key != oldWidget.child.key) {
      final kind = widget.transition.kind;
      final ms = widget.transition.durationMs;
      if (kind == TransitionKind.none || ms <= 0) {
        _controller.stop();
        _previous = null;
        _current = widget.child;
        _activeKind = TransitionKind.none;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onTransitionCompleted?.call();
        });
      } else {
        _previous = _current;
        _current = widget.child;
        _activeKind = kind;
        _controller
          ..duration = Duration(milliseconds: ms)
          ..forward(from: 0.0);
      }
    } else {
      _current = widget.child;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_previous == null || !_controller.isAnimating) {
      return SizedBox.expand(child: _current);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        final prev = _previous!;
        final curr = _current;

        return switch (_activeKind) {
          TransitionKind.none => SizedBox.expand(child: curr),
          TransitionKind.crossFade => Stack(
            fit: StackFit.expand,
            children: [
              prev,
              Opacity(opacity: t, child: curr),
            ],
          ),
          TransitionKind.fadeThroughBlack => Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black),
              if (t < 0.5)
                Opacity(opacity: 1.0 - t * 2.0, child: prev)
              else
                Opacity(opacity: (t - 0.5) * 2.0, child: curr),
            ],
          ),
          TransitionKind.slideLeft => _slide(prev, curr, t, const Offset(1, 0)),
          TransitionKind.slideRight => _slide(
            prev,
            curr,
            t,
            const Offset(-1, 0),
          ),
          TransitionKind.slideUp => _slide(prev, curr, t, const Offset(0, 1)),
          TransitionKind.slideDown => _slide(
            prev,
            curr,
            t,
            const Offset(0, -1),
          ),
          TransitionKind.zoomIn => Stack(
            fit: StackFit.expand,
            children: [
              Opacity(opacity: 1.0 - t, child: prev),
              Opacity(
                opacity: t,
                child: Transform.scale(scale: 0.85 + 0.15 * t, child: curr),
              ),
            ],
          ),
          TransitionKind.zoomOut => Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: 1.0 - t,
                child: Transform.scale(scale: 1.0 + 0.15 * t, child: prev),
              ),
              Opacity(opacity: t, child: curr),
            ],
          ),
          TransitionKind.wipe => Stack(
            fit: StackFit.expand,
            children: [
              prev,
              ClipRect(clipper: _WipeClipper(t), child: curr),
            ],
          ),
        };
      },
    );
  }

  Widget _slide(Widget prev, Widget curr, double t, Offset enterFrom) {
    final exitTo = Offset(-enterFrom.dx, -enterFrom.dy);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          FractionalTranslation(
            translation: Offset.lerp(Offset.zero, exitTo, t)!,
            child: prev,
          ),
          FractionalTranslation(
            translation: Offset.lerp(enterFrom, Offset.zero, t)!,
            child: curr,
          ),
        ],
      ),
    );
  }
}

class _WipeClipper extends CustomClipper<Rect> {
  _WipeClipper(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * progress.clamp(0.0, 1.0), size.height);

  @override
  bool shouldReclip(covariant _WipeClipper oldClipper) =>
      oldClipper.progress != progress;
}
