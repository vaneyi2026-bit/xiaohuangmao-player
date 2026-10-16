import 'dart:async';

import 'package:flutter/material.dart';

import '../import_service.dart';
import '../native.dart';
import '../store.dart';
import '../util.dart';
import '../widgets/common.dart';

const appVersion = '0.1.0';

/// 设置：主题、播放偏好、存储管理、帮助与关于。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int? _thumbBytes;
  int? _free;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _refresh();
    store.addListener(_onStore);
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    _debounce?.cancel();
    super.dispose();
  }

  void _onStore() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _refresh);
  }

  Future<void> _refresh() async {
    final t = await store.dirBytes(store.thumbsDir);
    final f = await Native.freeSpace();
    if (mounted) {
      setState(() {
        _thumbBytes = t;
        _free = f;
      });
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.prefs;
        return Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            const _Group('外观'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('跟随系统')),
                  ButtonSegment(value: 1, label: Text('浅色')),
                  ButtonSegment(value: 2, label: Text('深色')),
                ],
                selected: {p.themeMode},
                onSelectionChanged: (s) {
                  p.themeMode = s.first;
                  store.themeMode.value = s.first;
                  store.save();
                },
              ),
            ),
            const _Group('播放'),
            SwitchListTile(
              title: const Text('记住上次倍速'),
              subtitle: const Text('关闭时每次都从 1 倍速开始'),
              value: p.rememberSpeed,
              onChanged: (v) {
                p.rememberSpeed = v;
                store.save();
              },
            ),
            _SegTile<int>(
              title: '默认画面比例',
              value: p.defaultFit,
              options: const {0: '适应', 1: '填充', 2: '原始大小'},
              onChanged: (v) {
                p.defaultFit = v;
                store.save();
              },
            ),
            _SegTile<int>(
              title: '字幕字号',
              value: p.subSize,
              options: const {0: '小', 1: '中', 2: '大'},
              onChanged: (v) {
                p.subSize = v;
                store.save();
              },
            ),
            const _Group('存储'),
            ListTile(
              title: const Text('视频副本'),
              subtitle: Text('${store.items.length} 个视频'),
              trailing: Text(fmtSize(store.mediaBytes)),
            ),
            ListTile(
              title: const Text('缩略图缓存'),
              trailing: Text(_thumbBytes == null ? '…' : fmtSize(_thumbBytes!)),
            ),
            ListTile(
              title: const Text('手机可用空间'),
              trailing: Text(_free == null ? '…' : fmtSize(_free!)),
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('清理缓存'),
              subtitle: const Text('只清缩略图和无效临时文件，不删除视频'),
              onTap: () async {
                await store.clearCache(importing: importer.busy);
                await _refresh();
                _toast('缓存已清理，缩略图会在后台重新生成');
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_toggle_off_rounded),
              title: const Text('清空观看记录'),
              subtitle: const Text('清除进度、最近观看和 AB 点；保留视频、收藏和字幕'),
              onTap: () async {
                final ok = await confirmDialog(context,
                    title: '清空观看记录？',
                    message: '所有视频的观看进度、最近观看时间和 AB 循环点都会被清除。\n视频、收藏和字幕绑定会保留。',
                    ok: '清空',
                    danger: true);
                if (ok) {
                  store.clearHistory();
                  _toast('观看记录已清空');
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
              title: Text('删除全部视频', style: TextStyle(color: scheme.error)),
              subtitle: Text('释放 ${fmtSize(store.mediaBytes)}；不影响相册和文件里的原视频'),
              onTap: store.items.isEmpty
                  ? null
                  : () async {
                      final ok = await confirmDialog(context,
                          title: '删除全部 ${store.items.length} 个视频？',
                          message: '将删除 App 内所有视频副本、观看记录和字幕，此操作无法撤销。\n相册和文件里的原视频不受影响。',
                          ok: '全部删除',
                          danger: true);
                      if (ok) {
                        await store.deleteAll();
                        await _refresh();
                        _toast('已删除全部视频');
                      }
                    },
            ),
            const _Group('其他'),
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: const Text('恢复默认设置'),
              onTap: () async {
                final ok = await confirmDialog(context, title: '恢复默认设置？', message: '主题、倍速记忆、画面比例和字幕字号会恢复默认。');
                if (ok) store.resetPrefs();
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline_rounded),
              title: const Text('帮助'),
              onTap: () => _help(context),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('关于与开源声明'),
              subtitle: const Text('小黄毛影音 $appVersion'),
              onTap: () => showLicensePage(
                context: context,
                applicationName: '小黄毛影音',
                applicationVersion: appVersion,
                applicationIcon: const Padding(padding: EdgeInsets.all(12), child: LogoMark(size: 56)),
                applicationLegalese:
                    '个人视频播放器，仅供自用及小范围分享。\n播放组件 media_kit（MIT），内含 libmpv、FFmpeg 等开源库，按其各自许可（LGPL 等）分发，源码可按需提供。\n本 App 不上传任何视频、文件名或观看记录。',
              ),
            ),
          ]),
        );
      },
    );
  }

  void _help(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('使用帮助'),
        content: const SingleChildScrollView(
          child: Text(
            '导入\n'
            '· 从相册或文件导入的视频会复制一份到 App 内，占用手机空间。\n'
            '· 同名的 .srt / .ass 字幕和视频一起从“文件”选中，会自动绑定。\n'
            '· 其他 App 里点“分享”或“用其他应用打开”，选小黄毛影音即可导入。\n\n'
            '播放手势\n'
            '· 单击：显示 / 隐藏控制\n'
            '· 双击左侧 / 右侧：后退 / 前进 10 秒；双击中间：暂停\n'
            '· 左右滑动：调整进度\n'
            '· 左半边上下滑：亮度；右半边上下滑：音量\n'
            '· 长按：临时 2 倍速，松手恢复\n\n'
            'AB 循环（反复听一段）\n'
            '· 在片段开头点“AB”设 A 点，到结尾再点一次设 B 点，即开始循环。\n'
            '· 循环中再点“AB”关闭；在面板里可微调 A、B 点。\n\n'
            '字幕乱码\n'
            '· 在播放面板“字幕编码”里切换 GBK/GB18030、Big5 等。\n\n'
            '注意\n'
            '· 卸载 App 会删除 App 内的所有视频副本和记录，相册和文件里的原视频不受影响。',
            style: TextStyle(height: 1.55),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了'))],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  const _Group(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
        child: Text(title,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.secondary)),
      );
}

class _SegTile<T> extends StatelessWidget {
  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  const _SegTile({required this.title, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value))],
              selected: {value},
              onSelectionChanged: (s) => onChanged(s.first),
            ),
          ),
        ]),
      );
}
