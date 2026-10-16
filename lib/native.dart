import 'dart:async';

import 'package:flutter/services.dart';

/// 安卓原生能力的 Dart 封装（实现见 MainActivity.kt）。
class Native {
  static const _m = MethodChannel('xhm/native');
  static const _e = EventChannel('xhm/events');
  static Stream<Map<dynamic, dynamic>>? _events;

  /// 复制进度、外部分享、音频焦点丢失、耳机拔出等事件。
  static Stream<Map<dynamic, dynamic>> get events =>
      _events ??= _e.receiveBroadcastStream().map((e) => e as Map<dynamic, dynamic>);

  static Future<Map<String, String>> dirs() async {
    final r = await _m.invokeMapMethod<String, String>('dirs');
    return r ?? const {};
  }

  static Future<int> freeSpace() async => (await _m.invokeMethod<int>('freeSpace')) ?? 0;

  static Future<List<String>> pickGallery() async =>
      (await _m.invokeListMethod<String>('pickGallery')) ?? const [];

  static Future<List<String>> pickFiles() async =>
      (await _m.invokeListMethod<String>('pickFiles')) ?? const [];

  static Future<List<String>> pickSubtitle() async =>
      (await _m.invokeListMethod<String>('pickSubtitle')) ?? const [];

  static Future<UriInfo> queryUri(String uri) async {
    final r = await _m.invokeMapMethod<String, dynamic>('queryUri', {'uri': uri}) ?? const {};
    return UriInfo(
      name: (r['name'] as String?) ?? 'video',
      size: (r['size'] as num?)?.toInt() ?? -1,
      mime: r['mime'] as String?,
      dateTaken: (r['dateTaken'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<int> copyUri(String taskId, String uri, String dest) async {
    final r = await _m.invokeMethod<int>('copyUri', {'taskId': taskId, 'uri': uri, 'dest': dest});
    return r ?? 0;
  }

  static Future<void> cancelCopy(String taskId) => _m.invokeMethod('cancelCopy', {'taskId': taskId});

  static Future<ProbeResult> probe(String path, String thumb) async {
    final r = await _m.invokeMapMethod<String, dynamic>('probe', {'path': path, 'thumb': thumb}) ?? const {};
    return ProbeResult(
      ok: r['ok'] == true,
      durationMs: (r['duration'] as num?)?.toInt() ?? 0,
      width: (r['width'] as num?)?.toInt() ?? 0,
      height: (r['height'] as num?)?.toInt() ?? 0,
      hasVideo: r['hasVideo'] == true,
      thumb: r['thumb'] == true,
    );
  }

  /// 读取字幕文本。encoding 为 auto 时自动识别 UTF-8 / UTF-16 / GB18030。
  static Future<({String text, String encoding})> readText(String path, String encoding) async {
    final r = await _m.invokeMapMethod<String, dynamic>('readText', {'path': path, 'encoding': encoding}) ?? const {};
    return (text: (r['text'] as String?) ?? '', encoding: (r['encoding'] as String?) ?? encoding);
  }

  static Future<List<Map<dynamic, dynamic>>> takeShared() async {
    final r = await _m.invokeListMethod<Map<dynamic, dynamic>>('takeShared');
    return r ?? const [];
  }

  static Future<double> getBrightness() async => (await _m.invokeMethod<double>('getBrightness')) ?? 0.5;
  static Future<void> setBrightness(double v) => _m.invokeMethod('setBrightness', {'value': v});
  static Future<void> resetBrightness() => _m.invokeMethod('resetBrightness');
  static Future<double> getVolume() async => (await _m.invokeMethod<double>('getVolume')) ?? 0.5;
  static Future<void> setVolume(double v) => _m.invokeMethod('setVolume', {'value': v});
  static Future<bool> requestFocus() async => (await _m.invokeMethod<bool>('requestFocus')) ?? false;
  static Future<void> abandonFocus() => _m.invokeMethod('abandonFocus');
}

class UriInfo {
  final String name;
  final int size;
  final String? mime;
  final int dateTaken;
  const UriInfo({required this.name, required this.size, this.mime, this.dateTaken = 0});
}

class ProbeResult {
  final bool ok;
  final int durationMs;
  final int width;
  final int height;
  final bool hasVideo;
  final bool thumb;
  const ProbeResult({
    required this.ok,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.hasVideo,
    required this.thumb,
  });
}
