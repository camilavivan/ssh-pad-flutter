import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/keepalive/keepalive_controller.dart';
import 'data/host_store.dart';
import 'ui/pad/pad_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const SshPadApp(),
    ),
  );
}

class SshPadApp extends ConsumerWidget {
  const SshPadApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ensure keepalive controller is created and observes lifecycle.
    ref.watch(keepAliveControllerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'SSH Pad',
      theme: AppThemes.light,
      darkTheme: AppThemes.dark,
      themeMode: themeMode,
      home: const PadShell(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Banner(
          message: 'M3',
          location: BannerLocation.topEnd,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
