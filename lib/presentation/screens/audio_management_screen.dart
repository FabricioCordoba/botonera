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
    final filteredSounds = controller.allSoundsFiltered;

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
            FilledButton.icon(
              onPressed: controller.isBusy ? null : () => controller.importCustomSound(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Administrá todos los audios. Podés importar archivos mp3, wav, m4a o aac, o grabar nuevos desde la pestaña Grabar.',
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
        if (filteredSounds.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                controller.searchQuery.isEmpty
                    ? 'No hay audios todavía. Tocá Agregar para importar uno.'
                    : 'No se encontraron audios con esa búsqueda.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final sound in filteredSounds)
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: CircleAvatar(
          backgroundColor: sound.color.withValues(alpha: 0.2),
          child: Text(sound.emoji),
        ),
        title: Text(sound.name),
        subtitle: Text(sound.isDefault ? 'Audio por defecto' : 'Audio personalizado'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Reproducir',
              onPressed: () => controller.playSound(sound),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
            if (!sound.isDefault)
              IconButton(
                tooltip: 'Eliminar',
                onPressed: () => _confirmDelete(context, ref, sound),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: theme.colorScheme.error,
                ),
              ),
            PopupMenuButton<_SoundAction>(
              tooltip: 'Más opciones',
              onSelected: (action) async {
                switch (action) {
                  case _SoundAction.favorite:
                    await controller.toggleFavorite(sound);
                  case _SoundAction.edit:
                    if (context.mounted) {
                      await _openEditor(context, ref, sound);
                    }
                  case _SoundAction.delete:
                    if (context.mounted) {
                      await _confirmDelete(context, ref, sound);
                    }
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _SoundAction.favorite,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      sound.isFavorite ? Icons.favorite : Icons.favorite_border,
                    ),
                    title: Text(sound.isFavorite ? 'Quitar favorito' : 'Marcar favorito'),
                  ),
                ),
                const PopupMenuItem(
                  value: _SoundAction.edit,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Editar'),
                  ),
                ),
                if (!sound.isDefault)
                  PopupMenuItem(
                    value: _SoundAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        'Eliminar',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Sound sound,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar audio'),
        content: Text('¿Querés eliminar "${sound.name}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(soundboardProvider).deleteSound(sound);
    }
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

enum _SoundAction { favorite, edit, delete }
