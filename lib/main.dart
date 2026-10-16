import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'import_service.dart';
import 'native.dart';
import 'pages/home_page.dart';
import 'pages/import_sheet.dart';
import 'pages/library_page.dart';
import 'pages/settings_page.dart';
import 'store.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['libmpv / FFmpeg'],
      '本 App 通过 media_kit 使用 libmpv 与 FFmpeg 播放视频。这些库按 GNU LGPL 等开源许可分发，'
      '版权归各自作者所有。对应源码可在 https://github.com/media-kit 及各项目官网获取，也可向本 App 作者索取。',
    );
  });
  await store.init();
  importer.init();
  runApp(const XhmApp());
}

class XhmApp extends StatelessWidget {
  const XhmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: store.themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: '小黄毛影音',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark][mode.clamp(0, 2)],
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const RootShell(),
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tab = 0;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    importer.toast = (m) => messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
    importer.askDuplicate = _askDuplicate;
    _sub = Native.events.listen((e) {
      if (e['type'] == 'shared') _handleShared(e);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final e in await Native.takeShared()) {
        _handleShared(e);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<bool> _askDuplicate(String name) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return true;
    final r = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('可能已经导入过'),
        content: Text('媒体库里已有同名、同大小的视频：\n$name'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('跳过')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('保留两份')),
        ],
      ),
    );
    return r == true;
  }

  void _handleShared(Map<dynamic, dynamic> e) {
    final uris = (e['uris'] as List?)?.cast<String>() ?? const <String>[];
    final files = uris.where((u) => !u.startsWith('http://') && !u.startsWith('https://')).toList();
    if (files.length < uris.length || (uris.isEmpty && e['text'] != null)) {
      importer.toast?.call('暂不支持链接，请分享视频文件本身');
    }
    if (files.isEmpty) return;
    importer.addUris(files, 'share');
    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      Navigator.of(ctx).popUntil((r) => r.isFirst);
      showImportSheet(ctx);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: const [HomePage(), LibraryPage(), SettingsPage()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.play_circle_outline_rounded), selectedIcon: Icon(Icons.play_circle_rounded), label: '观看'),
          NavigationDestination(icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library_rounded), label: '媒体库'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: '设置'),
        ],
      ),
    );
  }
}
