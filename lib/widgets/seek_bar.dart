import 'package:flutter/material.dart';

import '../theme.dart';

/// 进度条：拖动时只预览，松手才跳转；显示缓冲和 A、B 标记。
class SeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final Duration? a;
  final Duration? b;
  final bool enabled;
  final ValueChanged<Duration?> onPreview; // null 表示结束预览
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onInteract;

  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    this.a,
    this.b,
    required this.enabled,
    required this.onPreview,
    required this.onSeek,
    this.onInteract,
  });

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag; // 0..1

  double _frac(Duration d) {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (d.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Duration _at(double f) => Duration(milliseconds: (widget.duration.inMilliseconds * f.clamp(0.0, 1.0)).round());

  void _update(double dx, double width) {
    final f = (dx / width).clamp(0.0, 1.0);
    setState(() => _drag = f);
    widget.onPreview(_at(f));
    widget.onInteract?.call();
  }

  void _end() {
    final f = _drag;
    if (f == null) return;
    setState(() => _drag = null);
    widget.onPreview(null);
    widget.onSeek(_at(f));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.duration > Duration.zero;
    return Semantics(
      slider: true,
      label: '播放进度',
      enabled: enabled,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: enabled ? (d) => _update(d.localPosition.dx, w) : null,
          onHorizontalDragUpdate: enabled ? (d) => _update(d.localPosition.dx, w) : null,
          onHorizontalDragEnd: enabled ? (_) => _end() : null,
          onHorizontalDragCancel: enabled ? _end : null,
          onTapDown: enabled ? (d) => _update(d.localPosition.dx, w) : null,
          onTapUp: enabled ? (_) => _end() : null,
          onTapCancel: enabled ? () => setState(() => _drag = null) : null,
          child: SizedBox(
            height: 36,
            width: w,
            child: CustomPaint(
              painter: _BarPainter(
                played: _drag ?? _frac(widget.position),
                buffered: _frac(widget.buffered),
                a: widget.a == null ? null : _frac(widget.a!),
                b: widget.b == null ? null : _frac(widget.b!),
                dragging: _drag != null,
                enabled: enabled,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _BarPainter extends CustomPainter {
  final double played, buffered;
  final double? a, b;
  final bool dragging, enabled;
  _BarPainter({
    required this.played,
    required this.buffered,
    this.a,
    this.b,
    required this.dragging,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size s) {
    const pad = 8.0;
    final w = s.width - pad * 2;
    final cy = s.height / 2;
    final h = dragging ? 5.0 : 3.5;
    RRect bar(double from, double to) => RRect.fromRectAndRadius(
        Rect.fromLTRB(pad + w * from, cy - h / 2, pad + w * to, cy + h / 2), Radius.circular(h / 2));
    canvas.drawRRect(bar(0, 1), Paint()..color = Colors.white.withValues(alpha: 0.22));
    if (buffered > 0) canvas.drawRRect(bar(0, buffered), Paint()..color = Colors.white.withValues(alpha: 0.38));
    if (a != null && b != null) {
      canvas.drawRect(
        Rect.fromLTRB(pad + w * a!, cy - 9, pad + w * b!, cy + 9),
        Paint()..color = kYellow.withValues(alpha: 0.22),
      );
    }
    if (!enabled) return;
    canvas.drawRRect(bar(0, played), Paint()..color = kYellow);
    void marker(double f, String label) {
      final x = pad + w * f;
      canvas.drawRect(Rect.fromLTWH(x - 1, cy - 10, 2, 20), Paint()..color = kYellow);
      final tp = TextPainter(
        text: TextSpan(text: label, style: const TextStyle(color: kYellow, fontSize: 10, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, cy - 10 - tp.height));
    }

    if (a != null) marker(a!, 'A');
    if (b != null) marker(b!, 'B');
    canvas.drawCircle(Offset(pad + w * played, cy), dragging ? 9 : 7, Paint()..color = kYellow);
  }

  @override
  bool shouldRepaint(covariant _BarPainter o) =>
      o.played != played || o.buffered != buffered || o.a != a || o.b != b || o.dragging != dragging || o.enabled != enabled;
}
