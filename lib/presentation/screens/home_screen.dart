import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/sound.dart';
import '../providers/sound_provider.dart';
import '../widgets/sound_button.dart';
import 'audio_management_screen.dart';
import 'record_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(soundboardProvider);
    final pages = [
      _DashboardPage(controller: controller),
      const RecordScreen(),
      const AudioManagementScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: SafeArea(
        child: controller.isInitialized
            ? IndexedStack(index: _index, children: pages)
            : const Center(child: CircularProgressIndicator()),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) async {
          await controller.stopPlayback();
          if (mounted) {
            setState(() => _index = value);
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.mic_rounded), label: 'Grabar'),
          NavigationDestination(icon: Icon(Icons.library_music_rounded), label: 'Audios'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Config'),
        ],
      ),
    );
  }
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({required this.controller});

  final SoundProvider controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCategory = controller.categories.where(
      (item) => item.id == controller.selectedCategoryId,
    );
    final categoryName = selectedCategory.isEmpty ? null : selectedCategory.first.name;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Soundboard Epico',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'El boton listo para rematar cualquier momento gracioso.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final category in controller.visibleCategories)
                      ChoiceChip(
                        label: Text('${category.icon} ${category.name} (${controller.sounds.where((sound) => sound.categoryId == category.id).length})'),
                        selected: category.id == controller.selectedCategoryId,
                        onSelected: (_) => controller.selectCategory(category.id),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                if (controller.favoriteSounds.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Favoritos',
                    trailing: '${controller.favoriteSounds.length}/8',
                  ),
                  const SizedBox(height: 12),
                  _FavoritesRow(sounds: controller.favoriteSounds),
                  const SizedBox(height: 20),
                ],
                _SectionHeader(
                  title: categoryName ?? 'Audios',
                  trailing: '${controller.currentCategorySounds.length} botones',
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index == controller.currentCategorySounds.length &&
                    controller.selectedCategoryId == 'custom') {
                  return _AddSoundTile(
                    onTap: controller.importCustomSound,
                  );
                }
                final sound = controller.currentCategorySounds[index];
                return SizedBox(
                  height: _buttonHeight(controller.settings.buttonSize),
                  child: SoundButton(
                    sound: sound,
                    buttonSize: controller.settings.buttonSize,
                    isPlaying: controller.currentlyPlayingId == sound.id,
                    onPressed: () => controller.playSound(sound),
                    onFavoriteToggle: () => controller.toggleFavorite(sound),
                  ),
                );
              },
              childCount: controller.currentCategorySounds.length +
                  (controller.selectedCategoryId == 'custom' ? 1 : 0),
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columnsForWidth(MediaQuery.of(context).size.width),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: _childAspectRatio(controller.settings.buttonSize),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    'Ultima reproduccion: ${controller.lastPlayedSound?.name ?? 'Todavia nada'} (${controller.formatLastPlayed(controller.lastPlayedSound)})',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 14),
                if (controller.historySounds.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: controller.historySounds
                          .map(
                            (sound) => ActionChip(
                              avatar: Text(sound.emoji),
                              label: Text(sound.name),
                              onPressed: () => controller.playSound(sound),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  int _columnsForWidth(double width) {
    if (width >= 1100) {
      return 4;
    }
    if (width >= 700) {
      return 3;
    }
    return 2;
  }

  double _childAspectRatio(SoundButtonSize size) {
    switch (size) {
      case SoundButtonSize.small:
        return 1.12;
      case SoundButtonSize.large:
        return 0.9;
      case SoundButtonSize.medium:
        return 1;
    }
  }

  double _buttonHeight(SoundButtonSize size) {
    switch (size) {
      case SoundButtonSize.small:
        return 122;
      case SoundButtonSize.large:
        return 188;
      case SoundButtonSize.medium:
        return 154;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        Text(
          trailing,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _FavoritesRow extends ConsumerWidget {
  const _FavoritesRow({required this.sounds});

  final List<Sound> sounds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(soundboardProvider);
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final sound = sounds[index];
          return ActionChip(
            avatar: Text(sound.emoji),
            label: Text(sound.name),
            onPressed: () => controller.playSound(sound),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemCount: sounds.length,
      ),
    );
  }
}

class _AddSoundTile extends StatelessWidget {
  const _AddSoundTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.35),
            style: BorderStyle.solid,
          ),
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline_rounded, size: 34),
              SizedBox(height: 8),
              Text('Agregar audio'),
            ],
          ),
        ),
      ),
    );
  }
}
