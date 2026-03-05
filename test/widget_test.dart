import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/main.dart';

void main() {
  testWidgets('music player app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MusicPlayerApp());

    expect(find.text('Local Music Player'), findsOneWidget);
    expect(find.text('Add Folder (Recursive)'), findsOneWidget);
    expect(find.text('Add Files'), findsOneWidget);
  });
}
