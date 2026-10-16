import 'dart:math';

String fmtDur(Duration d) {
  final neg = d.isNegative;
  d = d.abs();
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  final t = h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  return neg ? '-$t' : t;
}

String fmtMs(int ms) => fmtDur(Duration(milliseconds: ms));

String fmtSize(int b) {
  if (b < 0) return '未知大小';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double v = b.toDouble();
  int i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  if (i == 0) return '$b B';
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

String fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

String extOf(String name) {
  final i = name.lastIndexOf('.');
  if (i < 0 || i == name.length - 1) return '';
  return name.substring(i + 1).toLowerCase();
}

String stemOf(String name) {
  final i = name.lastIndexOf('.');
  return i <= 0 ? name : name.substring(0, i);
}

const videoExts = {
  'mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', 'flv', 'wmv', 'ts', 'm2ts', 'mts',
  '3gp', '3g2', 'mpg', 'mpeg', 'ogv', 'rmvb', 'rm', 'vob', 'f4v', 'asf', 'divx',
};

const subtitleExts = {'srt', 'ass', 'ssa', 'vtt'};

String extFromMime(String? mime) {
  switch (mime) {
    case 'video/mp4':
      return 'mp4';
    case 'video/quicktime':
      return 'mov';
    case 'video/x-matroska':
      return 'mkv';
    case 'video/webm':
      return 'webm';
    case 'video/3gpp':
      return '3gp';
    case 'video/x-msvideo':
      return 'avi';
    case 'video/x-flv':
      return 'flv';
    case 'video/mp2t':
      return 'ts';
    default:
      return '';
  }
}

final _rand = Random();
String newId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
    _rand.nextInt(1 << 20).toRadixString(36);
