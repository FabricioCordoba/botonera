import 'package:flutter/material.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/sound.dart';

class SoundButton extends StatelessWidget {
  const SoundButton({
    super.key,
    required this.sound,
    required this.buttonSize,
    required this.isPlaying,
    required this.onPressed,
    required this.onFavoriteToggle,
  });

  final Sound sound;
  final SoundButtonSize buttonSize;
  final bool isPlaying;
  final VoidCallback onPressed;
  final VoidCallback onFavoriteToggle;

  @override
  Widget build(BuildContext context) {
    final metrics = _metrics(buttonSize);
    final theme = Theme.of(context);
    final background = Color.alphaBlend(
      sound.color.withValues(alpha: isPlaying ? 0.26 : 0.18),
      theme.colorScheme.surface,
    );

    return Semantics(
      button: true,
      label: sound.name,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        scale: isPlaying ? 0.97 : 1,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isPlaying ? sound.color : sound.color.withValues(alpha: 0.25),
                width: isPlaying ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(sound.emoji, style: TextStyle(fontSize: metrics.emojiSize)),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: onFavoriteToggle,
                        icon: Icon(
                          sound.isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: sound.isFavorite ? Colors.pinkAccent : theme.colorScheme.onSurfaceVariant,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    sound.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: metrics.textSize,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: isPlaying ? 1 : 0.75,
                    child: Row(
                      children: [
                        Icon(
                          isPlaying ? Icons.graphic_eq : Icons.play_arrow_rounded,
                          size: 18,
                          color: sound.color,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isPlaying ? 'Sonando' : 'Tocar',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  _SoundButtonMetrics _metrics(SoundButtonSize size) {
    switch (size) {
      case SoundButtonSize.small:
        return const _SoundButtonMetrics(height: 122, emojiSize: 22, textSize: 14);
      case SoundButtonSize.large:
        return const _SoundButtonMetrics(height: 188, emojiSize: 30, textSize: 18);
      case SoundButtonSize.medium:
        return const _SoundButtonMetrics(height: 154, emojiSize: 26, textSize: 16);
    }
  }
}

class _SoundButtonMetrics {
  const _SoundButtonMetrics({
    required this.height,
    required this.emojiSize,
    required this.textSize,
  });

  final double height;
  final double emojiSize;
  final double textSize;
}
