import 'package:flutter/material.dart';

import '../store.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'player_page.dart';

/// 最近观看（最多显示 200 条）。
class RecentPage extends StatelessWidget {
  const RecentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('最近观看')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final list = store.recentWatched;
          if (list.isEmpty) {
            return Center(child: Text('还没有观看记录', style: TextStyle(color: scheme.onSurfaceVariant)));
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final it = list[i];
              final r = store.rec(it.id);
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: SizedBox(width: 112, child: MediaThumb(item: it, radius: 8)),
                title: Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  r.finished ? '已看完 · ${fmtDate(r.lastWatchedAt)}' : '看到 ${fmtMs(r.positionMs)} · ${fmtDate(r.lastWatchedAt)}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                onTap: () => PlayerPage.open(context, [it.id]),
              );
            },
          );
        },
      ),
    );
  }
}
