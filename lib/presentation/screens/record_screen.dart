import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/sound_provider.dart';

class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  final _nameController = TextEditingController();
  String _emoji = '🎙';
  int _colorValue = const Color(0xFF7C3AED).toARGB32();

  static const _emojiOptions = ['🎙', '🤣', '🔥', '😈', '💥', '👏'];
  static const _colorOptions = [
    0xFF7C3AED,
    0xFF3B82F6,
    0xFFF59E0B,
    0xFFEF4444,
    0xFF14B8A6,
  ];

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(soundboardProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Grabar nueva frase',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Grabala, escuchala y guardala para dispararla despues desde la botonera.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: controller.isRecording
                      ? theme.colorScheme.errorContainer
                      : theme.colorScheme.primaryContainer,
                ),
                child: Icon(
                  controller.isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 52,
                  color: controller.isRecording
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                controller.isRecording ? 'Grabando...' : 'Listo para grabar',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: controller.isRecording ? null : controller.startRecording,
                    icon: const Icon(Icons.fiber_manual_record_rounded),
                    label: const Text('Grabar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.isRecording ? controller.stopRecording : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Parar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.recordingPath != null && !controller.isRecording
                        ? controller.previewRecording
                        : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Preview'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Nombre del audio',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Text('Emoji', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final emoji in _emojiOptions)
              ChoiceChip(
                label: Text(emoji, style: const TextStyle(fontSize: 20)),
                selected: _emoji == emoji,
                onSelected: (_) => setState(() => _emoji = emoji),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Color', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in _colorOptions)
              InkWell(
                onTap: () => setState(() => _colorValue = color),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(color),
                    border: Border.all(
                      color: _colorValue == color ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: controller.recordingPath == null || controller.isRecording
              ? null
              : () async {
                  await controller.saveRecording(
                    name: _nameController.text,
                    emoji: _emoji,
                    colorValue: _colorValue,
                  );
                  if (!mounted || controller.recordingPath != null) {
                    return;
                  }
                  setState(() {
                    _nameController.clear();
                    _emoji = '🎙';
                    _colorValue = const Color(0xFF7C3AED).toARGB32();
                  });
                },
          icon: const Icon(Icons.save_rounded),
          label: const Text('Guardar grabacion'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
