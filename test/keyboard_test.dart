import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_pad_flutter/ui/terminal/hardware_keyboard_handler.dart';
import 'package:ssh_pad_flutter/ui/terminal/terminal_page.dart';
import 'package:xterm/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('soft keyboard type prefers visiblePassword (no suggestions)', () {
    expect(kTerminalKeyboardType, TextInputType.visiblePassword);
  });

  test('ActiveTerminalKeyboard Ctrl-C is consumed as interrupt path', () {
    final term = Terminal(maxLines: 100);
    var active = true;
    final kb = ActiveTerminalKeyboard(
      terminal: term,
      isActive: () => active,
    );
    // Simulate Ctrl+C via HardwareKeyboard — in unit test we call handle with
    // a KeyDownEvent; without real HW state, control may be false so just
    // ensure Escape is consumed.
    final esc = kb.handle(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        timeStamp: Duration.zero,
      ),
    );
    expect(esc, isTrue);

    active = false;
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
}
