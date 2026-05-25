import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:vibration/vibration.dart';

import '../../data/datasources/file_storage.dart';
import '../../data/datasources/local_db.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/sound.dart';
import '../../services/audio_service.dart';
import '../../services/hardware_service.dart';

final soundboardProvider = ChangeNotifierProvider<SoundProvider>((ref) {
  final provider = SoundProvider(
    database: LocalDb(),
    fileStorage: FileStorage(),
    audioService: AudioService(),
    hardwareService: HardwareService(),
  );
  unawaited(provider.initialize());
  ref.onDispose(provider.dispose);
  return provider;
});

class SoundProvider extends ChangeNotifier {
  SoundProvider({
    required LocalDb database,
    required FileStorage fileStorage,
    required AudioService audioService,
    required HardwareService hardwareService,
  }) : _database = database,
       _fileStorage = fileStorage,
       _audioService = audioService,
       _hardwareService = hardwareService;

  final LocalDb _database;
  final FileStorage _fileStorage;
  final AudioService _audioService;
  final HardwareService _hardwareService;
  final AudioRecorder _recorder = AudioRecorder();
  final Uuid _uuid = const Uuid();

  static const String _prefsTheme = 'theme_mode';
  static const String _prefsVolume = 'global_volume';
  static const String _prefsVibration = 'vibration_enabled';
  static const String _prefsPhysical = 'physical_controls_enabled';
  static const String _prefsBackgroundService = 'background_service_enabled';
  static const String _prefsShakeEnabled = 'background_shake_enabled';
  static const String _prefsButtonSize = 'button_size';
  static const String _prefsLocale = 'locale_code';
  static const String _prefsVolumeUpSound = 'physical_volume_up_sound_id';
  static const String _prefsVolumeDownSound = 'physical_volume_down_sound_id';
  static const String _prefsHeadsetSound = 'physical_headset_sound_id';
  static const String _prefsShakeSound = 'background_shake_sound_id';
  static const String _prefsLockSound = 'lock_sound_id';
  static const String _prefsNotificationSound1 = 'notification_sound_1_id';
  static const String _prefsNotificationSound2 = 'notification_sound_2_id';
  static const String _prefsHistory = 'recent_history';

  bool isInitialized = false;
  bool isBusy = false;
  bool isRecording = false;
  String? recordingPath;
  String? recordingPreviewName;
  String? currentlyPlayingId;
  String? selectedCategoryId;
  String? bannerMessage;
  bool bannerIsError = false;
  String searchQuery = '';
  AppSettings settings = const AppSettings();
  List<SoundCategory> categories = const [];
  List<Sound> sounds = const [];
  List<String> recentHistoryIds = const [];
  int storageBytes = 0;
  Timer? _errorTimer;
  bool notificationPermissionGranted = true;
  bool batteryOptimizationIgnored = false;
  bool volumeAccessibilityEnabled = false;

  List<SoundCategory> get visibleCategories => categories;

  List<Sound> get favoriteSounds =>
      sounds.where((sound) => sound.isFavorite).take(8).toList();

