import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secure_p2p_messenger/app_root.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
