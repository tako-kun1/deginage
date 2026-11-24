import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../src/rust/api/eew.dart';
import '../src/rust/api/intensity.dart';

/// 緊急地震速報の警告画面（image.png をベースに構成）
class EewAlertView extends StatefulWidget {
  const EewAlertView({
    super.key,
    required this.report,
    required this.evaluation,
  });

  final EewReport report;
  final EewEvaluation evaluation;

  @override
  State<EewAlertView> createState() => _EewAlertViewState();
}

class _EewAlertViewState extends State<EewAlertView> {
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  int? get _remainingSeconds {
    final arrival = widget.evaluation.sArrivalEpochMs;
    if (arrival == null) return null;
    final diffMs = arrival - _now.millisecondsSinceEpoch;
    return (diffMs / 1000).ceil();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFAD547),
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 1280,
          height: 720,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(36, 20, 36, 24),
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 18),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 440,
                        child: Column(
                          children: [
                            const SizedBox(
                              width: 220,
                              height: 220,
                              child: CustomPaint(painter: _QuakeIconPainter()),
                            ),
                            const SizedBox(height: 20),
                            Expanded(child: _buildCountdownPanel()),
                          ],
                        ),
                      ),
                      const SizedBox(width: 36),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildGuidanceMessages(),
                            const SizedBox(height: 16),
                            _buildEewFooterBanner(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 120,
          height: 112,
          child: CustomPaint(painter: _WarningTrianglePainter()),
        ),
        const SizedBox(width: 24),
        const Text(
          '地震が発生しました',
          style: TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.w900,
            color: Colors.black,
            letterSpacing: 2,
            height: 1.1,
          ),
        ),
        if (widget.report.isTest) ...[
          const SizedBox(width: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'テスト',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCountdownPanel() {
    final rem = _remainingSeconds;
    final localClass = widget.evaluation.localIntensityClass;
    final dist = widget.evaluation.distanceKm;

    final String mainText;
    final String subText;
    final Color accent;
    if (rem == null) {
      mainText = '警戒';
      subText = '強い揺れに備えてください';
      accent = Colors.amber.shade300;
    } else if (rem > 0) {
      mainText = 'あと $rem 秒';
      subText = '主要動到達まで（推定）';
      accent = rem <= 10 ? const Color(0xFFFF5252) : Colors.amber.shade300;
    } else {
      mainText = '到達中';
      subText = '頭を守り揺れが収まるまで待機';
      accent = const Color(0xFFFF5252);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF545456),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            subText,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            mainText,
            style: TextStyle(
              color: accent,
              fontSize: 64,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              if (localClass.isNotEmpty)
                _infoChip('所在地 予測震度 ${intensityLabel(raw: localClass)}'),
              if (dist != null) _infoChip('震源距離 約${dist.round()}km'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildGuidanceMessages() {
    return const Column(
      children: [
        Text(
          'カバンなどで頭を守り姿勢を低くしてください。',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            color: Colors.black,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 14),
        Text(
          '店員の指示に従って\n避難を行ってください。',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            color: Colors.black,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 16),
        Divider(color: Colors.black, thickness: 3, height: 3),
        SizedBox(height: 16),
        Text(
          'Protect your head with a bag or something\nand keep your body low.',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w500,
            color: Colors.black,
            height: 1.35,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 14),
        Text(
          'Follow the instructions of\nthe store staff and evacuate.',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w500,
            color: Colors.black,
            height: 1.35,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildEewFooterBanner() {
    final r = widget.report;
    final maxLabel = intensityLabel(raw: r.maxIntensity);
    final hypo = r.hypocenter.isEmpty ? '調査中' : r.hypocenter;
    final mag = r.magnitude > 0 ? 'M${r.magnitude.toStringAsFixed(1)}' : '';
    final depth = r.depth > 0 ? '深さ${r.depth.round()}km' : '';
    final detail = [
      '震源: $hypo',
      if (mag.isNotEmpty) mag,
      if (depth.isNotEmpty) depth,
      '最大予測震度 $maxLabel',
    ].join('  /  ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF727275),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            r.title.isEmpty ? '緊急地震速報' : '${r.title}（第${r.serial}報）',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// 警告の三角アイコン
class _WarningTrianglePainter extends CustomPainter {
  const _WarningTrianglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.5, h * 0.06)
      ..lineTo(w * 0.94, h * 0.90)
      ..lineTo(w * 0.06, h * 0.90)
      ..close();

    final stroke = Paint()
      ..color = const Color(0xFFE8A328)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.10
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = const Color(0xFFFFCA4F)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, stroke);
    canvas.drawPath(path, fill);

    // 感嘆符
    final mark = Paint()
      ..color = const Color(0xFF2B2B2B)
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final bar = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.52),
        width: w * 0.11,
        height: h * 0.34,
      ),
      Radius.circular(w * 0.055),
    );
    canvas.drawRRect(bar, mark);
    canvas.drawCircle(Offset(w * 0.5, h * 0.78), w * 0.06, mark);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 揺れる建物と家のピクトグラム（image.png 左上の再現）
class _QuakeIconPainter extends CustomPainter {
  const _QuakeIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final black = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    // 外枠
    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06;
    canvas.drawRect(
      Rect.fromLTWH(w * 0.03, h * 0.03, w * 0.94, h * 0.94),
      border,
    );

    // 地面バー
    canvas.drawRect(
      Rect.fromLTWH(w * 0.03, h * 0.80, w * 0.94, h * 0.17),
      black,
    );

    // 左側のビル（枠と窓4つ）
    final bldgRect = Rect.fromLTWH(w * 0.30, h * 0.22, w * 0.34, h * 0.60);
    canvas.drawRect(bldgRect, black);

    final bg = Paint()
      ..color = const Color(0xFFFAD547)
      ..style = PaintingStyle.fill;
    // ビルの内側をくり抜いて窓と柱を表現
    canvas.drawRect(Rect.fromLTWH(w * 0.35, h * 0.27, w * 0.24, h * 0.53), bg);
    // 4つの窓
    for (final rx in [0.38, 0.49]) {
      for (final ry in [0.31, 0.44]) {
        canvas.drawRect(
          Rect.fromLTWH(w * rx, h * ry, w * 0.08, h * 0.09),
          black,
        );
      }
    }

    // 右下の小さい家
    final houseRoof = Path()
      ..moveTo(w * 0.48, h * 0.62)
      ..lineTo(w * 0.56, h * 0.53)
      ..lineTo(w * 0.82, h * 0.53)
      ..lineTo(w * 0.90, h * 0.62)
      ..close();
    canvas.drawPath(houseRoof, black);
    canvas.drawRect(
      Rect.fromLTWH(w * 0.53, h * 0.61, w * 0.32, h * 0.20),
      black,
    );
    // 家の窓2つ
    canvas.drawRect(Rect.fromLTWH(w * 0.58, h * 0.67, w * 0.08, h * 0.08), bg);
    canvas.drawRect(Rect.fromLTWH(w * 0.71, h * 0.67, w * 0.08, h * 0.08), bg);

    // 左右の揺れ波線
    final wave = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.04
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void drawWave(double x, double top, double bottom, int cycles) {
      final p = Path()..moveTo(x, top);
      final step = (bottom - top) / (cycles * 2);
      for (var i = 0; i < cycles * 2; i++) {
        final dx = (i.isEven ? -1 : 1) * w * 0.04;
        p.lineTo(x + dx, top + step * (i + 1));
      }
      canvas.drawPath(p, wave);
    }

    drawWave(w * 0.17, h * 0.34, h * 0.68, 3);
    drawWave(w * 0.78, h * 0.18, h * 0.47, 3);
    drawWave(w * 0.86, h * 0.20, h * 0.45, 3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// テストやプレビュー用の簡易ヘルパー
double clampRatio(double v) => math.max(0.0, math.min(1.0, v));
