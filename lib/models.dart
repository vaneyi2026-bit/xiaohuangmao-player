int _i(dynamic v, [int d = 0]) => (v as num?)?.toInt() ?? d;

/// 媒体库中的一个视频（App 内副本）。
class MediaItem {
  final String id;
  String name;
  final String file; // media 目录下的文件名
  final String source; // gallery / file / share
  final String origName;
  final int size;
  int durationMs;
  int width;
  int height;
  final int addedAt;
  bool favorite;

  MediaItem({
    required this.id,
    required this.name,
    required this.file,
    required this.source,
    required this.origName,
    required this.size,
    this.durationMs = 0,
    this.width = 0,
    this.height = 0,
    required this.addedAt,
    this.favorite = false,
  });

  String get sourceLabel => switch (source) {
        'gallery' => '相册导入',
        'share' => '外部打开',
        _ => '文件导入',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'file': file,
        'source': source,
        'origName': origName,
        'size': size,
        'durationMs': durationMs,
        'width': width,
        'height': height,
        'addedAt': addedAt,
        'favorite': favorite,
      };

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '未命名',
        file: j['file'] as String,
        source: (j['source'] as String?) ?? 'file',
        origName: (j['origName'] as String?) ?? '',
        size: _i(j['size'], -1),
        durationMs: _i(j['durationMs']),
        width: _i(j['width']),
        height: _i(j['height']),
        addedAt: _i(j['addedAt']),
        favorite: j['favorite'] == true,
      );
}

/// 按视频保存的观看状态：进度、音轨、字幕、AB 点。
class WatchRecord {
  int positionMs = 0;
  bool finished = false;
  int lastWatchedAt = 0;
  String? audioId;
  String subMode = 'auto'; // auto / off / internal / external
  String? subId;
  String? extSubPath;
  String? extSubName;
  String subEncoding = 'auto';
  int subDelayMs = 0;
  int? abA;
  int? abB;

  WatchRecord();

  Map<String, dynamic> toJson() => {
        'positionMs': positionMs,
        'finished': finished,
        'lastWatchedAt': lastWatchedAt,
        'audioId': audioId,
        'subMode': subMode,
        'subId': subId,
        'extSubPath': extSubPath,
        'extSubName': extSubName,
        'subEncoding': subEncoding,
        'subDelayMs': subDelayMs,
        'abA': abA,
        'abB': abB,
      };

  factory WatchRecord.fromJson(Map<String, dynamic> j) => WatchRecord()
    ..positionMs = _i(j['positionMs'])
    ..finished = j['finished'] == true
    ..lastWatchedAt = _i(j['lastWatchedAt'])
    ..audioId = j['audioId'] as String?
    ..subMode = (j['subMode'] as String?) ?? 'auto'
    ..subId = j['subId'] as String?
    ..extSubPath = j['extSubPath'] as String?
    ..extSubName = j['extSubName'] as String?
    ..subEncoding = (j['subEncoding'] as String?) ?? 'auto'
    ..subDelayMs = _i(j['subDelayMs'])
    ..abA = (j['abA'] as num?)?.toInt()
    ..abB = (j['abB'] as num?)?.toInt();
}

/// 全局偏好。
class Prefs {
  int themeMode = 0; // 0 跟随系统 1 浅色 2 深色
  bool rememberSpeed = false;
  double lastSpeed = 1.0;
  int subSize = 1; // 0 小 1 中 2 大
  int defaultFit = 0; // 0 适应 1 填充 2 原始大小
  bool gestureHintShown = false;

  Prefs();

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode,
        'rememberSpeed': rememberSpeed,
        'lastSpeed': lastSpeed,
        'subSize': subSize,
        'defaultFit': defaultFit,
        'gestureHintShown': gestureHintShown,
      };

  factory Prefs.fromJson(Map<String, dynamic> j) => Prefs()
    ..themeMode = _i(j['themeMode'])
    ..rememberSpeed = j['rememberSpeed'] == true
    ..lastSpeed = (j['lastSpeed'] as num?)?.toDouble() ?? 1.0
    ..subSize = _i(j['subSize'], 1)
    ..defaultFit = _i(j['defaultFit'])
    ..gestureHintShown = j['gestureHintShown'] == true;
}
