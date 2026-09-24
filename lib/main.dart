import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/keepalive/keepalive_controller.dart';
import 'data/host_store.dart';
import 'ui/home_page.dart';
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

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

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
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Banner(
          message: 'M0',
          location: BannerLocation.topEnd,
          child: Stack(
            children: [
              ?child,
              Positioned(
                right: 8,
                bottom: 8,
                child: Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(20),
                  child: IconButton(
                    tooltip: '切换主题',
                    icon: Icon(
                      themeMode == ThemeMode.dark
                          ? Icons.light_mode
                          : Icons.dark_mode,
                    ),
                    onPressed: () {
                      final next = themeMode == ThemeMode.dark
                          ? ThemeMode.light
                          : ThemeMode.dark;
                      ref.read(themeModeProvider.notifier).state = next;
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
