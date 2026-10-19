// Grafik ringan tanpa paket tambahan: gauge zona, sparkline, kurva tenaga
// genggam live, tren per lansia, dan jumlah lansia per jam.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/motion.dart';
import '../app/theme.dart';
import '../utils/health_zones.dart';

String chartNum(double v, [int decimals = 1]) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v.toStringAsFixed(decimals).replaceAll('.', ',');
}

Color _ink(Color c) => Color.lerp(c, const Color(0xFF1F2430), 0.32)!;

/// Untuk teks berwarna zona di latar putih: lebih gelap supaya ≥ 4,5:1.
Color _textInk(Color c) => Color.lerp(c, const Color(0xFF1F2430), 0.55)!;

TextPainter _label(
  String text,
  double size,
  Color color, {
  FontWeight w = FontWeight.w500,
}) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(
      fontFamily: AppText.family,
      fontSize: size,
      color: color,
      fontWeight: w,
      height: 1,
    ),
  ),
  textDirection: TextDirection.ltr,
)..layout();

// ─── Gauge zona ──────────────────────────────────────────────────────────────

/// Bilah berwarna per zona dengan penanda nilai. Tanpa nilai, bilah tampil
/// redup sebagai panduan rentang normal.
class RangeGauge extends StatelessWidget {
  final GaugeSpec spec;
  final double? value;
  final bool compact;
  final bool showCaption;

  /// Bila diisi, nilai ditulis tebal di samping judul (layar hasil).
  final String? valueText;

  const RangeGauge({
    super.key,
    required this.spec,
    required this.value,
    this.compact = false,
    this.showCaption = true,
    this.valueText,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    final zone = v == null ? null : spec.zoneOf(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showCaption)
          if (compact && zone == null)
            Text(
              spec.normalText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.w400(10.5, AppColors.grey4),
            )
          else
            Row(
              children: [
                Flexible(
                  flex: valueText != null ? 3 : 1,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: spec.caption),
                        if (valueText != null)
                          TextSpan(
                            text: '  $valueText',
                            style: AppText.w700(15, AppColors.charcoal),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.w500(
                      compact ? 11 : 14,
                      compact ? AppColors.grey4 : AppColors.grey1,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    zone != null ? zone.label : spec.normalText,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: zone != null
                        ? AppText.w600(
                            compact ? 11.5 : 14,
                            _textInk(zone.color),
                          )
                        : AppText.w400(
                            compact ? 10.5 : 14,
                            compact ? AppColors.grey4 : AppColors.grey1,
                          ),
                  ),
                ),
              ],
            ),
        SizedBox(
          height: compact ? 28 : 34,
          child: CustomPaint(
            painter: _GaugePainter(spec: spec, value: v, compact: compact),
          ),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final GaugeSpec spec;
  final double? value;
  final bool compact;
  _GaugePainter({
    required this.spec,
    required this.value,
    required this.compact,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const markerR = 8.0;
    final barH = compact ? 8.0 : 10.0;
    final left = markerR, right = size.width - markerR;
    final w = right - left;
    final top = markerR - barH / 2 + 1;
    double xOf(double v) =>
        left + ((v - spec.min) / (spec.max - spec.min)).clamp(0.0, 1.0) * w;
    final rr = RRect.fromLTRBR(
      left,
      top,
      right,
      top + barH,
      Radius.circular(barH / 2),
    );
    final muted = value == null;

    canvas.save();
    canvas.clipRRect(rr);
    for (final z in spec.zones) {
      canvas.drawRect(
        Rect.fromLTRB(xOf(z.from), top, xOf(z.to), top + barH),
        Paint()..color = z.color.withValues(alpha: muted ? 0.38 : 0.9),
      );
    }
    canvas.restore();
    // Garis tipis di batas zona.
    for (final z in spec.zones.skip(1)) {
      final x = xOf(z.from);
      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + barH),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..strokeWidth = 1.5,
      );
    }

    // Angka batas, urut prioritas; yang bertabrakan dilewati.
    final used = <(double, double)>[];
    for (final t in spec.ticks) {
      final tp = _label(
        chartNum(t, spec.decimals),
        compact ? 10 : 14,
        compact ? AppColors.grey4 : AppColors.grey1,
      );
      final x = (xOf(t) - tp.width / 2).clamp(0.0, size.width - tp.width);
      if (used.any((u) => x < u.$2 + 4 && x + tp.width > u.$1 - 4)) continue;
      used.add((x, x + tp.width));
      tp.paint(canvas, Offset(x, top + barH + 3));
    }

    final v = value;
    if (v == null) return;
    final z = spec.zoneOf(v);
    final c = Offset(xOf(v), top + barH / 2);
    canvas.drawCircle(
      c + const Offset(0, 1.5),
      markerR,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(c, markerR, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      markerR - 1.5,
      Paint()
        ..color = _ink(z.color)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.spec != spec || old.compact != compact;
}

// ─── Sparkline ───────────────────────────────────────────────────────────────

class Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double? min;
  final double? max;

  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.min,
    this.max,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SparkPainter(values, color, min, max),
    size: Size.infinite,
  );
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double? min, max;
  _SparkPainter(this.values, this.color, this.min, this.max);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      final y = size.height * 0.6;
      final dash = Paint()
        ..color = AppColors.grey3
        ..strokeWidth = 1.5;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, size.width), y),
          dash,
        );
      }
      return;
    }
    var lo = min ?? values.reduce(math.min);
    var hi = max ?? values.reduce(math.max);
    if (hi - lo < 4) {
      final mid = (hi + lo) / 2;
      lo = mid - 2;
      hi = mid + 2;
    }
    final dx = size.width / (values.length - 1);
    Offset at(int i) => Offset(
      i * dx,
      size.height - 3 - (values[i] - lo) / (hi - lo) * (size.height - 6),
    );
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p0 = at(i - 1), p1 = at(i);
      final mx = (p0.dx + p1.dx) / 2;
      line.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [
          color.withValues(alpha: 0.28),
          color.withValues(alpha: 0.0),
        ]),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final last = at(values.length - 1);
    canvas.drawCircle(last, 4.5, Paint()..color = Colors.white);
    canvas.drawCircle(last, 3.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      !listEquals(old.values, values) || old.color != color;
}

