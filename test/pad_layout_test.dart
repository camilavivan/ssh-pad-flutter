import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_pad_flutter/ui/pad/drag_divider.dart';
import 'package:ssh_pad_flutter/ui/pad/pad_breakpoints.dart';

void main() {
  test('PadBreakpoints split at 600', () {
    expect(PadBreakpoints.isSplit(const BoxConstraints(maxWidth: 599)), isFalse);
    expect(PadBreakpoints.isSplit(const BoxConstraints(maxWidth: 600)), isTrue);
    expect(PadBreakpoints.isSplitSize(const Size(900, 600)), isTrue);
  });

  test('clampLeftWidth respects min and fraction', () {
    expect(clampLeftWidth(100, 800), PadBreakpoints.leftMin);
    final mid = clampLeftWidth(300, 800);
    expect(mid, 300);
    final maxed = clampLeftWidth(500, 800);
    expect(maxed, lessThanOrEqualTo(800 * PadBreakpoints.leftMaxFraction));
  });

  testWidgets('DragDivider builds', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(width: 200, child: ColoredBox(color: Colors.red)),
              DragDivider(onDrag: _noop),
              Expanded(child: ColoredBox(color: Colors.blue)),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(DragDivider), findsOneWidget);
  });
}

void _noop(double _) {}
