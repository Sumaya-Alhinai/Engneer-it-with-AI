import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aman_ai_app/main.dart';

void main() {
  testWidgets('يُبنى التطبيق ويعرض الشاشة الأولى دون أخطاء', (WidgetTester tester) async {
    await tester.pumpWidget(const AmanAIApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
