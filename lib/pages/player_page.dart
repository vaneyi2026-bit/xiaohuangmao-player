import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models.dart';
import '../native.dart';
import '../store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/seek_bar.dart';

const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
const _fits = [BoxFit.contain, BoxFit.cover, BoxFit.none];
const _fitNames = ['适应', '填充', '原始大小'];
const _subSizes = [26.0, 32.0, 40.0];
const _encodings = {'auto': '自动识别', 'UTF-8': 'UTF-8', 'GB18030': 'GBK / GB18030', 'Big5': 'Big5（繁体）', 'UTF-16LE': 'UTF-16'};

/// 播放器：手势、倍速、AB 循环、字幕与音轨、进度记忆、连续播放。
class PlayerPage extends StatefulWidget {
  final List<String> queue;
  final int index;
  const PlayerPage({super.key, required this.queue, this.index = 0});

  static Future<void> open(BuildContext context, List<String> ids, {int index = 0}) {
    if (ids.isEmpty) return Future.value();
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerPage(queue: ids, index: index)));
  }

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late final Player player = Player(configuration: const PlayerConfiguration(title: '小黄毛影音'));
  late final VideoController controller = VideoController(player);
  final subs = <StreamSubscription>[];

  late int idx = widget.index;
  MediaItem? item;
  int _loadToken = 0;

  bool loading = true;
  String? error;
  String? errorDetail;
  bool showErrorDetail = false;
  bool ended = false;

  final posN = ValueNotifier(Duration.zero);
  final bufN = ValueNotifier(Duration.zero);
  Duration dur = Duration.zero;
  bool playing = false;
  bool buffering = false;
  double rate = 1.0;
  double? _rateBeforeLongPress;

  bool controlsVisible = true;
  bool locked = false;
  bool panelOpen = false;
  Timer? _hideTimer;

  late BoxFit fit = _fits[store.prefs.defaultFit.clamp(0, 2)];
  bool? manualLandscape;

  // 手势
  Offset? _dtPos;
  bool _hActive = false;
  double _hDx = 0;
  Duration _hBase = Duration.zero;
  Duration? seekPreview;
  bool _vActive = false;
  bool _vLeft = false;
  double _vBase = 0.5;
  double _vDy = 0;
  double _brightness = 0.5;
  double _volume = 0.5;
  int _lastVolStep = -1;

  // 提示
  IconData? hudIcon;
  String? hudText;
  Timer? _hudTimer;
  String? toastText;
  Timer? _toastTimer;
  Duration? resumeFrom;
  Timer? _resumeTimer;
  bool showGestureHint = false;

  // AB 循环
  Duration? abA;
  Duration? abB;
  bool abActive = false;

  // 字幕
  String? subEncodingUsed;

  Timer? _saveTimer;

  bool get _hasQueue => widget.queue.length > 1;

  void refresh(VoidCallback f) {
    if (mounted) setState(f);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    showGestureHint = !store.prefs.gestureHintShown;
    _setup();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(idx);
    });
    Native.getBrightness().then((v) => _brightness = v);
    Native.getVolume().then((v) => _volume = v);
  }

  NativePlayer? get _np {
    final p = player.platform;
    return p is NativePlayer ? p : null;
  }

  Future<void> _setProp(String k, String v) async {
    try {
      await _np?.setProperty(k, v);
    } catch (_) {}
  }

  void _setup() {
    _setProp('hr-seek', 'yes');
    subs.addAll([
      player.stream.position.listen((d) {
        if (seekPreview == null) posN.value = d;
      }),
      player.stream.buffer.listen((d) => bufN.value = d),
      player.stream.duration.listen((d) {
        if (mounted) setState(() => dur = d);
      }),
      player.stream.playing.listen((v) {
        if (!mounted) return;
        setState(() => playing = v);
        if (v) {
          Native.requestFocus();
          ended = false;
        } else {
          Native.abandonFocus();
          _saveProgress();
        }
        _scheduleHide();
      }),
      player.stream.buffering.listen((v) {
        if (mounted) setState(() => buffering = v);
      }),
      player.stream.completed.listen((v) {
        if (v) _onCompleted();
      }),
      player.stream.error.listen((e) {
        errorDetail = e;
        if (loading && mounted && dur == Duration.zero) {
          setState(() {
            error = '此视频暂不能播放';
            loading = false;
          });
        }
      }),
      Native.events.listen((e) {
        final t = e['type'];
        if (t == 'focusLoss' || t == 'noisy') {
          if (_rateBeforeLongPress != null) _endLongPress();
          player.pause();
        }
      }),
    ]);
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (playing) _saveProgress();
    });
  }

  // ---------------- 加载与进度 ----------------

  Future<void> _load(int i) async {
    final token = ++_loadToken;
    final it = store.byId(widget.queue[i]);
    setState(() {
      idx = i;
      item = it;
      loading = true;
      error = null;
      errorDetail = null;
      showErrorDetail = false;
      ended = false;
      dur = Duration.zero;
      abA = null;
      abB = null;
      abActive = false;
      subEncodingUsed = null;
      resumeFrom = null;
    });
    posN.value = Duration.zero;
    await _setProp('ab-loop-a', 'no');
    await _setProp('ab-loop-b', 'no');
    if (it == null || !File(store.mediaPath(it)).existsSync()) {
      await player.stop();
      if (!mounted) return;
      setState(() {
        loading = false;
        error = '视频文件不可用';
        errorDetail = 'App 内的副本已丢失，请重新导入。';
      });
      return;
    }
    _applyOrientation();
    final rec = store.rec(it.id);
    rate = store.prefs.rememberSpeed ? store.prefs.lastSpeed : 1.0;
    await player.open(Media(store.mediaPath(it)), play: false);
    await player.setRate(rate);
    var d = player.state.duration;
    if (d == Duration.zero) {
      try {
        d = await player.stream.duration.firstWhere((x) => x > Duration.zero).timeout(const Duration(seconds: 15));
      } catch (_) {}
    }
    if (!mounted || token != _loadToken) return;
    if (d == Duration.zero) {
      setState(() {
        loading = false;
        error ??= '此视频暂不能播放';
        errorDetail ??= '未能读取视频的时长或格式。';
      });
      return;
    }
    if (it.durationMs == 0) {
      it.durationMs = d.inMilliseconds;
      store.save();
    }
    await _restoreTracks(rec);
    if (!mounted || token != _loadToken) return;
    if (!rec.finished && rec.positionMs >= 5000 && rec.positionMs < d.inMilliseconds - 3000) {
      final from = Duration(milliseconds: rec.positionMs);
      await player.seek(from);
      posN.value = from;
      _showResume(from);
    }
    rec.finished = false;
    rec.lastWatchedAt = DateTime.now().millisecondsSinceEpoch;
    store.save();
    setState(() => loading = false);
    await player.play();
    _scheduleHide();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted || token != _loadToken || error != null) return;
      final videos = player.state.tracks.video.where((t) => t.id != 'auto' && t.id != 'no');
      if (videos.isEmpty && (player.state.width ?? 0) == 0) {
        player.pause();
        setState(() {
          error = '未找到可播放的视频画面';
          errorDetail = '这个文件里可能只有声音，或者画面编码暂不支持。';
        });
      }
    });
  }

  Future<void> _restoreTracks(WatchRecord rec) async {
    try {
      if (player.state.tracks.audio.length <= 2 && player.state.tracks.subtitle.length <= 2) {
        await player.stream.tracks
            .firstWhere((t) => t.audio.length > 2 || t.subtitle.length > 2)
            .timeout(const Duration(milliseconds: 1500));
      }
    } catch (_) {}
    final tracks = player.state.tracks;
    if (rec.audioId != null) {
      for (final a in tracks.audio) {
        if (a.id == rec.audioId) {
          await player.setAudioTrack(a);
          break;
        }
      }
    }
    switch (rec.subMode) {
      case 'off':
        await player.setSubtitleTrack(SubtitleTrack.no());
      case 'internal':
        for (final s in tracks.subtitle) {
          if (s.id == rec.subId) {
            await player.setSubtitleTrack(s);
            break;
          }
        }
      case 'external':
        final p = rec.extSubPath;
        if (p != null && File(p).existsSync()) {
          await _loadExternalSub(p, rec.subEncoding, name: rec.extSubName, quiet: true);
        }
    }
    if (rec.subDelayMs != 0) await _setProp('sub-delay', (rec.subDelayMs / 1000).toStringAsFixed(2));
  }

  void _saveProgress() {
    final it = item;
    if (it == null || loading || error != null || dur <= Duration.zero) return;
    final rec = store.rec(it.id);
    if (ended) {
      rec.finished = true;
      rec.positionMs = 0;
    } else {
      final p = posN.value.inMilliseconds;
      rec.positionMs = p < 5000 ? 0 : p;
      rec.finished = false;
    }
    rec.lastWatchedAt = DateTime.now().millisecondsSinceEpoch;
    store.save();
  }

  void _onCompleted() {
    if (abActive || loading || error != null) return;
    ended = true;
    _saveProgress();
    if (idx + 1 < widget.queue.length) {
      _load(idx + 1);
    } else {
      setState(() {
        controlsVisible = true;
        _hideTimer?.cancel();
      });
    }
  }

  void _showResume(Duration from) {
    setState(() => resumeFrom = from);
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => resumeFrom = null);
    });
  }

  // ---------------- 控制 ----------------

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!playing || panelOpen || seekPreview != null) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && playing && !panelOpen && seekPreview == null) setState(() => controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => controlsVisible = !controlsVisible);
    if (controlsVisible) _scheduleHide();
  }

  void _poke() {
    if (!controlsVisible) setState(() => controlsVisible = true);
    _scheduleHide();
  }

  Future<void> _togglePlay() async {
    if (error != null || loading) return;
    if (ended) {
      ended = false;
      await player.seek(Duration.zero);
      await player.play();
      return;
    }
    await player.playOrPause();
    _poke();
  }

  Future<void> _seekTo(Duration t) async {
    if (dur <= Duration.zero) return;
    if (t < Duration.zero) t = Duration.zero;
    if (t > dur) t = dur;
    posN.value = t;
    if (abActive && abA != null && abB != null && (t < abA! - const Duration(milliseconds: 300) || t > abB!)) {
      await _abClear();
      _toast('已退出循环');
    }
    await player.seek(t);
  }

  void _seekRel(int secs) {
    if (dur <= Duration.zero) return;
    _seekTo(posN.value + Duration(seconds: secs));
    _hud(secs < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded, '${secs > 0 ? '+' : ''}$secs 秒');
  }

  Future<void> _setRate(double r) async {
    rate = r;
    await player.setRate(r);
    if (store.prefs.rememberSpeed) {
      store.prefs.lastSpeed = r;
      store.save();
    }
    if (mounted) setState(() {});
  }

  void _hud(IconData icon, String text) {
    setState(() {
      hudIcon = icon;
      hudText = text;
    });
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => hudText = null);
    });
  }

  void _toast(String m) {
    if (!mounted) return;
    setState(() => toastText = m);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => toastText = null);
    });
  }

  bool get _videoIsLandscape {
    final it = item;
    if (it != null && it.width > 0 && it.height > 0) return it.width >= it.height;
    final w = player.state.width ?? 0;
    final h = player.state.height ?? 0;
    if (w > 0 && h > 0) return w >= h;
    return true;
  }

  void _applyOrientation() {
    final land = manualLandscape ?? _videoIsLandscape;
    SystemChrome.setPreferredOrientations(land
        ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : const [DeviceOrientation.portraitUp]);
  }

  void _toggleOrientation() {
    final cur = manualLandscape ?? _videoIsLandscape;
    manualLandscape = !cur;
    if (manualLandscape == _videoIsLandscape) manualLandscape = null;
    _applyOrientation();
    _poke();
  }

  void _handleBack() {
    if (locked) {
      setState(() => controlsVisible = true);
      _toast('屏幕已锁定，先点左侧的锁解锁');
      return;
    }
    if (manualLandscape != null) {
      manualLandscape = null;
      _applyOrientation();
      return;
    }
    Navigator.of(context).pop();
  }

  // ---------------- 手势 ----------------

  void _onDoubleTap(double width) {
    if (locked || error != null) return;
    final x = _dtPos?.dx ?? width / 2;
    if (x < width / 3) {
      _seekRel(-10);
    } else if (x > width * 2 / 3) {
      _seekRel(10);
    } else {
      _togglePlay();
    }
  }

  void _startLongPress() {
    if (locked || !playing || error != null) return;
    _rateBeforeLongPress = rate;
    player.setRate(2.0);
    setState(() {});
  }

  void _endLongPress() {
    final r = _rateBeforeLongPress;
    if (r == null) return;
    _rateBeforeLongPress = null;
    player.setRate(r);
    if (mounted) setState(() {});
  }

  void _hStart(DragStartDetails d, double width) {
    _hActive = !locked && error == null && dur > Duration.zero && d.localPosition.dx > 28 && d.localPosition.dx < width - 28;
    if (!_hActive) return;
    _hDx = 0;
    _hBase = posN.value;
  }

  void _hUpdate(DragUpdateDetails d, double width) {
    if (!_hActive) return;
    _hDx += d.delta.dx;
    final ms = _hBase.inMilliseconds + (_hDx / width * 120000).round();
    final t = Duration(milliseconds: ms.clamp(0, dur.inMilliseconds));
    setState(() => seekPreview = t);
  }

  void _hEnd() {
    if (!_hActive) return;
    _hActive = false;
    final t = seekPreview;
    setState(() => seekPreview = null);
    if (t != null) _seekTo(t);
    _scheduleHide();
  }

  void _vStart(DragStartDetails d, double width) {
    _vActive = !locked && error == null;
    if (!_vActive) return;
    _vLeft = d.localPosition.dx < width / 2;
    _vBase = _vLeft ? _brightness : _volume;
    _vDy = 0;
    _lastVolStep = -1;
    if (_vLeft) {
      Native.getBrightness().then((v) => _brightness = v);
    } else {
      Native.getVolume().then((v) => _volume = v);
    }
  }

  void _vUpdate(DragUpdateDetails d, double height) {
    if (!_vActive) return;
    _vDy += d.delta.dy;
    final v = (_vBase - _vDy / (height * 0.7)).clamp(0.0, 1.0);
    if (_vLeft) {
      _brightness = v;
      Native.setBrightness(v);
      _hud(Icons.brightness_6_rounded, '亮度 ${(v * 100).round()}%');
    } else {
      _volume = v;
      final step = (v * 100).round();
      if (step != _lastVolStep) {
        _lastVolStep = step;
        Native.setVolume(v);
      }
      _hud(v == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, '音量 $step%');
    }
  }

  // ---------------- AB 循环 ----------------

  String _secs(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(3);

  Future<void> _abTap() async {
    if (dur <= Duration.zero) {
      _toast('该视频不支持跳转，无法使用 AB 循环');
      return;
    }
    if (abActive) {
      await _abClear();
      _toast('已关闭循环');
      return;
    }
    final p = posN.value;
    if (abA == null) {
      setState(() => abA = p);
      _toast('已设 A 点 ${fmtDur(p)}，播到片段结尾再点一次');
      return;
    }
    if (p - abA! < const Duration(seconds: 1)) {
      _toast('B 点要比 A 点晚至少 1 秒');
      return;
    }
    abB = p;
    await _abApply(seekToA: true);
    _toast('A–B 循环中');
  }

  Future<void> _abApply({bool seekToA = false}) async {
    final a = abA, b = abB;
    if (a == null || b == null) return;
    await _setProp('ab-loop-a', _secs(a));
    await _setProp('ab-loop-b', _secs(b));
    if (mounted) setState(() => abActive = true);
    if (seekToA) {
      posN.value = a;
      await player.seek(a);
    }
    final it = item;
    if (it != null) {
      store.rec(it.id)
        ..abA = a.inMilliseconds
        ..abB = b.inMilliseconds;
      store.save();
    }
  }

  Future<void> _abClear() async {
    await _setProp('ab-loop-a', 'no');
    await _setProp('ab-loop-b', 'no');
    if (mounted) {
      setState(() {
        abActive = false;
        abA = null;
        abB = null;
      });
    }
  }

  Future<void> _abNudge(bool isA, int deltaMs) async {
    final a = abA, b = abB;
    if (a == null) return;
    var na = a, nb = b;
    if (isA) {
      na = Duration(milliseconds: (a.inMilliseconds + deltaMs).clamp(0, dur.inMilliseconds));
    } else if (b != null) {
      nb = Duration(milliseconds: (b.inMilliseconds + deltaMs).clamp(0, dur.inMilliseconds));
    }
    if (nb != null && nb - na < const Duration(seconds: 1)) {
      _toast('A、B 点至少相隔 1 秒');
      return;
    }
    setState(() {
      abA = na;
      abB = nb;
    });
    if (abActive) await _abApply(seekToA: isA);
  }

  Future<void> _abRestore() async {
    final it = item;
    if (it == null) return;
    final r = store.rec(it.id);
    if (r.abA == null || r.abB == null) return;
    setState(() {
      abA = Duration(milliseconds: r.abA!);
      abB = Duration(milliseconds: r.abB!);
    });
    await _abApply(seekToA: true);
  }

  // ---------------- 字幕 ----------------

  Future<bool> _loadExternalSub(String path, String encoding, {String? name, bool quiet = false}) async {
    try {
      final r = await Native.readText(path, encoding);
      await player.setSubtitleTrack(SubtitleTrack.data(r.text, title: name ?? '外挂字幕', language: 'zh'));
      final it = item;
      if (it != null) {
        store.rec(it.id)
          ..subMode = 'external'
          ..extSubPath = path
          ..extSubName = name
          ..subEncoding = encoding;
        store.save();
      }
      if (mounted) setState(() => subEncodingUsed = r.encoding);
      return true;
    } catch (_) {
      if (!quiet) _toast('字幕文件无法读取');
      return false;
    }
  }

  Future<void> _pickExternalSub() async {
    final it = item;
    if (it == null) return;
    List<String> uris;
    try {
      uris = await Native.pickSubtitle();
    } catch (_) {
      _toast('无法打开系统选择器');
      return;
    }
    if (uris.isEmpty) return;
    final info = await Native.queryUri(uris.first);
    final ext = extOf(info.name);
    if (!subtitleExts.contains(ext)) {
      _toast('请选择 .srt 或 .ass 字幕文件');
      return;
    }
    final dest = '${store.subsDir}/${it.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await Native.copyUri(newId(), uris.first, dest);
    } catch (_) {
      _toast('字幕文件无法读取');
      return;
    }
    final old = store.rec(it.id).extSubPath;
    final ok = await _loadExternalSub(dest, 'auto', name: info.name);
    if (ok) {
      if (old != null && old != dest) {
        try {
          File(old).deleteSync();
        } catch (_) {}
      }
      _toast('已加载字幕：${info.name}');
    }
  }

  Future<void> _setSubDelay(int ms) async {
    final it = item;
    if (it == null) return;
    ms = ms.clamp(-10000, 10000);
    store.rec(it.id).subDelayMs = ms;
    store.save();
    await _setProp('sub-delay', (ms / 1000).toStringAsFixed(2));
    if (mounted) setState(() {});
  }

  // ---------------- 生命周期 ----------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _endLongPress();
      player.pause();
      _saveProgress();
      store.flush();
    }
  }

  @override
  void dispose() {
    _saveProgress();
    store.flush();
    WidgetsBinding.instance.removeObserver(this);
    for (final s in subs) {
      s.cancel();
    }
    for (final t in [_hideTimer, _hudTimer, _toastTimer, _resumeTimer, _saveTimer]) {
      t?.cancel();
    }
    Native.abandonFocus();
    Native.resetBrightness();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    player.dispose();
    posN.dispose();
    bufN.dispose();
    super.dispose();
  }

  // ---------------- 界面 ----------------

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: playerTheme,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleBack();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: LayoutBuilder(builder: (context, c) {
            final size = Size(c.maxWidth, c.maxHeight);
            return Stack(children: [
              Positioned.fill(
                child: Video(
                  controller: controller,
                  controls: NoVideoControls,
                  fit: fit,
                  fill: Colors.black,
                  subtitleViewConfiguration: SubtitleViewConfiguration(
                    style: TextStyle(
                      fontSize: _subSizes[store.prefs.subSize.clamp(0, 2)],
                      height: 1.35,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 4),
                        Shadow(color: Colors.black, blurRadius: 1, offset: Offset(1, 1)),
                      ],
                    ),
                    // 控制条显示时字幕上移，避开底部控制
                    padding: EdgeInsets.fromLTRB(24, 0, 24, (controlsVisible || !playing) && !locked ? 120 : 36),
                  ),
                ),
              ),
              Positioned.fill(child: _gestureLayer(size)),
              if (buffering || loading) const Center(child: CircularProgressIndicator(color: kYellow)),
              if (hudText != null) Center(child: _hudBox()),
              if (seekPreview != null) Center(child: _seekPreviewBox()),
              if (_rateBeforeLongPress != null) _topChip('2 倍速播放中', Icons.fast_forward_rounded),
              _controls(size),
              if (resumeFrom != null && error == null) _resumeChip(),
              if (toastText != null)
                Positioned(
                  top: 64,
                  left: 0,
                  right: 0,
                  child: Center(child: _pill(Text(toastText!, style: const TextStyle(color: Colors.white)))),
                ),
              if (ended && idx + 1 >= widget.queue.length && error == null) _endOverlay(),
              if (error != null) _errorOverlay(),
              if (showGestureHint && !loading && error == null) _gestureHint(),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _gestureLayer(Size size) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      onDoubleTapDown: locked ? null : (d) => _dtPos = d.localPosition,
      onDoubleTap: locked ? null : () => _onDoubleTap(size.width),
      onLongPressStart: locked ? null : (_) => _startLongPress(),
      onLongPressEnd: locked ? null : (_) => _endLongPress(),
      onLongPressCancel: locked ? null : _endLongPress,
      onHorizontalDragStart: locked ? null : (d) => _hStart(d, size.width),
      onHorizontalDragUpdate: locked ? null : (d) => _hUpdate(d, size.width),
      onHorizontalDragEnd: locked ? null : (_) => _hEnd(),
      onHorizontalDragCancel: locked ? null : _hEnd,
      onVerticalDragStart: locked ? null : (d) => _vStart(d, size.width),
      onVerticalDragUpdate: locked ? null : (d) => _vUpdate(d, size.height),
      onVerticalDragEnd: locked ? null : (_) => _vActive = false,
      child: const SizedBox.expand(),
    );
  }

  Widget _pill(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(20)),
        child: child,
      );

  Widget _hudBox() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (hudIcon != null) Icon(hudIcon, color: kYellow, size: 30),
          const SizedBox(height: 6),
          Text(hudText!, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _seekPreviewBox() {
    final t = seekPreview!;
    final diff = t - posN.value;
    final sign = diff.isNegative ? '-' : '+';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(16)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${fmtDur(t)} / ${fmtDur(dur)}',
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('$sign${fmtDur(diff.abs())}', style: const TextStyle(color: kYellow, fontSize: 14)),
      ]),
    );
  }

  Widget _topChip(String text, IconData icon) => Positioned(
        top: 24,
        left: 0,
        right: 0,
        child: Center(
          child: _pill(Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: kYellow, size: 18),
            const SizedBox(width: 6),
            Text(text, style: const TextStyle(color: Colors.white)),
          ])),
        ),
      );

  Widget _resumeChip() => Positioned(
        top: 64,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.only(left: 16, right: 4),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.78), borderRadius: BorderRadius.circular(22)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('从 ${fmtDur(resumeFrom!)} 继续', style: const TextStyle(color: Colors.white)),
              TextButton(
                onPressed: () {
                  setState(() => resumeFrom = null);
                  _seekTo(Duration.zero);
                },
                child: const Text('从头播放', style: TextStyle(color: kYellow, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      );

  Widget _controls(Size size) {
    final visible = controlsVisible || !playing || panelOpen;
    final it = item;
    final pad = MediaQuery.of(context).padding;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Stack(children: [
            // 锁定按钮（始终在左侧中部）
            Positioned(
              left: 12 + pad.left,
              top: 0,
              bottom: 0,
              child: Center(
                child: _roundBtn(
                  locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  locked ? '解锁' : '锁定屏幕',
                  () {
                    setState(() => locked = !locked);
                    _toast(locked ? '已锁定，点锁形按钮解锁' : '已解锁');
                    _poke();
                  },
                  highlight: locked,
                ),
              ),
            ),
            if (!locked) ...[
              // 顶栏
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(4 + pad.left, 8 + pad.top, 8 + pad.right, 24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xB3000000), Color(0x00000000)],
                    ),
                  ),
                  child: Row(children: [
                    IconButton(
                      tooltip: '返回',
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        it?.name ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_hasQueue)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text('${idx + 1}/${widget.queue.length}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ),
                    IconButton(
                      tooltip: '更多设置',
                      icon: const Icon(Icons.tune_rounded, color: Colors.white),
                      onPressed: _openPanel,
                    ),
                  ]),
                ),
              ),
              // 底栏
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(8 + pad.left, 28, 8 + pad.right, 6 + pad.bottom),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xCC000000), Color(0x00000000)],
                    ),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ValueListenableBuilder<Duration>(
                      valueListenable: posN,
                      builder: (context, pos, _) => Row(children: [
                        const SizedBox(width: 8),
                        Text(fmtDur(seekPreview ?? pos), style: const TextStyle(color: Colors.white, fontSize: 12)),
                        Expanded(
                          child: ValueListenableBuilder<Duration>(
                            valueListenable: bufN,
                            builder: (context, buf, _) => SeekBar(
                              position: pos,
                              duration: dur,
                              buffered: buf,
                              a: abA,
                              b: abB,
                              enabled: error == null && !loading,
                              onInteract: _poke,
                              onPreview: (d) {
                                setState(() => seekPreview = d);
                                if (d == null) _scheduleHide();
                              },
                              onSeek: _seekTo,
                            ),
                          ),
                        ),
                        Text(dur > Duration.zero ? fmtDur(dur) : '--:--',
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                        const SizedBox(width: 8),
                      ]),
                    ),
                    Row(children: [
                      if (_hasQueue)
                        _iconBtn(Icons.skip_previous_rounded, '上一个', idx > 0 ? () => _gotoQueue(idx - 1) : null),
                      _iconBtn(
                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        playing ? '暂停' : '播放',
                        _togglePlay,
                        size: 34,
                      ),
                      if (_hasQueue)
                        _iconBtn(Icons.skip_next_rounded, '下一个',
                            idx + 1 < widget.queue.length ? () => _gotoQueue(idx + 1) : null),
                      const Spacer(),
                      _abButton(),
                      _textBtn('${_fmtRate(rate)}x', '倍速', () => _openPanel()),
                      _iconBtn(Icons.subtitles_outlined, '字幕与音轨', _openPanel),
                      _iconBtn(Icons.screen_rotation_rounded, '切换横竖屏', _toggleOrientation),
                    ]),
                  ]),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  String _fmtRate(double r) => r == r.roundToDouble() ? r.toStringAsFixed(1) : r.toString();

  void _gotoQueue(int i) {
    _saveProgress();
    _load(i);
  }

  Widget _abButton() {
    final label = abActive ? 'A–B' : (abA == null ? 'AB' : '设 B');
    final tip = abActive ? '关闭 A–B 循环' : (abA == null ? '设 A 点（循环起点）' : '设 B 点并开始循环');
    return Tooltip(
      message: tip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: abActive || abA != null ? kYellow : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              _abTap();
              _poke();
            },
            child: Container(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(label,
                  style: TextStyle(
                    color: abActive || abA != null ? kInk : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  )),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback? onTap, {double size = 26}) => IconButton(
        tooltip: tip,
        iconSize: size,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        color: Colors.white,
        disabledColor: Colors.white30,
        icon: Icon(icon),
        onPressed: onTap == null
            ? null
            : () {
                onTap();
                _poke();
              },
      );

  Widget _textBtn(String text, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(52, 48)),
          onPressed: onTap,
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );

  Widget _roundBtn(IconData icon, String tip, VoidCallback onTap, {bool highlight = false}) => Tooltip(
        message: tip,
        child: Material(
          color: highlight ? kYellow : Colors.black.withValues(alpha: 0.5),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(icon, color: highlight ? kInk : Colors.white, size: 22),
            ),
          ),
        ),
      );

  Widget _endOverlay() => Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.6),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('播放结束', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              Row(mainAxisSize: MainAxisSize.min, children: [
                FilledButton.icon(
                  onPressed: () {
                    setState(() => ended = false);
                    player.seek(Duration.zero);
                    player.play();
                  },
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('重播'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
              ]),
            ]),
          ),
        ),
      );

  Widget _errorOverlay() => Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.85),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline_rounded, color: kYellow, size: 44),
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                if (item != null) ...[
                  const SizedBox(height: 6),
                  Text(item!.name, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                ],
                if (showErrorDetail && errorDetail != null) ...[
                  const SizedBox(height: 12),
                  Text(errorDetail!, style: const TextStyle(color: Colors.white60, fontSize: 12), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
                  if (_hasQueue && idx + 1 < widget.queue.length)
                    FilledButton(onPressed: () => _gotoQueue(idx + 1), child: const Text('跳过')),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('返回'),
                  ),
                  if (errorDetail != null)
                    TextButton(
                      onPressed: () => setState(() => showErrorDetail = !showErrorDetail),
                      child: Text(showErrorDetail ? '收起详情' : '查看详情'),
                    ),
                ]),
              ]),
            ),
          ),
        ),
      );

  Widget _gestureHint() => Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.78),
          padding: const EdgeInsets.all(28),
          child: Center(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('播放手势', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                for (final l in const [
                  ['单击', '显示 / 隐藏控制'],
                  ['双击左 / 右', '后退 / 前进 10 秒'],
                  ['左右滑动', '调整进度'],
                  ['左半边上下滑', '调亮度'],
                  ['右半边上下滑', '调音量'],
                  ['长按', '临时 2 倍速'],
                  ['AB 按钮', '反复播放一段'],
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                          width: 110,
                          child: Text(l[0],
                              textAlign: TextAlign.right,
                              style: const TextStyle(color: kYellow, fontWeight: FontWeight.w700))),
                      const SizedBox(width: 16),
                      SizedBox(width: 150, child: Text(l[1], style: const TextStyle(color: Colors.white))),
                    ]),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    store.prefs.gestureHintShown = true;
                    store.save();
                    setState(() => showGestureHint = false);
                  },
                  child: const Text('知道了'),
                ),
              ]),
            ),
          ),
        ),
      );

  // ---------------- 面板 ----------------

  Future<void> _openPanel() async {
    setState(() {
      panelOpen = true;
      controlsVisible = true;
    });
    _hideTimer?.cancel();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (ctx) => Theme(
        data: playerTheme,
        child: _Panel(s: this),
      ),
    );
    if (!mounted) return;
    setState(() => panelOpen = false);
    _scheduleHide();
  }
}

