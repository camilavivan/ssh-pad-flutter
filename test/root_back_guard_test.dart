import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_pad_flutter/ui/keyboard/root_back_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RootBackGuard: nested route pops on Back; root stays',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: RootBackGuard(
          navigatorKey: navKey,
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(
                            body: Center(child: Text('inner-page')),
                          ),
                        ),
                      );
                    },
                    child: const Text('go'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('inner-page'), findsOneWidget);
    expect(navKey.currentState!.canPop(), isTrue);

    // System / gesture Back pops the nested route.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('inner-page'), findsNothing);
    expect(find.text('go'), findsOneWidget);
    expect(navKey.currentState!.canPop(), isFalse);

    // Root Back must NOT finish / remove the shell.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