// ─── Kurva tenaga genggam live ───────────────────────────────────────────────

/// Kurva tenaga remasan beberapa detik terakhir dan puncak tertinggi di
/// jendela waktu. [cutoff] opsional: garis batas hanya bila ada acuan resmi.
class LiveForceChart extends StatefulWidget {
  final ValueListenable<double> source;
  final double? cutoff;
  final double height;

  const LiveForceChart({
    super.key,
    required this.source,
    this.cutoff,
    this.height = 64,
  });

  @override
  State<LiveForceChart> createState() => _LiveForceChartState();
}

class _LiveForceChartState extends State<LiveForceChart>
    with SingleTickerProviderStateMixin {
  static const _window = 90; // ±4,5 detik pada 20 sampel/detik
  final List<double> _buf = [];
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (Motion.enabled) {
      _ticker = createTicker((elapsed) {
        if (elapsed - _last >= const Duration(milliseconds: 50)) {
          _last = elapsed;
          _push(widget.source.value);
        }
      })..start();
    } else {
      widget.source.addListener(_onValue);
    }
    _push(widget.source.value);
  }

  void _onValue() => _push(widget.source.value);

  void _push(double v) {
    setState(() {
      _buf.add(v);
      if (_buf.length > _window) _buf.removeAt(0);
    });
  }

  @override
  void dispose() {
    _ticker?.dispose();
    widget.source.removeListener(_onValue);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: CustomPaint(
      painter: _ForcePainter(
        List.of(_buf),
        widget.cutoff,
        // Tanpa ticker (screenshot/test) kurva direntangkan selebar kotak.
        window: Motion.enabled ? _window : math.max(_buf.length, 2),
      ),
      size: Size.infinite,
    ),
  );
}

class _ForcePainter extends CustomPainter {
  final List<double> v;
  final double? cutoff;
  final int window;
  _ForcePainter(this.v, this.cutoff, {required this.window});

