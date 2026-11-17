import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxai_auth_probe/main.dart';

void main() {
  testWidgets('shows the MAX authorization probe screen', (tester) async {
    await tester.pumpWidget(const AuthProbeApp());

    expect(find.text('MAX Auth Probe'), findsOneWidget);
    expect(find.text('Подключение WebSocket + QR'), findsOneWidget);
    expect(find.text('Подключиться и получить QR'), findsOneWidget);
    expect(find.text('Журнал проверки'), findsOneWidget);
  });
}
