import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deginage/common/ui.dart';
import 'package:deginage/signage/transition_switcher.dart';
import 'package:deginage/src/rust/api/models.dart';

void main() {
  test('メディア拡張子の判定が正しく動作する', () {
    expect(mediaKindForPath('C:/media/sample.png'), MediaKind.image);
    expect(mediaKindForPath('/home/user/movie.MP4'), MediaKind.video);
    expect(mediaKindForPath('readme.txt'), isNull);
  });

  test('曜日マスクの表示ラベルが正しく生成される', () {
    expect(weekdayMaskLabel(0), '毎日');
    expect(weekdayMaskLabel(0x7F), '毎日');
    expect(weekdayMaskLabel(0x1F), '平日');
    expect(weekdayMaskLabel(0x60), '土日');
    expect(weekdayMaskLabel(0x05), '月・水');
  });

  testWidgets('TransitionSwitcher がトランジション付きで子を切り替える', (tester) async {
    final transition = TransitionSetting(
      kind: TransitionKind.crossFade,
      durationMs: 300,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TransitionSwitcher(
          transition: transition,
          child: const Text('スライド1', key: ValueKey('1')),
        ),
      ),
    );
    expect(find.text('スライド1'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: TransitionSwitcher(
          transition: transition,
          child: const Text('スライド2', key: ValueKey('2')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('スライド2'), findsOneWidget);
    expect(find.text('スライド1'), findsNothing);
  });
}