  @override
  void paint(Canvas canvas, Size size) {
    final peak = v.isEmpty ? 0.0 : v.reduce(math.max);
    final cut = cutoff;
    final hi = math.max((cut ?? 20) * 1.6, peak * 1.15).clamp(20.0, 90.0);
    final rr = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.drawRRect(rr, Paint()..color = const Color(0xFFF2FBF7));
    double y(double x) => size.height - 4 - (x / hi) * (size.height - 10);

    // Garis batas (hanya bila ada acuan).
    if (cut != null) {
      final cy = y(cut);
      final dash = Paint()
        ..color = ZoneColors.watch
        ..strokeWidth = 1.5;
      for (var x = 6.0; x < size.width - 6; x += 9) {
        canvas.drawLine(
          Offset(x, cy),
          Offset(math.min(x + 5, size.width - 6), cy),
          dash,
        );
      }
      final cl = _label(
        'batas ${chartNum(cut)} kg',
        10,
        _ink(ZoneColors.watch),
      );
      cl.paint(canvas, Offset(8, cy - cl.height - 3));
    }

    if (v.length < 2) return;
    final n = window;
    final dx = (size.width - 8) / (n - 1);
    final x0 = size.width - 4 - (v.length - 1) * dx;
    final line = Path()..moveTo(x0, y(v.first));
    for (var i = 1; i < v.length; i++) {
      line.lineTo(x0 + i * dx, y(v[i]));
    }
    final area = Path.from(line)
      ..lineTo(x0 + (v.length - 1) * dx, size.height - 4)
      ..lineTo(x0, size.height - 4)
      ..close();
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawPath(
      area,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, size.height), [
          ZoneColors.good.withValues(alpha: 0.45),
          ZoneColors.good.withValues(alpha: 0.05),
        ]),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = const Color(0xFF1E9C6C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    // Puncak di jendela.
    if (peak >= 2) {
      final i = v.indexOf(peak);
      final p = Offset(x0 + i * dx, y(peak));
      canvas.drawCircle(p, 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(p, 3.2, Paint()..color = const Color(0xFF1E9C6C));
      final pl = _label(
        '${chartNum(peak)} kg',
        11,
        const Color(0xFF13734F),
        w: FontWeight.w700,
      );
      final lx = (p.dx - pl.width / 2).clamp(4.0, size.width - pl.width - 4);
      final ly = math.max(2.0, p.dy - pl.height - 6);
      pl.paint(canvas, Offset(lx, ly));
    }
  }

  @override
  bool shouldRepaint(covariant _ForcePainter old) => true;
}

// ─── Tren per lansia ─────────────────────────────────────────────────────────

@immutable
class TrendSeries {
  final String name;
  final Color color;
  final List<(DateTime, double)> points;
  const TrendSeries(this.name, this.color, this.points);
}

/// Garis tren beberapa kunjungan; pita hijau = rentang normal.
class TrendChart extends StatelessWidget {
  final List<TrendSeries> series;
  final List<(double, double)> normalBands;
  final String unit;
  final double height;

  const TrendChart({
    super.key,
    required this.series,
    this.normalBands = const [],
    this.unit = '',
    this.height = 170,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _TrendPainter(series, normalBands, unit),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final s in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(s.name, style: AppText.w500(14, AppColors.grey1)),
                ],
              ),
            if (normalBands.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 10,
                    decoration: BoxDecoration(
                      color: ZoneColors.good.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Rentang normal',
                    style: AppText.w500(14, AppColors.grey1),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<TrendSeries> series;
  final List<(double, double)> bands;
  final String unit;
  _TrendPainter(this.series, this.bands, this.unit);

  @override
  void paint(Canvas canvas, Size size) {
    final all = [
      for (final s in series)
        for (final p in s.points) p.$2,
    ];
    if (all.isEmpty) return;
    var lo = all.reduce(math.min), hi = all.reduce(math.max);
    for (final (a, b) in bands) {
      lo = math.min(lo, a);
      hi = math.max(hi, b);
    }
    final pad = (hi - lo) * 0.12 + 1;
    lo -= pad;
    hi += pad;
    const leftAxis = 38.0, bottomAxis = 22.0, topPad = 16.0, rightPad = 42.0;
    final plotW = size.width - leftAxis - rightPad;
    final plotH = size.height - bottomAxis - topPad;
    double y(double v) => topPad + (1 - (v - lo) / (hi - lo)) * plotH;

    // Tanggal kunjungan (gabungan semua seri, urut).
    final dates = <DateTime>{
      for (final s in series)
        for (final p in s.points) p.$1,
    }.toList()..sort();
    double x(DateTime d) => dates.length == 1
        ? leftAxis + plotW / 2
        : leftAxis + dates.indexOf(d) / (dates.length - 1) * plotW;

    for (final (a, b) in bands) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          leftAxis,
          y(b),
          leftAxis + plotW,
          y(a),
          const Radius.circular(4),
        ),
        Paint()..color = ZoneColors.good.withValues(alpha: 0.13),
      );
    }
    // Garis bantu + angka sumbu.
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var k = 0; k <= 3; k++) {
      final v = lo + (hi - lo) * k / 3;
      final yy = y(v);
      canvas.drawLine(Offset(leftAxis, yy), Offset(leftAxis + plotW, yy), grid);
      final tp = _label(v.round().toString(), 14, AppColors.grey1);
      tp.paint(canvas, Offset(leftAxis - tp.width - 6, yy - tp.height / 2));
    }
    // Label tanggal (maks. 6).
    final step = math.max(1, (dates.length / 6).ceil());
    for (var i = 0; i < dates.length; i++) {
      if (i % step != 0 && i != dates.length - 1) continue;
      final d = dates[i];
      final tp = _label('${d.day}/${d.month}', 14, AppColors.grey1);
      tp.paint(canvas, Offset(x(d) - tp.width / 2, size.height - tp.height));
    }

