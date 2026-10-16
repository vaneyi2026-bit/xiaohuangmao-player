import 'package:flutter/material.dart';

import '../import_service.dart';
import '../theme.dart';

Future<void> showImportSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const ImportSheet(),
  );
}

/// 导入面板：选择来源（相册 / 文件），查看导入队列。
class ImportSheet extends StatelessWidget {
  const ImportSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: importer,
      builder: (context, _) {
        final tasks = importer.tasks.reversed.toList();
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Row(children: [
                const Text('导入视频', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (tasks.any((t) => !t.active))
                  TextButton(onPressed: importer.clearFinished, child: const Text('清除已结束')),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text(
                '导入会把视频复制一份到 App 内，会占用手机空间；删除相册或文件里的原视频后，副本仍可播放。',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                Expanded(
                  child: _SourceButton(
                    icon: Icons.photo_library_outlined,
                    title: '从相册',
                    subtitle: '手机拍的、保存的视频',
                    onTap: () => importer.pickAndImport('gallery'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SourceButton(
                    icon: Icons.folder_open_outlined,
                    title: '从文件',
                    subtitle: '下载的视频，可连同字幕一起选',
                    onTap: () => importer.pickAndImport('file'),
                  ),
                ),
              ]),
            ),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Text('同名的 .srt / .ass 字幕和视频一起选中，会自动绑定。',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
                  itemBuilder: (context, i) => _TaskTile(task: tasks[i]),
                ),
              ),
          ]),
        );
      },
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SourceButton({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: kInk),
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer.withValues(alpha: 0.75))),
          ]),
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final ImportTask task;
  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = task;
    final failed = t.state == TaskState.failed;
    IconData icon = t.isSubtitle ? Icons.subtitles_outlined : Icons.movie_outlined;
    if (t.state == TaskState.done) icon = Icons.check_circle_rounded;
    if (failed) icon = Icons.error_outline_rounded;
    return ListTile(
      leading: Icon(icon,
          color: failed
              ? scheme.error
              : t.state == TaskState.done
                  ? scheme.secondary
                  : scheme.onSurfaceVariant),
      title: Text(t.isSubtitle ? t.origName : t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.statusText,
            style: TextStyle(fontSize: 12, color: failed ? scheme.error : scheme.onSurfaceVariant)),
        if (t.state == TaskState.copying)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(value: t.copied == 0 ? null : t.progress, minHeight: 3),
          ),
      ]),
      trailing: t.active
          ? IconButton(tooltip: '取消', icon: const Icon(Icons.close_rounded), onPressed: () => importer.cancel(t))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (failed || t.state == TaskState.cancelled)
                IconButton(tooltip: '重试', icon: const Icon(Icons.refresh_rounded), onPressed: () => importer.retry(t)),
              IconButton(tooltip: '移除', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => importer.remove(t)),
            ]),
    );
  }
}
