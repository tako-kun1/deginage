import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:deginage/src/rust/api/simple.dart';
import 'package:deginage/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  testWidgets('Rust コアが初期化されバージョンを取得できる', (tester) async {
    expect(coreVersion(), isNotEmpty);
  });
}