    for (final s in series) {
      if (s.points.isEmpty) continue;
      final pts = [for (final p in s.points) Offset(x(p.$1), y(p.$2))];
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round,
      );
      for (final p in pts) {
        canvas.drawCircle(p, 4.5, Paint()..color = Colors.white);
        canvas.drawCircle(p, 3.3, Paint()..color = s.color);
      }
      final lastV = s.points.last.$2;
      final tp = _label(
        chartNum(lastV),
        14,
        _textInk(s.color),
        w: FontWeight.w700,
      );
      tp.paint(canvas, Offset(pts.last.dx + 8, pts.last.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => true;
}

// ─── Lansia per jam ──────────────────────────────────────────────────────────

class HourlyBars extends StatelessWidget {
  /// Jumlah per jam (0–23).
  final Map<int, int> counts;
  final int? currentHour;
  final double height;

  const HourlyBars({
    super.key,
    required this.counts,
    this.currentHour,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: CustomPaint(
      painter: _HourPainter(counts, currentHour),
      size: Size.infinite,
    ),
  );
}

class _HourPainter extends CustomPainter {
  final Map<int, int> counts;
  final int? now;
  _HourPainter(this.counts, this.now);

  @override
  void paint(Canvas canvas, Size size) {
    final hours = counts.keys.toList();
    var from = 7, to = 15;
    if (hours.isNotEmpty) {
      from = math.min(from, hours.reduce(math.min));
      to = math.max(to, hours.reduce(math.max));
    }
    if (now != null) {
      from = math.min(from, now!);
      to = math.max(to, now!);
    }
    final n = to - from + 1;
    final maxC = math.max(3, counts.values.fold<int>(0, math.max));
    const bottom = 20.0, topPad = 18.0;
    final slot = size.width / n;
    final bw = math.min(28.0, slot * 0.62);
    final plotH = size.height - bottom - topPad;
    canvas.drawLine(
      Offset(0, size.height - bottom),
      Offset(size.width, size.height - bottom),
      Paint()..color = AppColors.border,
    );
    for (var i = 0; i < n; i++) {
      final h = from + i;
      final c = counts[h] ?? 0;
      final cx = slot * i + slot / 2;
      final isNow = h == now;
      if (c > 0) {
        final bh = math.max(4.0, c / maxC * plotH);
        final r = RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - bw / 2, size.height - bottom - bh, bw, bh),
          topLeft: const Radius.circular(6),
          topRight: const Radius.circular(6),
        );
        canvas.drawRRect(
          r,
          Paint()
            ..shader = ui.Gradient.linear(
              r.outerRect.topCenter,
              r.outerRect.bottomCenter,
              [
                isNow
                    ? AppColors.primary
                    : AppColors.blueDenim.withValues(alpha: 0.75),
                isNow
                    ? AppColors.blueDenim
                    : AppColors.blueDenim.withValues(alpha: 0.45),
              ],
            ),
        );
        final tp = _label(
          '$c',
          11,
          isNow ? AppColors.primary : AppColors.grey1,
          w: FontWeight.w700,
        );
        tp.paint(
          canvas,
          Offset(cx - tp.width / 2, size.height - bottom - bh - tp.height - 3),
        );
      }
      // Jam yang punya batang selalu diberi label.
      if (n <= 12 || i % 2 == 0 || isNow || c > 0) {
        final tp = _label(
          h.toString().padLeft(2, '0'),
          10.5,
          isNow ? AppColors.primary : AppColors.grey4,
          w: isNow ? FontWeight.w700 : FontWeight.w500,
        );
        tp.paint(canvas, Offset(cx - tp.width / 2, size.height - tp.height));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HourPainter old) =>
      !mapEquals(old.counts, counts) || old.now != now;
}
