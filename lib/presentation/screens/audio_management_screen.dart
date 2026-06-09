import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/sound.dart';
import '../providers/sound_provider.dart';

class AudioManagementScreen extends ConsumerWidget {
  const AudioManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(soundboardProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Audios',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Aca administras todos los audios. Para agregar nuevos, usa Personalizados o la pantalla Grabar.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: controller.setSearchQuery,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Buscar por nombre',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 18),
        for (final sound in controller.allSoundsFiltered)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SoundListTile(sound: sound),
          ),
      ],
    );
  }
}

class _SoundListTile extends ConsumerWidget {
  const _SoundListTile({required this.sound});

  final Sound sound;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(soundboardProvider);
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: CircleAvatar(
          backgroundColor: sound.color.withValues(alpha: 0.2),
          child: Text(sound.emoji),
        ),
        title: Text(sound.name),
        subtitle: Text(sound.isDefault ? 'Audio por defecto' : 'Audio personalizado'),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'Favorito',
              onPressed: () => controller.toggleFavorite(sound),
              icon: Icon(sound.isFavorite ? Icons.favorite : Icons.favorite_border),
            ),
            IconButton(
              tooltip: 'Editar',
              onPressed: () => _openEditor(context, ref, sound),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Reproducir',
              onPressed: () => controller.playSound(sound),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
            if (!sound.isDefault)
              IconButton(
                tooltip: 'Eliminar',
                onPressed: () => controller.deleteSound(sound),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref, Sound sound) async {
    final nameController = TextEditingController(text: sound.name);
    String emoji = sound.emoji;
    int colorValue = sound.colorValue;
    final controller = ref.read(soundboardProvider);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: ['🎙', '🤣', '🔥', '😱', '🏆', '😶']
                        .map(
                          (value) => ChoiceChip(
                            label: Text(value),
                            selected: emoji == value,
                            onSelected: (_) => setState(() => emoji = value),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final color in const [
                        0xFF7C3AED,
                        0xFF3B82F6,
                        0xFFF59E0B,
                        0xFFEF4444,
                        0xFF14B8A6,
                      ])
                        InkWell(
                          onTap: () => setState(() => colorValue = color),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(color),
                              border: Border.all(
                                color: colorValue == color ? Colors.white : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      await controller.updateSound(
                        sound.copyWith(
                          name: nameController.text.trim().isEmpty
                              ? sound.name
                              : nameController.text.trim(),
                          emoji: emoji,
                          colorValue: colorValue,
                        ),
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Guardar cambios'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
