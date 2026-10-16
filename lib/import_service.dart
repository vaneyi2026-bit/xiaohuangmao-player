import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'native.dart';
import 'store.dart';
import 'util.dart';

enum TaskState { queued, copying, done, failed, cancelled, skipped }

class ImportTask {
  final String id = newId();
  final String uri;
  final String source;
  final bool isSubtitle;
  String name;
  final String origName;
  final int size;
  final String ext;
  int copied = 0;
  TaskState state = TaskState.queued;
  String? error;
  String? mediaId;
  String? subPath;
  bool paired = false;

  ImportTask({
    required this.uri,
    required this.source,
    required this.isSubtitle,
    required this.name,
    required this.origName,
    required this.size,
    required this.ext,
  });

  bool get active => state == TaskState.queued || state == TaskState.copying;
  double? get progress => size > 0 ? (copied / size).clamp(0.0, 1.0) : null;

  String get statusText => switch (state) {
        TaskState.queued => '等待中',
        TaskState.copying => copied == 0
            ? (source == 'gallery' ? '正在从相册获取…' : '正在获取文件…')
            : size > 0
                ? '正在复制 ${fmtSize(copied)} / ${fmtSize(size)}'
                : '正在复制 ${fmtSize(copied)}',
        TaskState.done => isSubtitle ? (paired ? '字幕已绑定' : '字幕未匹配到同名视频') : '导入完成',
        TaskState.failed => error ?? '导入失败',
        TaskState.cancelled => '已取消',
        TaskState.skipped => '已跳过（重复）',
      };
}

/// 导入队列：按顺序复制到 App 内，显示进度，可取消、重试。
class ImportService extends ChangeNotifier {
  final List<ImportTask> tasks = [];
  bool _running = false;
  StreamSubscription? _sub;

  /// 发现疑似重复时询问：返回 true 表示保留两份。
  Future<bool> Function(String name)? askDuplicate;
  void Function(String msg)? toast;

  bool get busy => tasks.any((t) => t.active);
  int get activeCount => tasks.where((t) => t.active).length;
  int get doneCount => tasks.where((t) => t.state == TaskState.done && !t.isSubtitle).length;

  void init() {
    _sub ??= Native.events.listen((e) {
      if (e['type'] != 'progress') return;
      final id = e['taskId'] as String?;
      for (final t in tasks) {
        if (t.id == id) {
          t.copied = (e['copied'] as num?)?.toInt() ?? t.copied;
          notifyListeners();
          break;
        }
      }
    });
  }

  Future<int> pickAndImport(String source) async {
    List<String> uris;
    try {
      uris = source == 'gallery' ? await Native.pickGallery() : await Native.pickFiles();
    } on PlatformException catch (e) {
      toast?.call('无法打开系统选择器：${e.message ?? ''}');
      return 0;
    }
    if (uris.isEmpty) {
      toast?.call('已取消');
      return 0;
    }
    return addUris(uris, source);
  }

  Future<int> addUris(List<String> uris, String source) async {
    int added = 0;
    for (final u in uris) {
      UriInfo info;
      try {
        info = await Native.queryUri(u);
      } catch (_) {
        info = const UriInfo(name: 'video', size: -1);
      }
      var ext = extOf(info.name);
      final isSub = subtitleExts.contains(ext);
      if (ext.isEmpty || (!videoExts.contains(ext) && !isSub)) {
        final m = extFromMime(info.mime);
        if (m.isNotEmpty) {
          ext = m;
        } else if (info.mime != null && info.mime!.startsWith('video/')) {
          ext = 'mp4';
        }
      }
      var display = stemOf(info.name);
      if (source == 'gallery' && info.dateTaken > 0) display = fmtDate(info.dateTaken);
      final t = ImportTask(
        uri: u,
        source: source,
        isSubtitle: isSub,
        name: display,
        origName: info.name,
        size: info.size,
        ext: ext,
      );
      if (!isSub && !videoExts.contains(ext)) {
        t.state = TaskState.failed;
        t.error = info.size == 0 ? '这是空文件（0 字节）' : '不是支持的视频文件';
      } else if (info.size == 0) {
        t.state = TaskState.failed;
        t.error = '这是空文件（0 字节）';
      } else {
        added++;
      }
      tasks.add(t);
    }
    notifyListeners();
    unawaited(_run());
    return added;
  }

  void cancel(ImportTask t) {
    if (t.state == TaskState.queued) {
      t.state = TaskState.cancelled;
      notifyListeners();
    } else if (t.state == TaskState.copying) {
      Native.cancelCopy(t.id);
    }
  }