  List<Sound> get currentCategorySounds {
    if (selectedCategoryId == null) {
      return const [];
    }

    final filtered = sounds.where((sound) {
      final matchesCategory = sound.categoryId == selectedCategoryId;
      final matchesSearch =
          searchQuery.isEmpty ||
          sound.name.toLowerCase().contains(searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();

    filtered.sort((a, b) {
      if (a.isFavorite != b.isFavorite) {
        return a.isFavorite ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    return filtered;
  }

  List<Sound> get allSoundsFiltered {
    final filtered = sounds.where((sound) {
      if (searchQuery.isEmpty) {
        return true;
      }
      return sound.name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();
    filtered.sort((a, b) => a.name.compareTo(b.name));
    return filtered;
  }

  List<Sound> get historySounds {
    final map = {for (final sound in sounds) sound.id: sound};
    return recentHistoryIds.map((id) => map[id]).whereType<Sound>().toList();
  }

  Sound? get lastPlayedSound =>
      historySounds.isEmpty ? null : historySounds.first;

  int get customSoundCount => sounds.where((sound) => !sound.isDefault).length;

  Future<void> initialize() async {
    if (isInitialized) {
      return;
    }

    try {
      await _database.init();
      await _database.seedDefaults(
        categories: _defaultCategories,
        sounds: _defaultSounds,
      );
      await _loadSettings();
      categories = await _database.getCategories();
      sounds = await _database.getSounds();
      selectedCategoryId = categories.isEmpty ? null : categories.first.id;
      recentHistoryIds = await _readHistory();
      await _audioService.preload(sounds);
      await _audioService.setGlobalVolume(settings.globalVolume);
      await _hardwareService.initialize(
        onButtonPressed: handlePhysicalButtonPress,
      );
      await _hardwareService.setEnabled(settings.physicalControlsEnabled);
      await _refreshAndroidCapabilities();
      await _syncBackgroundService(showFeedback: false);
      await _refreshStorageUsage();
      isInitialized = true;
      notifyListeners();
    } catch (_) {
      showError(
        'No pude inicializar la app completa. Algunas funciones pueden estar limitadas.',
      );
      categories = _defaultCategories;
      sounds = _defaultSounds;
      selectedCategoryId = categories.first.id;
      isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      settings = AppSettings(
        globalVolume: prefs.getDouble(_prefsVolume) ?? 1,
        vibrationEnabled: prefs.getBool(_prefsVibration) ?? true,
        physicalControlsEnabled: prefs.getBool(_prefsPhysical) ?? false,
        backgroundServiceEnabled:
            prefs.getBool(_prefsBackgroundService) ?? false,
        shakeEnabled: prefs.getBool(_prefsShakeEnabled) ?? false,
        themeMode: _themeModeFromString(prefs.getString(_prefsTheme)),
        buttonSize: _buttonSizeFromString(prefs.getString(_prefsButtonSize)),
        localeCode: prefs.getString(_prefsLocale) ?? 'es',
        volumeUpSoundId: prefs.getString(_prefsVolumeUpSound),
        volumeDownSoundId: prefs.getString(_prefsVolumeDownSound),
        headsetSoundId: prefs.getString(_prefsHeadsetSound),
        shakeSoundId: prefs.getString(_prefsShakeSound),
        lockScreenSoundId: prefs.getString(_prefsLockSound),
        notificationSound1Id: prefs.getString(_prefsNotificationSound1),
        notificationSound2Id: prefs.getString(_prefsNotificationSound2),
      );
    } catch (_) {
      settings = const AppSettings();
    }
  }

  Future<void> _persistSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsVolume, settings.globalVolume);
      await prefs.setBool(_prefsVibration, settings.vibrationEnabled);
      await prefs.setBool(_prefsPhysical, settings.physicalControlsEnabled);
      await prefs.setBool(
        _prefsBackgroundService,
        settings.backgroundServiceEnabled,
      );
      await prefs.setBool(_prefsShakeEnabled, settings.shakeEnabled);
      await prefs.setString(_prefsTheme, settings.themeMode.name);
      await prefs.setString(_prefsButtonSize, settings.buttonSize.name);
      await prefs.setString(_prefsLocale, settings.localeCode);
      await _persistNullableString(
        prefs,
        _prefsVolumeUpSound,
        settings.volumeUpSoundId,
      );
      await _persistNullableString(
        prefs,
        _prefsVolumeDownSound,
        settings.volumeDownSoundId,
      );
      await _persistNullableString(
        prefs,
        _prefsHeadsetSound,
        settings.headsetSoundId,
      );
      await _persistNullableString(
        prefs,
        _prefsShakeSound,
        settings.shakeSoundId,
      );
      await _persistNullableString(
        prefs,
        _prefsLockSound,
        settings.lockScreenSoundId,
      );
      await _persistNullableString(
        prefs,
        _prefsNotificationSound1,
        settings.notificationSound1Id,
      );
      await _persistNullableString(
        prefs,
        _prefsNotificationSound2,
        settings.notificationSound2Id,
      );
    } catch (_) {}
  }

  Future<void> _persistNullableString(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value == null) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, value);
  }

  Future<List<String>> _readHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_prefsHistory) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persistHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsHistory, recentHistoryIds);
    } catch (_) {}
  }

  Future<void> playSound(Sound sound) async {
    currentlyPlayingId = sound.id;
    notifyListeners();

    if (settings.vibrationEnabled) {
      HapticFeedback.selectionClick();
      try {
        if (await Vibration.hasVibrator()) {
          await Vibration.vibrate(duration: 30, amplitude: 40);
        }
      } catch (_) {}
    }

    try {
      clearBanner(notify: false);
      await _audioService.play(sound);
      await _markSoundPlayed(sound);
    } catch (_) {
      showError('No pude reproducir "${sound.name}".');
    } finally {
      currentlyPlayingId = null;
      notifyListeners();
    }
  }

  Future<void> stopPlayback() async {
    await _audioService.stopAll();
    currentlyPlayingId = null;
    notifyListeners();
  }

  Future<void> _markSoundPlayed(Sound sound) async {
    final updated = sound.copyWith(
      playCount: sound.playCount + 1,
      lastPlayedAt: DateTime.now(),
    );
    await _database.upsertSound(updated);
    sounds = sounds
        .map((item) => item.id == updated.id ? updated : item)
        .toList();
    recentHistoryIds = [
      updated.id,
      ...recentHistoryIds.where((id) => id != updated.id),
    ].take(10).toList();
    await _persistHistory();
  }

  Future<void> selectCategory(String categoryId) async {
    await stopPlayback();
    selectedCategoryId = categoryId;
    notifyListeners();
  }

  Future<void> nextCategory() async {
    if (categories.isEmpty || selectedCategoryId == null) {
      return;
    }

    await stopPlayback();
    final currentIndex = categories.indexWhere(
      (item) => item.id == selectedCategoryId,
    );
    final nextIndex = (currentIndex + 1) % categories.length;
    selectedCategoryId = categories[nextIndex].id;
    notifyListeners();
  }

  Future<void> previousCategory() async {
    if (categories.isEmpty || selectedCategoryId == null) {
      return;
    }

    await stopPlayback();
    final currentIndex = categories.indexWhere(
      (item) => item.id == selectedCategoryId,
    );
    final previousIndex = currentIndex == 0
        ? categories.length - 1
        : currentIndex - 1;
    selectedCategoryId = categories[previousIndex].id;
    notifyListeners();
  }

  void setSearchQuery(String value) {
    searchQuery = value;
    notifyListeners();
  }

  Future<void> toggleFavorite(Sound sound) async {
    final updated = sound.copyWith(isFavorite: !sound.isFavorite);
    await _database.upsertSound(updated);
    sounds = sounds
        .map((item) => item.id == sound.id ? updated : item)
        .toList();
    notifyListeners();
  }

  Future<void> updateSound(Sound updated) async {
    await _database.upsertSound(updated);
    sounds = sounds
        .map((item) => item.id == updated.id ? updated : item)
        .toList();
    await _refreshStorageUsage();
    notifyListeners();
  }

  Future<void> deleteSound(Sound sound) async {
    if (sound.isDefault) {
      return;
    }

    await _database.deleteSound(sound.id);
    await _fileStorage.deleteIfExists(sound.source);
    sounds = sounds.where((item) => item.id != sound.id).toList();
    recentHistoryIds = recentHistoryIds.where((id) => id != sound.id).toList();
    await _persistHistory();
    await _refreshStorageUsage();
    notifyListeners();
  }

  Future<void> importCustomSound() async {
    if (customSoundCount >= settings.maxCustomSounds) {
      showError(
        'Llegaste al limite de ${settings.maxCustomSounds} audios personalizados.',
      );
      return;
    }

    final imported = await _fileStorage.importAudioFile();
    if (imported == null) {
      return;
    }

    final sound = Sound(
      id: _uuid.v4(),
      name: p.basenameWithoutExtension(imported.name).replaceAll('_', ' '),
      emoji: '🎙',
      colorValue: const Color(0xFF3B82F6).toARGB32(),
      categoryId: _customCategoryId,
      source: imported.source,
      isAsset: false,
      isDefault: false,
      createdAt: DateTime.now(),
    );
    await _database.upsertSound(sound);
    sounds = [...sounds, sound];
    await _refreshStorageUsage();
    showSuccess('Audio importado correctamente.');
    notifyListeners();
  }

  Future<void> startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        showError('Necesito permiso de microfono para grabar.');
        return;
      }

      final filePath = kIsWeb
          ? 'recording_${DateTime.now().millisecondsSinceEpoch}.opus'
          : await _fileStorage.reserveRecordingPath(
              'recording_${DateTime.now().millisecondsSinceEpoch}.m4a',
            );

      await _recorder.start(
        RecordConfig(encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc),
        path: filePath,
      );
      recordingPath = filePath;
      isRecording = true;
      clearBanner(notify: false);
      notifyListeners();
    } catch (_) {
      showError('No pude iniciar la grabacion.');
    }
  }

  Future<void> stopRecording() async {
    try {
      final path = await _recorder.stop();
      recordingPath = path ?? recordingPath;
      isRecording = false;
      notifyListeners();
    } catch (_) {
      showError('No pude detener la grabacion.');
      isRecording = false;
      notifyListeners();
    }
  }

  Future<void> previewRecording() async {
    if (recordingPath == null) {
      return;
    }

    await playSound(
      Sound(
        id: 'preview',
        name: recordingPreviewName ?? 'Preview',
        emoji: '🎧',
        colorValue: const Color(0xFFF59E0B).toARGB32(),
        categoryId: _customCategoryId,
        source: recordingPath!,
        isAsset: false,
        isDefault: false,
      ),
    );
  }

  Future<void> saveRecording({
    required String name,
    required String emoji,
    required int colorValue,
  }) async {
    final path = recordingPath;
    final isWebRecording =
        kIsWeb &&
        path != null &&
        (path.startsWith('blob:') || path.startsWith('data:'));

    if (path == null || (!isWebRecording && !File(path).existsSync())) {
      showError('Todavia no hay grabacion para guardar.');
      return;
    }

    final sound = Sound(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? 'Nueva frase' : name.trim(),
      emoji: emoji,
      colorValue: colorValue,
      categoryId: _customCategoryId,
      source: path,
      isAsset: false,
      isDefault: false,
      createdAt: DateTime.now(),
    );
    await _database.upsertSound(sound);
    sounds = [...sounds, sound];
    recordingPath = null;
    recordingPreviewName = null;
    await _refreshStorageUsage();
    showSuccess('Audio guardado correctamente.');
    notifyListeners();
  }

  Future<void> clearHistory() async {
    recentHistoryIds = const [];
    await _persistHistory();
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    settings = settings.copyWith(themeMode: mode);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updateButtonSize(SoundButtonSize size) async {
    settings = settings.copyWith(buttonSize: size);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updateGlobalVolume(double volume) async {
    settings = settings.copyWith(globalVolume: volume);
    await _persistSettings();
    await _audioService.setGlobalVolume(volume);
    notifyListeners();
  }

  Future<void> updateVibration(bool enabled) async {
    settings = settings.copyWith(vibrationEnabled: enabled);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updatePhysicalControls(bool enabled) async {
    settings = settings.copyWith(physicalControlsEnabled: enabled);
    await _persistSettings();
    await _hardwareService.setEnabled(enabled);
    notifyListeners();
  }

  Future<void> updateBackgroundServiceEnabled(bool enabled) async {
    settings = settings.copyWith(backgroundServiceEnabled: enabled);
    await _persistSettings();
    await _syncBackgroundService();
    notifyListeners();
  }

  Future<void> updateShakeEnabled(bool enabled) async {
    settings = settings.copyWith(shakeEnabled: enabled);
    await _persistSettings();
    await _syncBackgroundService();
    notifyListeners();
  }

  String? assignedSoundIdForButton(PhysicalButtonType button) {
    switch (button) {
      case PhysicalButtonType.volumeUp:
        return settings.volumeUpSoundId;
      case PhysicalButtonType.volumeDown:
        return settings.volumeDownSoundId;
      case PhysicalButtonType.headset:
        return settings.headsetSoundId;
      case PhysicalButtonType.lock:
        return settings.lockScreenSoundId;
    }
  }

  String? shakeAssignedSoundId() => settings.shakeSoundId;

  String? notificationSound1AssignedId() => settings.notificationSound1Id;
  String? notificationSound2AssignedId() => settings.notificationSound2Id;

  Sound? assignedSoundForButton(PhysicalButtonType button) {
    final soundId = assignedSoundIdForButton(button);
    if (soundId == null) {
      return null;
    }
    for (final sound in sounds) {
      if (sound.id == soundId) {
        return sound;
      }
    }
    return null;
  }

  Future<void> assignPhysicalButtonSound(
    PhysicalButtonType button,
    String? soundId,
  ) async {
    switch (button) {
      case PhysicalButtonType.volumeUp:
        settings = settings.copyWith(volumeUpSoundId: soundId);
        break;
      case PhysicalButtonType.volumeDown:
        settings = settings.copyWith(volumeDownSoundId: soundId);
        break;
      case PhysicalButtonType.headset:
        settings = settings.copyWith(headsetSoundId: soundId);
        break;
      case PhysicalButtonType.lock:
        settings = settings.copyWith(lockScreenSoundId: soundId);
        break;
    }
    await _persistSettings();
    await _syncBackgroundService(showFeedback: false);
    notifyListeners();
  }

  Future<void> assignLockScreenSound(String? soundId) async {
    await assignPhysicalButtonSound(PhysicalButtonType.lock, soundId);
  }

  Future<void> assignShakeSound(String? soundId) async {
    settings = settings.copyWith(shakeSoundId: soundId);
    await _persistSettings();
    await _syncBackgroundService(showFeedback: false);
    notifyListeners();
  }

  Future<void> assignNotificationSound1(String? soundId) async {
    settings = settings.copyWith(notificationSound1Id: soundId);
    await _persistSettings();
    await _syncBackgroundService(showFeedback: false);
    notifyListeners();
  }

  Future<void> assignNotificationSound2(String? soundId) async {
    settings = settings.copyWith(notificationSound2Id: soundId);
    await _persistSettings();
    await _syncBackgroundService(showFeedback: false);
    notifyListeners();
  }

  Future<void> handlePhysicalButtonPress(PhysicalButtonType button) async {
    if (!settings.physicalControlsEnabled) {
      showError('Activa los controles fisicos para usar esta asignacion.');
      return;
    }

    final sound = assignedSoundForButton(button);
    if (sound == null) {
      showError(
        'No hay ningun sonido asignado a ${button.label.toLowerCase()}.',
      );
      return;
    }

    await playSound(sound);
  }

  Future<void> simulatePhysicalButton(PhysicalButtonType button) async {
    await _hardwareService.simulatePress(button);
  }

  Future<void> _refreshAndroidCapabilities() async {
    if (kIsWeb || !Platform.isAndroid) {
      notificationPermissionGranted = true;
      batteryOptimizationIgnored = true;
      return;
    }

    notificationPermissionGranted = await _hardwareService
        .isNotificationPermissionGranted();
    batteryOptimizationIgnored = await _hardwareService
        .isIgnoringBatteryOptimizations();
    volumeAccessibilityEnabled = await _hardwareService
        .isVolumeAccessibilityServiceEnabled();
  }

  Future<bool> requestNotificationPermission() async {
    if (kIsWeb || !Platform.isAndroid) {
      return true;
    }

    final granted = await _hardwareService.requestNotificationPermission();
    await _refreshAndroidCapabilities();
    notifyListeners();
    return granted;
  }

  Future<bool> requestBatteryOptimizationExemption() async {
    if (kIsWeb || !Platform.isAndroid) {
      return true;
    }

    final requested = await _hardwareService
        .requestIgnoreBatteryOptimizations();
    await _refreshAndroidCapabilities();
    notifyListeners();
    return requested;
  }

  Future<bool> requestVolumeAccessibilityService() async {
    if (kIsWeb || !Platform.isAndroid) {
      return true;
    }

    await _hardwareService.requestVolumeAccessibilityService();
    await _refreshAndroidCapabilities();
    notifyListeners();
    return volumeAccessibilityEnabled;
  }

  Future<void> _syncBackgroundService({bool showFeedback = true}) async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }

    if (!settings.backgroundServiceEnabled) {
      await _hardwareService.stopBackgroundService();
      return;
    }

    final volumeUpSound = assignedSoundForButton(PhysicalButtonType.volumeUp);
    final volumeDownSound = assignedSoundForButton(
      PhysicalButtonType.volumeDown,
    );
    final headsetSound = assignedSoundForButton(PhysicalButtonType.headset);
    Sound? shakeSound;
    if (settings.shakeEnabled && settings.shakeSoundId != null) {
      for (final sound in sounds) {
        if (sound.id == settings.shakeSoundId) {
          shakeSound = sound;
          break;
        }
      }
    }

    if (volumeUpSound == null &&
        volumeDownSound == null &&
        headsetSound == null &&
        shakeSound == null) {
      await _hardwareService.stopBackgroundService();
      if (showFeedback) {
        showError(
          'Asigna un sonido a volumen, auricular o shake para usar segundo plano.',
        );
      }
      return;
    }

    Sound? notifSound1;
    if (settings.notificationSound1Id != null) {
      for (final sound in sounds) {
        if (sound.id == settings.notificationSound1Id) {
          notifSound1 = sound;
          break;
        }
      }
    }

    Sound? notifSound2;
    if (settings.notificationSound2Id != null) {
      for (final sound in sounds) {
        if (sound.id == settings.notificationSound2Id) {
          notifSound2 = sound;
          break;
        }
      }
    }

    if (!notificationPermissionGranted) {
      if (showFeedback) {
        showError(
          'Hace falta permiso de notificaciones para iniciar el servicio.',
        );
      }
      return;
    }

    if ((volumeUpSound != null || volumeDownSound != null) &&
        !volumeAccessibilityEnabled) {
      if (showFeedback) {
        showError(
          'Activa el servicio de accesibilidad para usar Volumen + y Volumen - bloqueado.',
        );
      }
    }

    final volumeUpPath = volumeUpSound == null
        ? null
        : await _fileStorage.ensurePlayableFilePath(volumeUpSound);
    final volumeDownPath = volumeDownSound == null
        ? null
        : await _fileStorage.ensurePlayableFilePath(volumeDownSound);
    final mediaPath = headsetSound == null
        ? null
        : await _fileStorage.ensurePlayableFilePath(headsetSound);
    final shakePath = shakeSound == null
        ? null
        : await _fileStorage.ensurePlayableFilePath(shakeSound);
    final notif1Path = notifSound1 == null
        ? null
        : await _fileStorage.ensurePlayableFilePath(notifSound1);
    final notif2Path = notifSound2 == null
        ? null
        : await _fileStorage.ensurePlayableFilePath(notifSound2);

    await _hardwareService.startOrUpdateBackgroundService(
      volumeUpPath: volumeUpPath,
      volumeUpLabel: volumeUpSound?.name,
      volumeDownPath: volumeDownPath,
      volumeDownLabel: volumeDownSound?.name,
      mediaButtonPath: mediaPath,
      mediaButtonLabel: headsetSound?.name,
      shakePath: shakePath,
      shakeLabel: shakeSound?.name,
      shakeEnabled: settings.shakeEnabled,
      notification1Path: notif1Path,
      notification1Label: notifSound1?.name,
      notification2Path: notif2Path,
      notification2Label: notifSound2?.name,
    );
  }

  Future<void> resetSettings() async {
    settings = const AppSettings();
    await _persistSettings();
    await _audioService.setGlobalVolume(settings.globalVolume);
    await _hardwareService.setEnabled(settings.physicalControlsEnabled);
    await _syncBackgroundService(showFeedback: false);
    notifyListeners();
  }

  Future<void> _refreshStorageUsage() async {
    final customPaths = sounds
        .where((sound) => !sound.isAsset)
        .map((sound) => sound.source);
    storageBytes = await _fileStorage.computeStorageBytes(customPaths);
  }

  String formatStorageUsage() {
    final mb = storageBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(2)} MB';
  }

  String formatLastPlayed(Sound? sound) {
    if (sound?.lastPlayedAt == null) {
      return 'Todavia no reprodujiste nada.';
    }
    final diff = DateTime.now().difference(sound!.lastPlayedAt!);
    if (diff.inMinutes < 1) {
      return 'hace unos segundos';
    }
    if (diff.inHours < 1) {
      return 'hace ${diff.inMinutes} min';
    }
    return 'hace ${diff.inHours} h';
  }

  void showError(String message) {
    _errorTimer?.cancel();
    bannerMessage = message;
    bannerIsError = true;
    notifyListeners();
    _errorTimer = Timer(const Duration(seconds: 4), clearBanner);
  }

  void showSuccess(String message) {
    _errorTimer?.cancel();
    bannerMessage = message;
    bannerIsError = false;
    notifyListeners();
    _errorTimer = Timer(const Duration(seconds: 3), clearBanner);
  }

  void clearBanner({bool notify = true}) {
    _errorTimer?.cancel();
    _errorTimer = null;
    bannerMessage = null;
    bannerIsError = false;
    if (notify) {
      notifyListeners();
    }
  }

  ThemeMode _themeModeFromString(String? value) {
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  SoundButtonSize _buttonSizeFromString(String? value) {
    return SoundButtonSize.values.firstWhere(
      (size) => size.name == value,
      orElse: () => SoundButtonSize.medium,
    );
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    unawaited(_audioService.dispose());
    unawaited(_recorder.dispose());
    super.dispose();
  }
}

