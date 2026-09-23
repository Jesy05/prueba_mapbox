import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_mapbox/main.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('muestra la identidad de Vygo', (WidgetTester tester) async {
    await tester.pumpWidget(const VygoApp());

    expect(find.text('VYGO'), findsOneWidget);
    expect(find.text('Registrar ubicación'), findsOneWidget);
  });
}
