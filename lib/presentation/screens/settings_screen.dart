import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/sound.dart';
import '../providers/sound_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(soundboardProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Configuracion',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 18),
        _Panel(
          title: 'Reproduccion',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Volumen global'),
              subtitle: Slider(
                value: controller.settings.globalVolume,
                onChanged: controller.updateGlobalVolume,
              ),
              trailing: Text('${(controller.settings.globalVolume * 100).round()}%'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vibracion al tocar'),
              value: controller.settings.vibrationEnabled,
              onChanged: controller.updateVibration,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Panel(
          title: 'Interfaz',
          children: [
            const Text('Tema'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ThemeMode.values
                  .map(
                    (mode) => ChoiceChip(
                      label: Text(_themeLabel(mode)),
                      selected: controller.settings.themeMode == mode,
                      onSelected: (_) => controller.updateThemeMode(mode),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            const Text('Tamano de botones'),
            const SizedBox(height: 8),
            SegmentedButton<SoundButtonSize>(
              segments: const [
                ButtonSegment(value: SoundButtonSize.small, label: Text('Pequeno')),
                ButtonSegment(value: SoundButtonSize.medium, label: Text('Mediano')),
                ButtonSegment(value: SoundButtonSize.large, label: Text('Grande')),
              ],
              selected: {controller.settings.buttonSize},
              onSelectionChanged: (value) => controller.updateButtonSize(value.first),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Panel(
          title: 'Controles fisicos',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activar controles fisicos'),
              subtitle: Text(controller.settings.physicalControlsEnabled
                  ? controller.bannerMessage == null
                      ? 'Asignaciones activas para pruebas y futura integracion nativa.'
                      : controller.bannerMessage!
                  : 'Activalo para asignar y probar botones desde la app.'),
              value: controller.settings.physicalControlsEnabled,
              onChanged: controller.updatePhysicalControls,
            ),
            const SizedBox(height: 8),
            Text(
              controller.settings.physicalControlsEnabled
                  ? 'Con la app abierta, Volumen + y Volumen - ya pueden disparar sonidos. Las otras asignaciones siguen como prueba interna.'
                  : 'La captura del boton fisico real no estaba activa. Estas pruebas validan la asignacion dentro de la app.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ...PhysicalButtonType.values.map(
              (button) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _PhysicalButtonAssignment(
                  button: button,
                  selectedSoundId: controller.assignedSoundIdForButton(button),
                  sounds: controller.sounds,
                  onChanged: (soundId) =>
                      controller.assignPhysicalButtonSound(button, soundId),
                  onTest: () => controller.simulatePhysicalButton(button),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Panel(
          title: 'Segundo plano',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Servicio persistente'),
              subtitle: const Text(
                'Mantiene auricular y shake activos con notificacion visible de reproduccion.',
              ),
              value: controller.settings.backgroundServiceEnabled,
              onChanged: controller.updateBackgroundServiceEnabled,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activar shake'),
              subtitle: const Text(
                'Escucha acelerometro desde el servicio para disparar un sonido por agitacion.',
              ),
              value: controller.settings.shakeEnabled,
              onChanged: controller.settings.backgroundServiceEnabled
                  ? controller.updateShakeEnabled
                  : null,
            ),
            _StatusTile(
              title: 'Notificaciones',
              value: controller.notificationPermissionGranted
                  ? 'Permitidas'
                  : 'Pendientes',
              actionLabel: controller.notificationPermissionGranted
                  ? 'Listo'
                  : 'Permitir',
              onPressed: controller.notificationPermissionGranted
                  ? null
                  : () async {
                      await controller.requestNotificationPermission();
                    },
            ),
            _StatusTile(
              title: 'Bateria',
              value: controller.batteryOptimizationIgnored
                  ? 'Excluida'
                  : 'Optimizacion activa',
              actionLabel: controller.batteryOptimizationIgnored
                  ? 'Listo'
                  : 'Excluir',
              onPressed: controller.batteryOptimizationIgnored
                  ? null
                  : () async {
                      await controller.requestBatteryOptimizationExemption();
                    },
            ),
            const SizedBox(height: 10),
            _SoundAssignmentField(
              title: 'Boton multimedia del auricular',
              description: 'Responde a play, pause, siguiente y anterior cuando el servicio esta activo.',
              selectedSoundId:
                  controller.assignedSoundIdForButton(PhysicalButtonType.headset),
              sounds: controller.sounds,
              onChanged: (soundId) =>
                  controller.assignPhysicalButtonSound(PhysicalButtonType.headset, soundId),
            ),
            const SizedBox(height: 14),
            _SoundAssignmentField(
              title: 'Notificacion: Sonido 1',
              description: 'Boton en la notificacion para disparar un sonido con el telefono bloqueado.',
              selectedSoundId: controller.notificationSound1AssignedId(),
              sounds: controller.sounds,
              onChanged: controller.assignNotificationSound1,
            ),
            const SizedBox(height: 14),
            _SoundAssignmentField(
              title: 'Notificacion: Sonido 2',
              description: 'Segundo boton en la notificacion para disparar otro sonido con el telefono bloqueado.',
              selectedSoundId: controller.notificationSound2AssignedId(),
              sounds: controller.sounds,
              onChanged: controller.assignNotificationSound2,
            ),
            const SizedBox(height: 14),
            _SoundAssignmentField(
              title: 'Agitacion',
              description: 'Usa el acelerometro en segundo plano mientras el servicio esta activo.',
              selectedSoundId: controller.shakeAssignedSoundId(),
              sounds: controller.sounds,
              onChanged: controller.assignShakeSound,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Panel(
          title: 'Datos locales',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Audios personalizados'),
              trailing: Text('${controller.customSoundCount}/${controller.settings.maxCustomSounds}'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Almacenamiento usado'),
              trailing: Text(controller.formatStorageUsage()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Historial reciente'),
              trailing: Text('${controller.historySounds.length}'),
            ),
            Wrap(
              spacing: 10,
              children: [
                OutlinedButton(
                  onPressed: controller.clearHistory,
                  child: const Text('Limpiar historial'),
                ),
                FilledButton(
                  onPressed: controller.resetSettings,
                  child: const Text('Restablecer'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Claro';
      case ThemeMode.dark:
        return 'Oscuro';
      case ThemeMode.system:
        return 'Auto';
    }
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.title,
    required this.value,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final String value;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(value),
      trailing: FilledButton.tonal(
        onPressed: onPressed,
        child: Text(actionLabel),
      ),
    );
  }
}

class _SoundAssignmentField extends StatelessWidget {
  const _SoundAssignmentField({
    required this.title,
    required this.description,
    required this.selectedSoundId,
    required this.sounds,
    required this.onChanged,
  });

  final String title;
  final String description;
  final String? selectedSoundId;
  final List<Sound> sounds;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          initialValue: selectedSoundId,
          decoration: const InputDecoration(
            labelText: 'Sonido asignado',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Sin asignar'),
            ),
            ...sounds.map(
              (sound) => DropdownMenuItem<String?>(
                value: sound.id,
                child: Text(sound.name),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _PhysicalButtonAssignment extends StatelessWidget {
  const _PhysicalButtonAssignment({
    required this.button,
    required this.selectedSoundId,
    required this.sounds,
    required this.onChanged,
    required this.onTest,
  });

  final PhysicalButtonType button;
  final String? selectedSoundId;
  final List<Sound> sounds;
  final ValueChanged<String?> onChanged;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            button.label,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            button.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: selectedSoundId,
            decoration: const InputDecoration(
              labelText: 'Sonido asignado',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Sin asignar'),
              ),
              ...sounds.map(
                (sound) => DropdownMenuItem<String?>(
                  value: sound.id,
                  child: Text(sound.name),
                ),
              ),
            ],
            onChanged: onChanged,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onTest,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Probar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
