import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pad/pad_shell.dart';

/// Legacy entry; M3 uses [PadShell] as the adaptive home.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const PadShell();
}
