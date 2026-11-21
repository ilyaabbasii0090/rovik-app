import 'package:flutter_test/flutter_test.dart';
import 'package:rovik_app/main.dart';

void main() {
  testWidgets('اپ بالا می‌آید و صفحه اصلی فارسی است',
      (WidgetTester tester) async {
    await tester.pumpWidget(const RovikApp());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Rovik'), findsWidgets);
    expect(find.text('سرورها (۰)'), findsOneWidget);
    expect(find.text('هنوز سروری نداری'), findsOneWidget);
    expect(find.text('پشتیبانی'), findsOneWidget);
    expect(find.text('خرید / تمدید'), findsOneWidget);
  });
}
