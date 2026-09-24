import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

  test('Escape disposition: terminal / overlay / consume', () {
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
        barrierDismissiblePopup: true,
      ),
      EscapeDisposition.allowOverlayDismiss,
    );
    expect(
      AppEscapePolicy.disposition(
        terminalShouldReceive: false,
        barrierDismissiblePopup: false,
      ),
      EscapeDisposition.consume,
    );
    // Terminal wins over overlay.
    expect(
      AppEscapePolicy.disposition(
        terminalShouldReceive: true,
        barrierDismissiblePopup: true,
      ),
      EscapeDisposition.sendToPty,
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

  test('TerminalEscapeSink requires active + focus', () {
    final term = Terminal(maxLines: 100);
    var active = true;
    var focused = false;
    final sink = TerminalEscapeSink(
      terminal: term,
      isActive: () => active,
      hasTerminalFocus: () => focused,
    );
    expect(sink.shouldReceiveEscape(), isFalse);
    focused = true;
    expect(sink.shouldReceiveEscape(), isTrue);
    active = false;
    expect(sink.shouldReceiveEscape(), isFalse);
  });
}
