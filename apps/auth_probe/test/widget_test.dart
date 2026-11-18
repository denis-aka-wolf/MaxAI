import 'package:flutter_test/flutter_test.dart';
import 'package:maxai_auth_probe/main.dart';

void main() {
  testWidgets('shows the MAX authorization probe screen', (tester) async {
    await tester.pumpWidget(const AuthProbeApp());

    expect(find.text('MAX Auth Probe'), findsOneWidget);
    expect(find.text('Подключение WebSocket + QR'), findsOneWidget);
    expect(
      find.text('Подключиться / восстановить авторизацию'),
      findsOneWidget,
    );
    expect(find.text('Войти по SMS'), findsOneWidget);
    expect(find.text('Проверить Root'), findsOneWidget);
    expect(find.text('Проверить Sub CA'), findsOneWidget);
    expect(find.text('Установить Root'), findsOneWidget);
    expect(find.text('Установить Sub CA'), findsOneWidget);
    expect(find.text('TLS: Default'), findsOneWidget);
    expect(find.text('TLS: MaxAI'), findsOneWidget);
    expect(find.text('Журнал проверки'), findsOneWidget);
  });
}
