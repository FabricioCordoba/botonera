import 'package:flutter/material.dart';

enum SoundButtonSize { small, medium, large }
enum PhysicalButtonType { volumeUp, volumeDown, headset, lock }

extension PhysicalButtonTypeX on PhysicalButtonType {
  String get label {
    switch (this) {
      case PhysicalButtonType.volumeUp:
        return 'Volumen +';
      case PhysicalButtonType.volumeDown:
        return 'Volumen -';
      case PhysicalButtonType.headset:
        return 'Boton manos libres';
      case PhysicalButtonType.lock:
        return 'Boton de bloqueo';
    }
  }

  String get description {
    switch (this) {
      case PhysicalButtonType.volumeUp:
        return 'Ideal para lanzar un sonido rapido sin mirar la pantalla.';
      case PhysicalButtonType.volumeDown:
        return 'Sirve como segundo disparador fisico independiente.';
      case PhysicalButtonType.headset:
        return 'Pensado para auriculares o accesorios con boton multimedia.';
      case PhysicalButtonType.lock:
        return 'Reservado para una futura integracion nativa.';
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
    this.headsetSoundId,
    this.shakeSoundId,
    this.lockScreenSoundId,
    this.notificationSound1Id,
    this.notificationSound2Id,
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
  final String? headsetSoundId;
  final String? shakeSoundId;
  final String? lockScreenSoundId;
  final String? notificationSound1Id;
  final String? notificationSound2Id;
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
    Object? headsetSoundId = _unset,
    Object? shakeSoundId = _unset,
    Object? lockScreenSoundId = _unset,
    Object? notificationSound1Id = _unset,
    Object? notificationSound2Id = _unset,
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
      headsetSoundId: identical(headsetSoundId, _unset)
          ? this.headsetSoundId
          : headsetSoundId as String?,
      shakeSoundId: identical(shakeSoundId, _unset)
          ? this.shakeSoundId
          : shakeSoundId as String?,
      lockScreenSoundId: identical(lockScreenSoundId, _unset)
          ? this.lockScreenSoundId
          : lockScreenSoundId as String?,
      notificationSound1Id: identical(notificationSound1Id, _unset)
          ? this.notificationSound1Id
          : notificationSound1Id as String?,
      notificationSound2Id: identical(notificationSound2Id, _unset)
          ? this.notificationSound2Id
          : notificationSound2Id as String?,
      maxCustomSounds: maxCustomSounds ?? this.maxCustomSounds,
    );
  }
}
