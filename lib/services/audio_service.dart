import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../domain/entities/sound.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  double _volume = 1;

  Future<void> preload(Iterable<Sound> sounds) async {}

  Future<void> setGlobalVolume(double value) async {
    _volume = value.clamp(0, 1);
    await _player.setVolume(_volume);
    await _player.setReleaseMode(ReleaseMode.stop);
  }

  Future<void> play(Sound sound) async {
    await _player.stop();
    await _player.setVolume(_volume);

    final source = _buildSource(sound);
    await _player.play(source, volume: _volume, position: Duration.zero);
  }

  Future<void> stopAll() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }

  bool _isWebPlayableUrl(String source) {
    if (!kIsWeb) {
      return source.startsWith('blob:') || source.startsWith('data:');
    }

    return source.startsWith('blob:') ||
        source.startsWith('data:') ||
        source.startsWith('http');
  }

  Source _buildSource(Sound sound) {
    if (sound.isAsset) {
      return AssetSource(sound.source.replaceFirst('assets/', ''));
    }

    if (_isWebPlayableUrl(sound.source)) {
      return UrlSource(sound.source);
    }

    return DeviceFileSource(sound.source);
  }
}
