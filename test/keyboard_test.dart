import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_pad_flutter/ui/keyboard/app_escape_policy.dart';
import 'package:ssh_pad_flutter/ui/terminal/hardware_keyboard_handler.dart';
import 'package:ssh_pad_flutter/ui/terminal/terminal_page.dart';
import 'package:xterm/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppEscapePolicy.uninstall();
    AppEscapePolicy.setTerminalSink(null);
  });

  test('soft keyboard type prefers visiblePassword (no suggestions)', () {
    expect(kTerminalKeyboardType, TextInputType.visiblePassword);
  });

  test('Escape disposition: overlay first, then terminal, else consume', () {
    expect(
      AppEscapePolicy.disposition(
        terminalShouldReceive: false,
        barrierDismissiblePopup: true,
      ),
      EscapeDisposition.allowOverlayDismiss,
    );
    expect(
      AppEscapePolicy.disposition(
        terminalShouldReceive: true,
        barrierDismissiblePopup: false,
      ),
      EscapeDisposition.sendToPty,
    );
    expect(
      AppEscapePolicy.disposition(
        terminalShouldReceive: false,
        barrierDismissiblePopup: false,
      ),
      EscapeDisposition.consume,
    );
    // Overlay wins over terminal (menus must close).
    expect(
      AppEscapePolicy.disposition(
        terminalShouldReceive: true,
        barrierDismissiblePopup: true,
      ),
      EscapeDisposition.allowOverlayDismiss,
    );
  });

  test('shortcutsWithoutEscapeBack strips Escape→DismissIntent', () {
    final base = Map<ShortcutActivator, Intent>.of(
      WidgetsApp.defaultShortcuts,
    );
    final fixed = AppEscapePolicy.shortcutsWithoutEscapeBack(base);
    final esc = fixed.entries.where((e) {
      final a = e.key;
      return a is SingleActivator &&
          a.trigger == LogicalKeyboardKey.escape &&
          !a.control &&
          !a.shift &&
          !a.alt &&
          !a.meta;
    });
    expect(esc, isNotEmpty);
    for (final e in esc) {
      expect(e.value, isA<DoNothingAndStopPropagationIntent>());
      expect(e.value, isNot(isA<DismissIntent>()));
    }
  });

  test('actionsWithoutEscapeBack neutralizes DismissIntent', () {
    final fixed = AppEscapePolicy.actionsWithoutEscapeBack(
      Map<Type, Action<Intent>>.of(WidgetsApp.defaultActions),
    );
    expect(fixed[DismissIntent], isA<DoNothingAction>());
  });

  test('early Esc with terminal sink sends once and is handled', () {
    final term = Terminal(maxLines: 100);
    final output = <int>[];
    term.onOutput = (data) {
      output.addAll(data.codeUnits);
    };

    AppEscapePolicy.setTerminalSink(
      TerminalEscapeSink(
        terminal: term,
        isActive: () => true,
        hasTerminalFocus: () => true,
      ),
    );

    final down = AppEscapePolicy.handleEarlyKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        timeStamp: Duration.zero,
      ),
    );
    expect(down, KeyEventResult.handled);
    expect(output, contains(0x1b));
    expect(output.where((c) => c == 0x1b).length, 1);

    final before = output.length;
    final repeat = AppEscapePolicy.handleEarlyKeyEvent(
      const KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        timeStamp: Duration.zero,
      ),
    );
    expect(repeat, KeyEventResult.handled);
    expect(output.length, before); // no flood on repeat
  });

  test('early Esc without terminal sink is consumed (not ignored)', () {
    AppEscapePolicy.setTerminalSink(null);
    final result = AppEscapePolicy.handleEarlyKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        timeStamp: Duration.zero,
      ),
    );
    expect(result, KeyEventResult.handled);
  });

  test('early handler ignores non-Escape and goBack', () {
    AppEscapePolicy.setTerminalSink(null);
    expect(
      AppEscapePolicy.handleEarlyKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      ),
      KeyEventResult.ignored,
    );
    expect(
      AppEscapePolicy.handleEarlyKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.browserBack,
          logicalKey: LogicalKeyboardKey.goBack,
          timeStamp: Duration.zero,
        ),
      ),
      KeyEventResult.ignored,
    );
  });

  test('ActiveTerminalKeyboard no longer owns Escape (avoid double 0x1b)', () {
    final term = Terminal(maxLines: 100);
    final kb = ActiveTerminalKeyboard(
      terminal: term,
      isActive: () => true,
    );
    expect(
      kb.handle(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.escape,
          logicalKey: LogicalKeyboardKey.escape,
          timeStamp: Duration.zero,
        ),
      ),
      isFalse,
    );
  });

  test('TerminalEscapeSink: focused always receives; unfocused depends on editable',
      () {
    final term = Terminal(maxLines: 100);
    var active = true;
    var focused = false;
    final sink = TerminalEscapeSink(
      terminal: term,
      isActive: () => active,
      hasTerminalFocus: () => focused,
    );
    // Unfocused + no EditableText primary → pad-split chrome may receive Esc.
    expect(AppEscapePolicy.primaryFocusIsEditableText(), isFalse);
    expect(sink.shouldReceiveEscape(), isTrue);

    focused = true;
    expect(sink.shouldReceiveEscape(), isTrue);

    active = false;
    expect(sink.shouldReceiveEscape(), isFalse);
  });

  testWidgets('Ctrl+[ with terminal sink sends single 0x1b', (tester) async {
    final term = Terminal(maxLines: 100);
    final output = <int>[];
    term.onOutput = (data) {
      output.addAll(data.codeUnits);
    };

    AppEscapePolicy.install();
    AppEscapePolicy.setTerminalSink(
      TerminalEscapeSink(
        terminal: term,
        isActive: () => true,
        hasTerminalFocus: () => true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        shortcuts: AppEscapePolicy.shortcutsWithoutEscapeBack(
          Map<ShortcutActivator, Intent>.of(WidgetsApp.defaultShortcuts),
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();

    expect(output, contains(0x1b));
    expect(output.where((c) => c == 0x1b).length, 1);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('Esc does not pop a page route (DismissIntent disabled)',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    AppEscapePolicy.bindNavigator(navKey);
    AppEscapePolicy.install();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        shortcuts: AppEscapePolicy.shortcutsWithoutEscapeBack(
          Map<ShortcutActivator, Intent>.of(WidgetsApp.defaultShortcuts),
        ),
        actions: AppEscapePolicy.actionsWithoutEscapeBack(
          Map<Type, Action<Intent>>.of(WidgetsApp.defaultActions),
        ),
        home: Builder(
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
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('inner-page'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Page route must remain — Esc is not Back / DismissIntent.
    expect(find.text('inner-page'), findsOneWidget);
  });

  testWidgets('Esc with focused terminal sink sends 0x1b via early handler',
      (tester) async {
    final term = Terminal(maxLines: 100);
    final output = <int>[];
    term.onOutput = (data) {
      output.addAll(data.codeUnits);
    };

    final focus = FocusNode();
    addTearDown(focus.dispose);

    AppEscapePolicy.install();
    AppEscapePolicy.setTerminalSink(
      TerminalEscapeSink(
        terminal: term,
        isActive: () => true,
        hasTerminalFocus: () => focus.hasFocus,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        shortcuts: AppEscapePolicy.shortcutsWithoutEscapeBack(
          Map<ShortcutActivator, Intent>.of(WidgetsApp.defaultShortcuts),
        ),
        actions: AppEscapePolicy.actionsWithoutEscapeBack(
          Map<Type, Action<Intent>>.of(WidgetsApp.defaultActions),
        ),
        home: Scaffold(
          body: Focus(
            focusNode: focus,
            autofocus: true,
            child: const Text('term-focus'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(output, contains(0x1b));
    expect(output.where((c) => c == 0x1b).length, 1);
  });
}
