import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'import_sheet.dart';
import 'player_page.dart';

enum _Sort { added, name, size, duration }

enum _Filter { all, gallery, file, favorite }

/// 媒体库：搜索、排序、筛选、收藏、改名、删除、多选连续播放。
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String _q = '';
  _Sort _sort = _Sort.added;
  _Filter _filter = _Filter.all;
  final Set<String> _selected = {};
  final _search = TextEditingController();

  bool get _selecting => _selected.isNotEmpty;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MediaItem> _visible() {
    var list = store.items.where((it) {
      switch (_filter) {
        case _Filter.gallery:
          if (it.source != 'gallery') return false;
        case _Filter.file:
          if (it.source == 'gallery') return false;
        case _Filter.favorite:
          if (!it.favorite) return false;
        case _Filter.all:
          break;
      }
      if (_q.isEmpty) return true;
      return it.name.toLowerCase().contains(_q.toLowerCase()) || it.origName.toLowerCase().contains(_q.toLowerCase());
    }).toList();
    switch (_sort) {
      case _Sort.added:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case _Sort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
      case _Sort.size:
        list.sort((a, b) => b.size.compareTo(a.size));
      case _Sort.duration:
        list.sort((a, b) => b.durationMs.compareTo(a.durationMs));
    }
    return list;
  }

  Future<void> _rename(MediaItem it) async {
    final c = TextEditingController(text: it.name);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改显示名称'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(helperText: '只修改 App 内显示的名称，不改动原文件'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('保存')),
        ],
      ),
    );
    if (r != null) store.rename(it, r);
  }

  Future<void> _delete(List<MediaItem> list) async {
    final bytes = list.fold<int>(0, (s, e) => s + (e.size > 0 ? e.size : 0));
    final ok = await confirmDialog(
      context,
      title: list.length == 1 ? '删除这个视频？' : '删除 ${list.length} 个视频？',
      message: '将删除 App 内的副本，释放约 ${fmtSize(bytes)}，观看进度和字幕绑定也会一并删除。\n\n不会删除相册或文件中的原视频。',
      ok: '删除',
      danger: true,
    );
    if (!ok) return;
    for (final it in list) {
      await store.deleteItem(it);
    }
    setState(() => _selected.clear());
  }

  void _info(MediaItem it) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 72, child: Text(k, style: TextStyle(color: scheme.onSurfaceVariant))),
            Expanded(child: SelectableText(v)),
          ]),
        );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('文件信息'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          row('名称', it.name),
          row('原文件名', it.origName.isEmpty ? '—' : it.origName),
          row('大小', fmtSize(it.size)),
          row('时长', it.durationMs > 0 ? fmtMs(it.durationMs) : '未知'),
          row('分辨率', it.width > 0 ? '${it.width} × ${it.height}' : '未知'),
          row('来源', it.sourceLabel),
          row('导入时间', fmtDate(it.addedAt)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
      ),
    );
  }

  void _toggleSelect(MediaItem it) {
    setState(() {
      if (!_selected.remove(it.id)) _selected.add(it.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        _selected.removeWhere((id) => store.byId(id) == null);
        final list = _visible();
        return PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(() => _selected.clear());
          },
          child: Scaffold(
            appBar: _selecting
                ? AppBar(
                    leading: IconButton(
                        tooltip: '取消选择',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _selected.clear())),
                    title: Text('已选 ${_selected.length} 个'),
                    actions: [
                      IconButton(
                        tooltip: '全选',
                        icon: const Icon(Icons.select_all_rounded),
                        onPressed: () => setState(() => _selected.addAll(list.map((e) => e.id))),
                      ),
                      IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _delete(_selected.map((id) => store.byId(id)!).toList()),
                      ),
                    ],
                  )
                : AppBar(
                    title: const Text('媒体库'),
                    actions: [
                      PopupMenuButton<_Sort>(
                        tooltip: '排序',
                        icon: const Icon(Icons.sort_rounded),
                        initialValue: _sort,
                        onSelected: (v) => setState(() => _sort = v),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: _Sort.added, child: Text('按添加时间')),
                          PopupMenuItem(value: _Sort.name, child: Text('按名称')),
                          PopupMenuItem(value: _Sort.size, child: Text('按大小')),
                          PopupMenuItem(value: _Sort.duration, child: Text('按时长')),
                        ],
                      ),
                      IconButton(
                          tooltip: '导入视频',
                          icon: const Icon(Icons.add_rounded),
                          onPressed: () => showImportSheet(context)),
                    ],
                  ),
            floatingActionButton: _selecting
                ? FloatingActionButton.extended(
                    onPressed: () {
                      final ids = list.where((e) => _selected.contains(e.id)).map((e) => e.id).toList();
                      setState(() => _selected.clear());
                      PlayerPage.open(context, ids);
                    },
                    icon: const Icon(Icons.playlist_play_rounded),
                    label: const Text('连续播放'),
                  )
                : null,
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _q = v.trim()),
                  decoration: InputDecoration(
                    hintText: '搜索名称',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _q.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() {
                              _search.clear();
                              _q = '';
                            })),
                    filled: true,
                    fillColor: scheme.surfaceContainer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final f in _Filter.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(switch (f) {
                            _Filter.all => '全部',
                            _Filter.gallery => '相册导入',
                            _Filter.file => '文件导入',
                            _Filter.favorite => '收藏',
                          }),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? _Empty(hasAny: store.items.isNotEmpty)
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: list.length,
                        itemBuilder: (context, i) => _tile(list[i], list),
                      ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _tile(MediaItem it, List<MediaItem> list) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selected.contains(it.id);
    final rec = store.recOrNull(it.id);
    String sub = '${fmtSize(it.size)} · ${it.sourceLabel}';
    if (rec != null && !rec.finished && rec.positionMs > 0) sub = '看到 ${fmtMs(rec.positionMs)} · $sub';
    return Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: () => _selecting ? _toggleSelect(it) : PlayerPage.open(context, [it.id]),
        onLongPress: () => _toggleSelect(it),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(children: [
            SizedBox(width: 128, child: Thumb(item: it, radius: 8)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.3)),
                const SizedBox(height: 4),
                Text(sub, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ]),
            ),
            if (_selecting)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: selected ? scheme.secondary : scheme.outline),
              )
            else
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (v) {
                  switch (v) {
                    case 'fav':
                      store.toggleFavorite(it);
                    case 'rename':
                      _rename(it);
                    case 'info':
                      _info(it);
                    case 'select':
                      _toggleSelect(it);
                    case 'delete':
                      _delete([it]);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'fav', child: Text(it.favorite ? '取消收藏' : '收藏')),
                  const PopupMenuItem(value: 'rename', child: Text('修改显示名称')),
                  const PopupMenuItem(value: 'select', child: Text('多选')),
                  const PopupMenuItem(value: 'info', child: Text('文件信息')),
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
          ]),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final bool hasAny;
  const _Empty({required this.hasAny});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(hasAny ? Icons.search_off_rounded : Icons.video_library_outlined, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(hasAny ? '没有符合条件的视频' : '媒体库还是空的',
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
          if (!hasAny) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => showImportSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('导入视频'),
            ),
          ],
        ]),
      ),
    );
  }
}
