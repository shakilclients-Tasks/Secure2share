import 'package:drive2share/models/secure_detail.dart';
import 'package:drive2share/screens/secure_details_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('secure detail form shows its title only in the app bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SecureDetailsFormScreen(type: SecureDetailType.voterId),
      ),
    );

    expect(find.text('Voter ID'), findsOneWidget);
  });
}
