// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:background_transfer_example/main.dart';

void main() {
  testWidgets('Verify app UI elements', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Verify that the app title is displayed
    expect(
      find.text('File Transfer Plugin Demo'),
      findsOneWidget,
    );

    // Verify that both Upload and Download sections exist
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);

    // Verify that the buttons are present
    expect(find.text('Download in Background'), findsOneWidget);
    expect(find.text('Select File'), findsOneWidget);
    expect(find.text('Upload in Background'), findsOneWidget);
  });
}
