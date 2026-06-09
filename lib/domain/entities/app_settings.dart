import 'package:flutter/material.dart';

enum SoundButtonSize { small, medium, large }
enum PhysicalButtonType { volumeUp, volumeDown }

extension PhysicalButtonTypeX on PhysicalButtonType {
  String get label {
    switch (this) {
      case PhysicalButtonType.volumeUp:
        return 'Volumen +';
      case PhysicalButtonType.volumeDown:
        return 'Volumen -';
    }
  }

  String get description {
    switch (this) {
      case PhysicalButtonType.volumeUp:
        return 'Ideal para lanzar un sonido rapido sin mirar la pantalla.';
      case PhysicalButtonType.volumeDown:
        return 'Sirve como segundo disparador fisico independiente.';
    }
  }
}

const Object _unset = Object();

class AppSettings {
  const AppSettings({
    this.globalVolume = 1,
    this.vibrationEnabled = true,
    this.physicalControlsEnabled = false,
    this.backgroundServiceEnabled = false,
    this.shakeEnabled = false,
    this.themeMode = ThemeMode.system,
    this.buttonSize = SoundButtonSize.medium,
    this.localeCode = 'es',
    this.volumeUpSoundId,
    this.volumeDownSoundId,
    this.shakeSoundId,
    this.maxCustomSounds = 100,
  });

  final double globalVolume;
  final bool vibrationEnabled;
  final bool physicalControlsEnabled;
  final bool backgroundServiceEnabled;
  final bool shakeEnabled;
  final ThemeMode themeMode;
  final SoundButtonSize buttonSize;
  final String localeCode;
  final String? volumeUpSoundId;
  final String? volumeDownSoundId;
  final String? shakeSoundId;
  final int maxCustomSounds;

  AppSettings copyWith({
    double? globalVolume,
    bool? vibrationEnabled,
    bool? physicalControlsEnabled,
    bool? backgroundServiceEnabled,
    bool? shakeEnabled,
    ThemeMode? themeMode,
    SoundButtonSize? buttonSize,
    String? localeCode,
    Object? volumeUpSoundId = _unset,
    Object? volumeDownSoundId = _unset,
    Object? shakeSoundId = _unset,
    int? maxCustomSounds,
  }) {
    return AppSettings(
      globalVolume: globalVolume ?? this.globalVolume,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      physicalControlsEnabled:
          physicalControlsEnabled ?? this.physicalControlsEnabled,
      backgroundServiceEnabled:
          backgroundServiceEnabled ?? this.backgroundServiceEnabled,
      shakeEnabled: shakeEnabled ?? this.shakeEnabled,
      themeMode: themeMode ?? this.themeMode,
      buttonSize: buttonSize ?? this.buttonSize,
      localeCode: localeCode ?? this.localeCode,
      volumeUpSoundId: identical(volumeUpSoundId, _unset)
          ? this.volumeUpSoundId
          : volumeUpSoundId as String?,
      volumeDownSoundId: identical(volumeDownSoundId, _unset)
          ? this.volumeDownSoundId
          : volumeDownSoundId as String?,
      shakeSoundId: identical(shakeSoundId, _unset)
          ? this.shakeSoundId
          : shakeSoundId as String?,
      maxCustomSounds: maxCustomSounds ?? this.maxCustomSounds,
    );
  }
}
