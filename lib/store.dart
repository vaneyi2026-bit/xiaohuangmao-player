import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'native.dart';

/// 媒体库、观看记录与偏好。数据保存在 App 私有目录的 library.json。
class AppStore extends ChangeNotifier {
  late String filesDir;
  late String cacheDir;

  String get mediaDir => '$filesDir/media';
  String get subsDir => '$filesDir/subs';
  String get tmpDir => '$filesDir/import_tmp';
  String get thumbsDir => '$cacheDir/thumbs';
  String get _dbPath => '$filesDir/library.json';

  final List<MediaItem> items = [];
  final Map<String, MediaItem> _byId = {};
  final Map<String, WatchRecord> records = {};
  Prefs prefs = Prefs();

  /// 主题单独通知，避免每次保存进度都重建整个 App。
  final themeMode = ValueNotifier<int>(0);

  /// 缩略图版本号，用于刷新图片缓存。
  final Map<String, int> thumbGen = {};
  final Set<String> _probed = {};
  final List<String> _probeQueue = [];
  bool _probing = false;

  Timer? _saveTimer;
  bool _writing = false;
  bool _dirty = false;

  Future<void> init() async {
    final d = await Native.dirs();
    filesDir = d['files']!;
    cacheDir = d['cache']!;
    for (final p in [mediaDir, subsDir, tmpDir, thumbsDir]) {
      await Directory(p).create(recursive: true);
    }
    // 清理上次中断留下的临时文件
    try {
      await for (final f in Directory(tmpDir).list()) {
        await f.delete(recursive: true);
      }
    } catch (_) {}
    final f = File(_dbPath);
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        for (final e in (j['items'] as List? ?? const [])) {
          final it = MediaItem.fromJson(Map<String, dynamic>.from(e as Map));
          items.add(it);
          _byId[it.id] = it;
        }
        final recs = Map<String, dynamic>.from(j['records'] as Map? ?? const {});
        recs.forEach((k, v) => records[k] = WatchRecord.fromJson(Map<String, dynamic>.from(v as Map)));
        if (j['prefs'] is Map) prefs = Prefs.fromJson(Map<String, dynamic>.from(j['prefs'] as Map));
        themeMode.value = prefs.themeMode;
      } catch (e) {
        debugPrint('library.json 读取失败: $e');
        // 保留损坏的文件，避免覆盖
        try {
          await f.copy('$_dbPath.broken-${DateTime.now().millisecondsSinceEpoch}');
        } catch (_) {}
      }
    }
    for (final it in items) {
      if (!File(thumbPath(it)).existsSync() || it.durationMs == 0) _probeQueue.add(it.id);
    }
    _runProbe();
  }

  MediaItem? byId(String id) => _byId[id];
  String mediaPath(MediaItem it) => '$mediaDir/${it.file}';
  String thumbPath(MediaItem it) => '$thumbsDir/${it.id}.jpg';
  bool hasThumb(MediaItem it) => File(thumbPath(it)).existsSync();
  WatchRecord rec(String id) => records.putIfAbsent(id, () => WatchRecord());
  WatchRecord? recOrNull(String id) => records[id];

  void addItem(MediaItem it) {
    items.add(it);
    _byId[it.id] = it;
    save();
  }

  /// 后台逐项生成缩略图与时长，不阻塞列表。
  void requestProbe(MediaItem it) {
    if (_probed.contains(it.id) || _probeQueue.contains(it.id)) return;
    _probeQueue.add(it.id);
    _runProbe();
  }

  Future<ProbeResult?> probeNow(MediaItem it) async {
    _probed.add(it.id);
    try {
      final r = await Native.probe(mediaPath(it), thumbPath(it));
      if (r.ok) {
        if (r.durationMs > 0) it.durationMs = r.durationMs;
        if (r.width > 0 && r.height > 0) {
          it.width = r.width;
          it.height = r.height;
        }
      }
      thumbGen[it.id] = (thumbGen[it.id] ?? 0) + 1;
      save();
      return r;
    } catch (_) {
      return null;
    }
  }

  Future<void> _runProbe() async {
    if (_probing) return;
    _probing = true;
    while (_probeQueue.isNotEmpty) {
      final id = _probeQueue.removeAt(0);
      final it = _byId[id];
      if (it == null || _probed.contains(id)) continue;
      if (!File(mediaPath(it)).existsSync()) {
        _probed.add(id);
        continue;
      }
      await probeNow(it);
    }
    _probing = false;
  }

  /// 继续观看：最近一个未看完且进度不少于 5 秒的视频。
  MediaItem? get continueItem {
    MediaItem? best;
    int bestAt = 0;
    records.forEach((id, r) {
      final it = _byId[id];
      if (it == null || r.finished || r.positionMs < 5000 || r.lastWatchedAt <= bestAt) return;
      best = it;
      bestAt = r.lastWatchedAt;
    });
    return best;
  }

  /// 最近观看，最多显示 200 条（仅为列表显示上限，不影响进度）。
  List<MediaItem> get recentWatched {
    final list = items.where((it) => (records[it.id]?.lastWatchedAt ?? 0) > 0).toList()
      ..sort((a, b) => records[b.id]!.lastWatchedAt.compareTo(records[a.id]!.lastWatchedAt));
    return list.length > 200 ? list.sublist(0, 200) : list;
  }

  List<MediaItem> get recentAdded => [...items]..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  List<MediaItem> get favorites => recentAdded.where((e) => e.favorite).toList();

  MediaItem? findDuplicate(String origName, int size) {
    if (size <= 0) return null;
    for (final it in items) {
      if (it.size == size && it.origName == origName) return it;
    }
    return null;
  }

  void toggleFavorite(MediaItem it) {
    it.favorite = !it.favorite;
    save();
  }

  void rename(MediaItem it, String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    it.name = n;
    save();
  }

  Future<void> deleteItem(MediaItem it) async {
    items.remove(it);
    _byId.remove(it.id);
    final r = records.remove(it.id);
    for (final p in [mediaPath(it), thumbPath(it), r?.extSubPath]) {
      if (p == null) continue;
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    save();
  }

  Future<void> deleteAll() async {
    for (final it in [...items]) {
      await deleteItem(it);
    }
    for (final p in [mediaDir, subsDir, thumbsDir]) {
      try {
        await Directory(p).delete(recursive: true);
      } catch (_) {}
      await Directory(p).create(recursive: true);
    }
    records.clear();
    save();
  }

  /// 清空观看记录：清进度、最后观看时间和 AB 点；保留视频、收藏和字幕绑定。
  void clearHistory() {
    for (final r in records.values) {
      r.positionMs = 0;
      r.finished = false;
      r.lastWatchedAt = 0;
      r.abA = null;
      r.abB = null;
    }
    save();
  }

  /// 清缓存：只清缩略图和无效临时文件。
  Future<void> clearCache({bool importing = false}) async {
    try {
      await Directory(thumbsDir).delete(recursive: true);
    } catch (_) {}
    await Directory(thumbsDir).create(recursive: true);
    if (!importing) {
      try {
        await for (final f in Directory(tmpDir).list()) {
          await f.delete(recursive: true);
        }
      } catch (_) {}
    }
    _probed.clear();
    for (final it in items) {
      thumbGen[it.id] = (thumbGen[it.id] ?? 0) + 1;
      _probeQueue.add(it.id);
    }
    notifyListeners();
    _runProbe();
  }

  void resetPrefs() {
    final hint = prefs.gestureHintShown;
    prefs = Prefs()..gestureHintShown = hint;
    themeMode.value = prefs.themeMode;
    save();
  }

  int get mediaBytes => items.fold(0, (s, e) => s + (e.size > 0 ? e.size : 0));

  Future<int> dirBytes(String path) async {
    int total = 0;
    try {
      await for (final f in Directory(path).list(recursive: true)) {
        if (f is File) total += await f.length();
      }
    } catch (_) {}
    return total;
  }

  /// 通知界面并稍后写盘。
  void save() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _write);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    await _write();
  }

  Future<void> _write() async {
    if (_writing) {
      _dirty = true;
      return;
    }
    _writing = true;
    try {
      final data = jsonEncode({
        'version': 1,
        'items': items.map((e) => e.toJson()).toList(),
        'records': records.map((k, v) => MapEntry(k, v.toJson())),
        'prefs': prefs.toJson(),
      });
      final tmp = File('$_dbPath.tmp');
      await tmp.writeAsString(data, flush: true);
      await tmp.rename(_dbPath);
    } catch (e) {
      debugPrint('保存失败: $e');
    } finally {
      _writing = false;
      if (_dirty) {
        _dirty = false;
        unawaited(_write());
      }
    }
  }
}

final store = AppStore();
