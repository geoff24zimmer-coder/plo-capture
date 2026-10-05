import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tracker/format.dart';

typedef RunPoint = ({DateTime at, double hours, int total});

const _line = Color(0xFF10B981); // app accent — the one series
const _ink = Color(0xFFE8E6E1);

/// Cumulative net vs hours played (slope = hourly rate). One series, so no
/// legend; a drag/tap crosshair reads out any point, and the readout defaults
/// to the latest total.
class RunningTotalChart extends StatefulWidget {
  final List<RunPoint> points;
  final double height;
  const RunningTotalChart(
      {super.key, required this.points, this.height = 180});

  @override
  State<RunningTotalChart> createState() => _RunningTotalChartState();
}

class _RunningTotalChartState extends State<RunningTotalChart> {
  int? _sel; // index into points, null = show the latest

  void _pick(Offset local, double width) {
    final pts = widget.points;
    if (pts.isEmpty) return;
    final maxH = math.max(pts.last.hours, 1e-9);
    final h = (local.dx - _ChartPainter.padL) /
        (width - _ChartPainter.padL - _ChartPainter.padR) *
        maxH;
    var best = 0;
    for (var i = 1; i < pts.length; i++) {
      if ((pts[i].hours - h).abs() < (pts[best].hours - h).abs()) best = i;
    }
    setState(() => _sel = best);
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    final i = _sel ?? pts.length - 1;
    final p = pts[i];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: usd(p.total, signed: true),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
            TextSpan(
                text: '  after ${hoursShort(p.hours)}h · ${shortDate(p.at)}, '
                    '${p.at.year}${_sel == null ? '' : ' · session ${i + 1}'}',
                style: TextStyle(
                    fontSize: 12, color: _ink.withValues(alpha: 0.55))),
          ]),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (ctx, c) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _pick(d.localPosition, c.maxWidth),
            onHorizontalDragUpdate: (d) => _pick(d.localPosition, c.maxWidth),
            onDoubleTap: () => setState(() => _sel = null),
            child: CustomPaint(
              size: Size(c.maxWidth, widget.height),
              painter: _ChartPainter(pts, _sel),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  static const padL = 46.0, padR = 10.0, padT = 8.0, padB = 22.0;
  final List<RunPoint> pts;
  final int? sel;
  _ChartPainter(this.pts, this.sel);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - padL - padR, h = size.height - padT - padB;
    final maxH = math.max(pts.last.hours, 1e-9);
    var lo = 0, hi = 0;
    for (final p in pts) {
      lo = math.min(lo, p.total);
      hi = math.max(hi, p.total);
    }
    if (lo == hi) hi = lo + 100;
    final span = (hi - lo).toDouble();
    final yLo = lo - span * 0.06, yHi = hi + span * 0.06;
    double x(double hours) => padL + hours / maxH * w;
    double y(int v) => padT + (yHi - v) / (yHi - yLo) * h;

    final grid = Paint()
      ..color = _ink.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    final zero = Paint()
      ..color = _ink.withValues(alpha: 0.32)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(padL, y(hi)), Offset(padL + w, y(hi)), grid);
    canvas.drawLine(Offset(padL, y(lo)), Offset(padL + w, y(lo)), grid);
    canvas.drawLine(Offset(padL, y(0)), Offset(padL + w, y(0)), zero);

    void label(String t, Offset at, {TextAlign align = TextAlign.right}) {
      final tp = TextPainter(
        text: TextSpan(
            text: t,
            style: TextStyle(fontSize: 10, color: _ink.withValues(alpha: 0.5))),
        textDirection: TextDirection.ltr,
        textAlign: align,
      )..layout();
      final dx = switch (align) {
        TextAlign.right => at.dx - tp.width,
        TextAlign.center => at.dx - tp.width / 2,
        _ => at.dx,
      };
      tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
    }

    // Y labels at the extremes and zero (skipped where they'd collide).
    label(usdCompact(hi), Offset(padL - 6, y(hi)));
    if ((y(0) - y(hi)).abs() > 14 && (y(0) - y(lo)).abs() > 14) {
      label('0', Offset(padL - 6, y(0)));
    }
    if (lo != 0) label(usdCompact(lo), Offset(padL - 6, y(lo)));
    final base = size.height - padB / 2 + 2;
    label('0h', Offset(padL, base), align: TextAlign.left);
    label('${hoursShort(maxH)}h', Offset(padL + w, base));
    label('hours played', Offset(padL + w / 2, base), align: TextAlign.center);

    final path = Path()..moveTo(x(0), y(0));
    for (final p in pts) {
      path.lineTo(x(p.hours), y(p.total));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final i = sel ?? pts.length - 1;
    final c = Offset(x(pts[i].hours), y(pts[i].total));
    if (sel != null) {
      canvas.drawLine(Offset(c.dx, padT), Offset(c.dx, padT + h),
          Paint()
            ..color = _ink.withValues(alpha: 0.35)
            ..strokeWidth = 1);
    }
    // 8px marker with a surface ring so it reads over the line.
    canvas.drawCircle(c, 6, Paint()..color = const Color(0xFF0C0F0E));
    canvas.drawCircle(c, 4, Paint()..color = _line);
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.pts != pts || old.sel != sel;
}
