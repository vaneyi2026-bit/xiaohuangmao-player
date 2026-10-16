import 'package:flutter_test/flutter_test.dart';
import 'package:xhmplayer/util.dart';

void main() {
  test('formats durations', () {
    expect(fmtDur(const Duration(minutes: 12, seconds: 30)), '12:30');
    expect(fmtDur(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });
}
