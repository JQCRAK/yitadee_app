import 'package:flutter_test/flutter_test.dart';
import 'package:yitadee_app/main.dart';

void main() {
  testWidgets('Prueba de arranque', (WidgetTester tester) async {
    // Construye nuestra app y dispara un frame.
    await tester.pumpWidget(const MyApp());

    // Verifica que el título principal de la app aparezca en pantalla.
    expect(find.text('YITADEE!!!'), findsOneWidget);
  });
}