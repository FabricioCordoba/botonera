import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/providers/sound_provider.dart';
import 'presentation/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SoundboardApp()));
}

class SoundboardApp extends ConsumerWidget {
  const SoundboardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(soundboardProvider);

    return MaterialApp(
      title: 'Soundboard Epico',
      debugShowCheckedModeBanner: false,
      themeMode: controller.settings.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C3AED),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C3AED),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF111827),
      ),
      home: const HomeScreen(),
      builder: (context, child) {
        final message = controller.bannerMessage;
        if (message == null) {
          return child ?? const SizedBox.shrink();
        }

        final isError = controller.bannerIsError;
        final scheme = Theme.of(context).colorScheme;

        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Material(
                color: isError ? scheme.errorContainer : scheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: isError ? scheme.onErrorContainer : scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
