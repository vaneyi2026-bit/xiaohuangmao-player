import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';

/// 品牌小标：黄色圆角底 + 播放三角 + 一撮头发。
class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LogoPainter());
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final bg = RRect.fromRectAndRadius(Rect.fromLTWH(0, w * 0.12, w, w * 0.88), Radius.circular(w * 0.26));
    canvas.drawRRect(bg, Paint()..color = kYellow);
    final tri = Path()
      ..moveTo(w * 0.40, w * 0.38)
      ..lineTo(w * 0.40, w * 0.86)
      ..lineTo(w * 0.78, w * 0.62)
      ..close();
    canvas.drawPath(tri, Paint()..color = kInk);
    final hair = Paint()
      ..color = kInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.42, w * 0.16)
          ..quadraticBezierTo(w * 0.40, w * 0.02, w * 0.30, -w * 0.02),
        hair);
    canvas.drawPath(
        Path()
          ..moveTo(w * 0.52, w * 0.15)
          ..quadraticBezierTo(w * 0.56, w * 0.0, w * 0.68, -w * 0.03),
        hair);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 视频缩略图：时长角标与观看进度条。
class Thumb extends StatelessWidget {
  final MediaItem item;
  final double radius;
  final bool showProgress;
  const Thumb({super.key, required this.item, this.radius = 10, this.showProgress = true});

  @override
  Widget build(BuildContext context) {
    final rec = store.recOrNull(item.id);
    final path = store.thumbPath(item);
    final exists = File(path).existsSync();
    if (!exists) store.requestProbe(item);
    double? progress;
    if (showProgress && rec != null && item.durationMs > 0 && !rec.finished && rec.positionMs > 0) {
      progress = (rec.positionMs / item.durationMs).clamp(0.0, 1.0);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(fit: StackFit.expand, children: [
          Container(color: const Color(0xFF242424)),
          if (exists)
            Image.file(
              File(path),
              key: ValueKey('${item.id}_${store.thumbGen[item.id] ?? 0}'),
              fit: BoxFit.cover,
              cacheWidth: 360,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const _Placeholder(),
            )
          else
            const _Placeholder(),
          if (item.durationMs > 0)
            Positioned(
              right: 6,
              bottom: progress != null ? 9 : 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(5)),
                child: Text(fmtMs(item.durationMs),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ),
          if (rec?.finished == true)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(5)),
                child: const Text('已看完', style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
          if (progress != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                color: kYellow,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
              ),
            ),
          if (item.favorite)
            Positioned(
              top: 5,
              right: 5,
              child: Icon(Icons.star_rounded, size: 18, color: kYellow, shadows: [
                Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 4),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) =>
      const Center(child: Icon(Icons.movie_outlined, color: Colors.white38, size: 30));
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
        child: Row(children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

/// 横向滚动的视频卡片列表。
class MediaStrip extends StatelessWidget {
  final List<MediaItem> items;
  final void Function(MediaItem) onTap;
  const MediaStrip({super.key, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 142,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final it = items[i];
          return Semantics(
            button: true,
            label: '播放 ${it.name}',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onTap(it),
              child: SizedBox(
                width: 168,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Thumb(item: it),
                  const SizedBox(height: 6),
                  Text(it.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, height: 1.25, color: scheme.onSurface)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, String ok = '确定', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error, foregroundColor: Colors.white)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}