  void retry(ImportTask t) {
    if (t.state == TaskState.failed || t.state == TaskState.cancelled) {
      if (!t.isSubtitle && !videoExts.contains(t.ext)) return;
      t.state = TaskState.queued;
      t.error = null;
      t.copied = 0;
      notifyListeners();
      unawaited(_run());
    }
  }

  void remove(ImportTask t) {
    if (t.active) return;
    tasks.remove(t);
    notifyListeners();
  }

  void clearFinished() {
    tasks.removeWhere((t) => !t.active);
    notifyListeners();
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final i = tasks.indexWhere((t) => t.state == TaskState.queued);
        if (i < 0) break;
        await _process(tasks[i]);
        notifyListeners();
      }
      _pairSubtitles();
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<void> _process(ImportTask t) async {
    // 疑似重复：文件名＋大小
    if (!t.isSubtitle) {
      final dup = store.findDuplicate(t.origName, t.size);
      if (dup != null && askDuplicate != null) {
        final keep = await askDuplicate!(t.origName);
        if (!keep) {
          t.state = TaskState.skipped;
          return;
        }
      }
      // 空间检查：文件大小 + 100 MB 预留
      if (t.size > 0) {
        final free = await Native.freeSpace();
        if (free < t.size + 100 * 1024 * 1024) {
          t.state = TaskState.failed;
          t.error = '剩余空间不足，无法完成导入';
          return;
        }
      }
    }
    t.state = TaskState.copying;
    t.copied = 0;
    notifyListeners();
    final tmp = '${store.tmpDir}/${t.id}.part';
    try {
      final n = await Native.copyUri(t.id, t.uri, tmp);
      t.copied = n;
      if (n == 0) {
        await _deleteQuiet(tmp);
        t.state = TaskState.failed;
        t.error = '这是空文件（0 字节）';
        return;
      }
      if (t.isSubtitle) {
        final dest = '${store.subsDir}/${t.id}.${t.ext}';
        await File(tmp).rename(dest);
        t.subPath = dest;
        t.state = TaskState.done;
        return;
      }
      final id = newId();
      final fileName = '$id.${t.ext.isEmpty ? 'mp4' : t.ext}';
      await File(tmp).rename('${store.mediaDir}/$fileName');
      final item = MediaItem(
        id: id,
        name: t.name,
        file: fileName,
        source: t.source,
        origName: t.origName,
        size: t.size > 0 ? t.size : n,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      );
      store.addItem(item);
      t.mediaId = id;
      t.state = TaskState.done;
      notifyListeners();
      await store.probeNow(item);
    } on PlatformException catch (e) {
      await _deleteQuiet(tmp);
      if (e.code == 'cancelled') {
        t.state = TaskState.cancelled;
      } else {
        t.state = TaskState.failed;
        final msg = e.message ?? '';
        t.error = msg.contains('NO_SPACE') || msg.contains('ENOSPC')
            ? '剩余空间不足，无法完成导入'
            : '无法读取该文件，请先保存到相册或文件再导入';
      }
    } catch (e) {
      await _deleteQuiet(tmp);
      t.state = TaskState.failed;
      t.error = '导入失败：$e';
    }
  }

  /// 与视频一起选中的同名字幕，自动绑定到对应视频。
  void _pairSubtitles() {
    final videos = tasks.where((t) => !t.isSubtitle && t.state == TaskState.done && t.mediaId != null).toList();
    final names = <String>[];
    for (final s in tasks.where((t) => t.isSubtitle && t.state == TaskState.done && !t.paired && t.subPath != null)) {
      var stem = stemOf(s.origName).toLowerCase();
      ImportTask? match;
      for (int k = 0; k < 2 && match == null; k++) {
        for (final v in videos) {
          if (stemOf(v.origName).toLowerCase() == stem) {
            match = v;
            break;
          }
        }
        stem = stemOf(stem); // 兼容 “视频名.zh.srt”
      }
      s.paired = true;
      if (match == null) {
        _deleteQuiet(s.subPath!);
        s.error = '未找到同名视频';
        continue;
      }
      final r = store.rec(match.mediaId!);
      final old = r.extSubPath;
      if (old != null && old != s.subPath) _deleteQuiet(old);
      r
        ..subMode = 'external'
        ..extSubPath = s.subPath
        ..extSubName = s.origName
        ..subEncoding = 'auto';
      names.add(s.origName);
    }
    if (names.isNotEmpty) {
      store.save();
      toast?.call('已为 ${names.length} 个视频绑定字幕');
    }
  }

  Future<void> _deleteQuiet(String p) async {
    try {
      final f = File(p);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

final importer = ImportService();