const String _defaultCategoryId = 'default';
const String _customCategoryId = 'custom';

const List<SoundCategory> _defaultCategories = [
  SoundCategory(
    id: _defaultCategoryId,
    name: 'Por defecto',
    icon: '🎛',
    sortOrder: 0,
    isSystem: true,
  ),
  SoundCategory(
    id: _customCategoryId,
    name: 'Personalizados',
    icon: '🎙',
    sortOrder: 1,
    isSystem: true,
  ),
];

const List<Sound> _defaultSounds = [
  Sound(
    id: 'penal_para_river',
    name: 'PENAL PARA RIVER',
    emoji: '💥',
    colorValue: 0xFFF97316,
    categoryId: _defaultCategoryId,
    source: 'assets/sounds/penal_para_river.mp3',
    isAsset: true,
    isDefault: true,
  ),
  Sound(
    id: 'encara_messi',
    name: 'ENCARA MESSI',
    emoji: '🏆',
    colorValue: 0xFF7C3AED,
    categoryId: _defaultCategoryId,
    source: 'assets/sounds/encara_messi.mp3',
    isAsset: true,
    isDefault: true,
  ),
  Sound(
    id: 'oh_no',
    name: 'OH NOOOO',
    emoji: '😱',
    colorValue: 0xFFEF4444,
    categoryId: _defaultCategoryId,
    source: 'assets/sounds/que_miras_bobo_messi.mp3',
    isAsset: true,
    isDefault: true,
  ),
  Sound(
    id: 'que_miras_bobo',
    name: 'QUE MIRAS BOBO..?',
    emoji: '🤦',
    colorValue: 0xFF3B82F6,
    categoryId: _defaultCategoryId,
    source: 'assets/sounds/que_miras_bobo_messi.mp3',
    isAsset: true,
    isDefault: true,
  ),
  Sound(
    id: 'silencio',
    name: 'Silencio incomodo',
    emoji: '😶',
    colorValue: 0xFF14B8A6,
    categoryId: _defaultCategoryId,
    source: 'assets/sounds/penal_para_river.mp3',
    isAsset: true,
    isDefault: true,
  ),
];
