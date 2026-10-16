import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('小黄毛影音')))));
}