class _Panel extends StatefulWidget {
  final _PlayerPageState s;
  const _Panel({required this.s});

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  _PlayerPageState get s => widget.s;

  Future<void> _do(Future<void> Function() f) async {
    await f();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final it = s.item;
    final rec = it == null ? null : store.rec(it.id);
    final tracks = s.player.state.tracks;
    final cur = s.player.state.track;
    final audios = tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final subsList = tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no' && !t.data).toList();
    final extActive = rec?.subMode == 'external' && cur.subtitle.data;
    final subOff = cur.subtitle.id == 'no';
    final h = MediaQuery.of(context).size.height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: h * 0.88),
      child: SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          _title('倍速'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in _speeds)
              ChoiceChip(
                label: Text('${s._fmtRate(r)}x'),
                selected: s.rate == r,
                onSelected: (_) => _do(() => s._setRate(r)),
              ),
          ]),
          _title('AB 循环'),
          Text(
            s.abActive
                ? '循环中：${fmtDur(s.abA!)} – ${fmtDur(s.abB!)}'
                : s.abA != null
                    ? '已设 A 点 ${fmtDur(s.abA!)}，播到结尾点“设 B”'
                    : '在片段开头点“设 A”，到结尾点“设 B”，即开始循环',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(
              onPressed: () => _do(() async {
                if (s.abActive) await s._abClear();
                s.refresh(() => s.abA = s.posN.value);
              }),
              child: const Text('设 A（当前位置）'),
            ),
            OutlinedButton(
              onPressed: s.abA == null
                  ? null
                  : () => _do(() async {
                        final p = s.posN.value;
                        if (p - s.abA! < const Duration(seconds: 1)) {
                          s._toast('B 点要比 A 点晚至少 1 秒');
                          return;
                        }
                        s.abB = p;
                        await s._abApply(seekToA: true);
                      }),
              child: const Text('设 B 并开始'),
            ),
            if (s.abActive || s.abA != null)
              TextButton(onPressed: () => _do(s._abClear), child: const Text('关闭循环')),
            if (!s.abActive && rec?.abA != null && rec?.abB != null)
              TextButton(
                onPressed: () => _do(s._abRestore),
                child: Text('恢复上次循环 ${fmtMs(rec!.abA!)}–${fmtMs(rec.abB!)}'),
              ),
          ]),
          if (s.abA != null) ...[
            const SizedBox(height: 8),
            _nudgeRow('A 点', s.abA!, (d) => _do(() => s._abNudge(true, d))),
            if (s.abB != null) _nudgeRow('B 点', s.abB!, (d) => _do(() => s._abNudge(false, d))),
          ],
          _title('字幕'),
          if (subsList.isNotEmpty)
            _radio('自动（视频默认字幕）', cur.subtitle.id == 'auto', () => _do(() async {
                  await s.player.setSubtitleTrack(SubtitleTrack.auto());
                  if (it != null) {
                    store.rec(it.id).subMode = 'auto';
                    store.save();
                  }
                })),
          _radio('关闭字幕', subOff, () => _do(() async {
                await s.player.setSubtitleTrack(SubtitleTrack.no());
                if (it != null) {
                  store.rec(it.id).subMode = 'off';
                  store.save();
                }
              })),
          for (final t in subsList)
            _radio(_trackName(t.title, t.language, t.id), !subOff && !cur.subtitle.data && cur.subtitle.id == t.id,
                () => _do(() async {
                      await s.player.setSubtitleTrack(t);
                      if (it != null) {
                        store.rec(it.id)
                          ..subMode = 'internal'
                          ..subId = t.id;
                        store.save();
                      }
                    })),
          if (rec?.extSubPath != null && File(rec!.extSubPath!).existsSync())
            _radio('外挂：${rec.extSubName ?? '字幕文件'}', extActive,
                () => _do(() async {
                      await s._loadExternalSub(rec.extSubPath!, rec.subEncoding, name: rec.extSubName);
                    })),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _do(s._pickExternalSub),
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('加载外挂字幕（.srt / .ass）'),
            ),
          ),
          if (extActive) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Text('字幕编码', style: TextStyle(color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _encodings.containsKey(rec!.subEncoding) ? rec.subEncoding : 'auto',
                  items: [
                    for (final e in _encodings.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(e.key == 'auto' && s.subEncodingUsed != null
                            ? '自动识别（${s.subEncodingUsed}）'
                            : e.value),
                      ),
                  ],
                  onChanged: (v) => _do(() async {
                    if (v == null) return;
                    await s._loadExternalSub(rec.extSubPath!, v, name: rec.extSubName);
                  }),
                ),
              ),
            ]),
            const Text('字幕乱码时，试试 GBK / GB18030 或 Big5。ASS 特效按纯文本显示。',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
          if (it != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              const Text('字幕时间', style: TextStyle(color: Colors.white)),
              const Spacer(),
              IconButton(
                tooltip: '提前 0.1 秒',
                icon: const Icon(Icons.remove_rounded),
                onPressed: () => _do(() => s._setSubDelay(store.rec(it.id).subDelayMs - 100)),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  '${store.rec(it.id).subDelayMs >= 0 ? '+' : ''}${(store.rec(it.id).subDelayMs / 1000).toStringAsFixed(1)} 秒',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              IconButton(
                tooltip: '延后 0.1 秒',
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _do(() => s._setSubDelay(store.rec(it.id).subDelayMs + 100)),
              ),
              TextButton(onPressed: () => _do(() => s._setSubDelay(0)), child: const Text('归零')),
            ]),
          ],
          const SizedBox(height: 8),
          Row(children: [
            const Text('字幕字号', style: TextStyle(color: Colors.white)),
            const Spacer(),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, label: Text('小')),
                ButtonSegment(value: 1, label: Text('中')),
                ButtonSegment(value: 2, label: Text('大')),
              ],
              selected: {store.prefs.subSize},
              onSelectionChanged: (v) {
                store.prefs.subSize = v.first;
                store.save();
                s.refresh(() {});
                setState(() {});
              },
            ),
          ]),
          _title('音轨'),
          if (audios.isEmpty)
            const Text('没有可选的音轨', style: TextStyle(color: Colors.white54))
          else ...[
            _radio('自动选择', cur.audio.id == 'auto', () => _do(() => s.player.setAudioTrack(AudioTrack.auto()))),
            for (final a in audios)
              _radio(_trackName(a.title, a.language, a.id), cur.audio.id == a.id, () => _do(() async {
                    await s.player.setAudioTrack(a);
                    if (it != null) {
                      store.rec(it.id).audioId = a.id;
                      store.save();
                    }
                  })),
          ],
          _title('画面比例'),
          Wrap(spacing: 8, children: [
            for (int i = 0; i < _fits.length; i++)
              ChoiceChip(
                label: Text(_fitNames[i]),
                selected: s.fit == _fits[i],
                onSelected: (_) {
                  s.refresh(() => s.fit = _fits[i]);
                  setState(() {});
                },
              ),
          ]),
          if (s.fit == BoxFit.cover)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('填充会裁掉画面边缘', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
        ]),
      ),
    );
  }

  String _trackName(String? title, String? lang, String id) {
    final parts = [if (title != null && title.isNotEmpty) title, if (lang != null && lang.isNotEmpty) lang];
    return parts.isEmpty ? '轨道 $id' : parts.join(' · ');
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t, style: const TextStyle(color: kYellow, fontSize: 14, fontWeight: FontWeight.w800)),
      );

  Widget _radio(String label, bool selected, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(children: [
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? kYellow : Colors.white54, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(color: Colors.white))),
          ]),
        ),
      );

  Widget _nudgeRow(String label, Duration v, void Function(int) nudge) => Row(children: [
        SizedBox(width: 44, child: Text(label, style: const TextStyle(color: Colors.white70))),
        IconButton(tooltip: '$label 提前 0.5 秒', icon: const Icon(Icons.remove_rounded), onPressed: () => nudge(-500)),
        SizedBox(
          width: 84,
          child: Text('${fmtDur(v)}.${(v.inMilliseconds % 1000) ~/ 100}',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        ),
        IconButton(tooltip: '$label 延后 0.5 秒', icon: const Icon(Icons.add_rounded), onPressed: () => nudge(500)),
      ]);
}
