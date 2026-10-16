import 'package:flutter/material.dart';

import '../import_service.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'import_sheet.dart';
import 'player_page.dart';
import 'recent_page.dart';

/// 观看：继续观看、导入入口、最近观看、最近添加、收藏。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _play(BuildContext context, MediaItem it) => PlayerPage.open(context, [it.id]);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([store, importer]),
      builder: (context, _) {
        final cont = store.continueItem;
        final recent = store.recentWatched;
        final added = store.recentAdded;
        final favs = store.favorites;
        return CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            title: const Row(children: [
              LogoMark(size: 26),
              SizedBox(width: 10),
              Text('小黄毛影音'),
            ]),
          ),
          if (importer.busy)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Material(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    leading: const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    title: Text('正在导入，还剩 ${importer.activeCount} 项'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showImportSheet(context),
                  ),
                ),
              ),
            ),
          if (cont != null)
            SliverToBoxAdapter(child: _ContinueCard(item: cont, onTap: () => _play(context, cont))),
          if (store.items.isEmpty)
            const SliverToBoxAdapter(child: _Welcome())
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        importer.pickAndImport('gallery');
                        showImportSheet(context);
                      },
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('从相册导入'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        importer.pickAndImport('file');
                        showImportSheet(context);
                      },
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('从文件导入'),
                    ),
                  ),
                ]),
              ),
            ),
          if (recent.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader('最近观看',
                  action: '全部',
                  onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecentPage()))),
            ),
            SliverToBoxAdapter(child: MediaStrip(items: recent.take(12).toList(), onTap: (it) => _play(context, it))),
          ],
          if (added.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader('最近添加')),
            SliverToBoxAdapter(child: MediaStrip(items: added.take(12).toList(), onTap: (it) => _play(context, it))),
          ],
          if (favs.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader('收藏')),
            SliverToBoxAdapter(child: MediaStrip(items: favs.take(12).toList(), onTap: (it) => _play(context, it))),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ]);
      },
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  const _ContinueCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rec = store.rec(item.id);
    final pos = fmtMs(rec.positionMs);
    final total = item.durationMs > 0 ? ' / ${fmtMs(item.durationMs)}' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              MediaThumb(item: item, radius: 0),
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: kYellow,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16)],
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: kInk, size: 38),
                  ),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('继续观看',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.secondary)),
                const SizedBox(height: 4),
                Text(item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('看到 $pos$total', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(children: [
        const LogoMark(size: 72),
        const SizedBox(height: 20),
        const Text('把视频放进来', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('从相册或文件导入视频。下次打开，点一下就能从上次的位置继续看。',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.5, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: () {
              importer.pickAndImport('gallery');
              showImportSheet(context);
            },
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('从相册导入'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: () {
              importer.pickAndImport('file');
              showImportSheet(context);
            },
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('从文件导入'),
          ),
        ),
        const SizedBox(height: 20),
        Text('学习小技巧：播放时点「AB」可以反复播放一段内容。',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
      ]),
    );
  }
}
