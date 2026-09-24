import 'package:flutter/material.dart';

/// Blocks [SystemNavigator.pop] / Activity finish when Back hits the root route.
///
/// In-app [Navigator] pushes (host editor, settings, dialogs) still pop via
/// the navigator first. Only when nothing remains to pop do we stay in-app
/// instead of leaving to the desktop (which would kill the SSH session on
/// ColorOS / OnePlus Pad when OEM Esc is remapped to BACK).
class RootBackGuard extends StatelessWidget {
  const RootBackGuard({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  final Widget child;

  /// App [NavigatorState] key — injectable for widget tests.
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = navigatorKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        }
        // else: stay in app — do not SystemNavigator.pop / finish Activity
      },
      child: child,
    );
  }
}
