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

  // FIX #3 #5: Logging and search debounce
  Timer? _searchDebounce;

  // FIX #6: Category count cache
  final Map<String, int> _soundCountByCategory = {};

  // FIX #3: Centralized logging helpers
  void _logError(String msg, [Object? err, StackTrace? st]) {
    if (kDebugMode) {
      debugPrint('❌ $msg');
      if (err != null) debugPrint('   → $err');
      if (st != null) debugPrintStack(stackTrace: st);
    }
  }

  void _logWarning(String msg) {
    if (kDebugMode) debugPrint('⚠️ $msg');
  }

  void _logInfo(String msg) {
    if (kDebugMode) debugPrint('ℹ️ $msg');
  }

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
  static const String _prefsShakeSound = 'background_shake_sound_id';
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
    filtered.sort((a, b) {
      if (a.isDefault != b.isDefault) {
        return a.isDefault ? 1 : -1;
      }
      return a.name.compareTo(b.name);
    });
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
        sounds: const [],
      );
      await _loadSettings();
      recentHistoryIds = await _readHistory();
      await _syncSoundLibraryFromStorage();
      categories = await _database.getCategories();
      sounds = await _database.getSounds();
      
      // FIX #6: Initialize category count cache
      await _updateCategoryCounts();
      
      selectedCategoryId = categories.isEmpty ? null : categories.first.id;
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
      _logInfo('SoundProvider initialized successfully');
      notifyListeners();
    } catch (e, st) {
      _logError('Error initializing provider', e, st);
      showError(
        'No pude inicializar la app completa. Algunas funciones pueden estar limitadas.',
      );
      categories = _defaultCategories;
      try {
        sounds = await _discoverBundledSounds();

      } catch (_) {
        sounds = const [];
      }
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
        shakeSoundId: prefs.getString(_prefsShakeSound),
      );
      _logInfo('Settings loaded successfully');
    } on PlatformException catch (e) {
      _logError('Platform error loading settings: ${e.message}', e);
      settings = const AppSettings();
    } catch (e, st) {
      _logError('Error loading settings', e, st);
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
        _prefsShakeSound,
        settings.shakeSoundId,
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
    // FIX #1: Stop playback first to avoid race condition
    await stopPlayback();
    
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
    } on PlatformException catch (e) {
      _logError('Audio platform error', e);
      showError('No pude reproducir "${sound.name}".');
      currentlyPlayingId = null;
      notifyListeners();
    } catch (e, st) {
      _logError('Error reproduciendo sonido', e, st);
      showError('Error inesperado.');
      currentlyPlayingId = null;
      notifyListeners();
    }
    // FIX #1: Don't clear here - let AudioPlayer notify completion
  }

  Future<void> stopPlayback() async {
    try {
      await _audioService.stopAll();
    } catch (e) {
      _logWarning('Error stopping playback: $e');
    }
    currentlyPlayingId = null;
    notifyListeners();
  }

  Future<void> _markSoundPlayed(Sound sound) async {
    try {
      final updated = sound.copyWith(
        playCount: sound.playCount + 1,
        lastPlayedAt: DateTime.now(),
      );
      await _database.upsertSound(updated);
      
      // FIX #7: Verify sound exists in memory list
      final index = sounds.indexWhere((s) => s.id == updated.id);
      if (index >= 0) {
        final newList = [...sounds];
        newList[index] = updated;
        sounds = newList;
      } else {
        // Sound not found - reload from DB
        _logWarning('Sound not found in memory after playing, reloading');
        sounds = await _database.getSounds();
      }
      
      recentHistoryIds = [
        updated.id,
        ...recentHistoryIds.where((id) => id != updated.id),
      ].take(10).toList();
      
      await _persistHistory();
      notifyListeners();
    } catch (e, st) {
      _logError('Error marking sound as played', e, st);
    }
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
    // FIX #5: Debounce search queries
    _searchDebounce?.cancel();
    
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      searchQuery = value;
      notifyListeners();
    });
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
    // FIX #10: Feedback cuando se intenta eliminar sonido por defecto
    if (sound.isDefault) {
      showError('No puedes eliminar audios por defecto.');
      return;
    }

    try {
      await _database.deleteSound(sound.id);
      await _fileStorage.deleteIfExists(sound.source);
      sounds = sounds.where((item) => item.id != sound.id).toList();
      recentHistoryIds = recentHistoryIds.where((id) => id != sound.id).toList();
      
      // FIX #6: Update category cache
      _soundCountByCategory[sound.categoryId] =
          (_soundCountByCategory[sound.categoryId] ?? 1) - 1;
      
      await _persistHistory();
      await _refreshStorageUsage();
      showSuccess('Audio "${sound.name}" eliminado.');
      notifyListeners();
    } catch (e, st) {
      _logError('Error eliminando sonido', e, st);
      showError('No pude eliminar el audio. Intenta de nuevo.');
    }
  }

  Future<void> importCustomSound() async {
    if (customSoundCount >= settings.maxCustomSounds) {
      showError(
        'Llegaste al límite de ${settings.maxCustomSounds} audios personalizados.',
      );
      return;
    }

    try {
      isBusy = true;
      notifyListeners();

      final imported = await _fileStorage.importAudioFile();
      if (imported == null) {
        return;
      }

      await _syncSoundLibraryFromStorage();
      categories = await _database.getCategories();
      sounds = await _database.getSounds();
      await _refreshStorageUsage();
      showSuccess('Audio "${imported.name}" importado correctamente.');
      notifyListeners();
    } catch (e, st) {
      _logError('Error importando sonido', e, st);
      showError('No pude importar el audio. Intenta de nuevo.');
    } finally {
      isBusy = false;
      notifyListeners();
    }
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

    if (path == null) {
      showError('Todavía no hay grabación para guardar.');
      return;
    }

    // FIX #4: Safe file existence check
    if (!isWebRecording) {
      try {
        final exists = await File(path).exists();
        if (!exists) {
          showError('El archivo de grabación ya no existe.');
          recordingPath = null;
          notifyListeners();
          return;
        }
      } catch (e) {
        _logError('Error verificando grabación', e);
        showError('Error al verificar la grabación.');
        return;
      }
    }

    // FIX #8: Input validation
    if (name.trim().isEmpty && emoji.isEmpty) {
      showError('Debes ingresar un nombre o emoji válido.');
      return;
    }

    try {
      final sound = Sound(
        id: _uuid.v4(),
        name: name.trim().isEmpty ? 'Nueva frase' : name.trim(),
        emoji: emoji.isEmpty ? '🎙' : emoji,
        colorValue: _validateColorValue(colorValue),
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
      
      // FIX #6: Update cache
      _soundCountByCategory[_customCategoryId] =
          (_soundCountByCategory[_customCategoryId] ?? 0) + 1;
      
      await _refreshStorageUsage();
      showSuccess('Audio guardado correctamente.');
      notifyListeners();
    } catch (e, st) {
      _logError('Error guardando grabación', e, st);
      showError('Error al guardar la grabación.');
    }
  }

  // FIX #8: Helper to validate color value
  int _validateColorValue(int value) {
    if (value < 0 || value > 0xFFFFFFFF) {
      return 0xFF7C3AED; // Default purple
    }
    return value;
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
    }
  }

  String? shakeAssignedSoundId() => settings.shakeSoundId;

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
    }
    await _persistSettings();
    await _syncBackgroundService(showFeedback: false);
    notifyListeners();
  }

  Future<void> assignShakeSound(String? soundId) async {
    settings = settings.copyWith(shakeSoundId: soundId);
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
      batteryOptimizationIgnored = true;
      return;
    }

    batteryOptimizationIgnored = await _hardwareService
        .isIgnoringBatteryOptimizations();
    volumeAccessibilityEnabled = await _hardwareService
        .isVolumeAccessibilityServiceEnabled();
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
        shakeSound == null) {
      await _hardwareService.stopBackgroundService();
      if (showFeedback) {
        showError(
          'Asigna un sonido a volumen o shake para usar segundo plano.',
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
    final shakePath = shakeSound == null
        ? null
        : await _fileStorage.ensurePlayableFilePath(shakeSound);

    await _hardwareService.startOrUpdateBackgroundService(
      volumeUpPath: volumeUpPath,
      volumeUpLabel: volumeUpSound?.name,
      volumeDownPath: volumeDownPath,
      volumeDownLabel: volumeDownSound?.name,
      mediaButtonPath: null,
      mediaButtonLabel: null,
      shakePath: shakePath,
      shakeLabel: shakeSound?.name,
      shakeEnabled: settings.shakeEnabled,
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

  Future<void> _syncSoundLibraryFromStorage() async {
    final discoveredSounds = [
      ...await _discoverBundledSounds(),
      ...await _discoverUserSounds(),
    ];
    final existingSounds = await _database.getSounds();
    final existingById = {for (final sound in existingSounds) sound.id: sound};
    final existingLocalBySource = {
      for (final sound in existingSounds.where((sound) => !sound.isAsset))
        sound.source: sound,
    };
    final activeIds = <String>{};

    for (final sound in discoveredSounds) {
      final existing = existingById[sound.id] ??
          (!sound.isAsset ? existingLocalBySource[sound.source] : null);
      final syncedSound = existing == null
          ? sound
          : sound.copyWith(
              id: existing.id,
              name: existing.isAsset ? sound.name : existing.name,
              emoji: existing.emoji,
              colorValue: existing.colorValue,
              isFavorite: existing.isFavorite,
              playCount: existing.playCount,
              lastPlayedAt: existing.lastPlayedAt,
              createdAt: existing.createdAt,
            );
      activeIds.add(syncedSound.id);
      await _database.upsertSound(
        syncedSound,
      );
    }

    for (final sound in existingSounds) {
      if (!activeIds.contains(sound.id)) {
        await _database.deleteSound(sound.id);
      }
    }

    recentHistoryIds = recentHistoryIds
        .where((soundId) => activeIds.contains(soundId))
        .toList();
    await _persistHistory();
    await _removeMissingAssignedSounds(activeIds);
  }

  Future<List<Sound>> _discoverBundledSounds() async {
    final manifest = await _loadAssetManifest();
    final paths = manifest
        .where((path) => path.startsWith('assets/sounds/'))
        .where(_fileStorage.isSupportedAudioPath)
        .toList()
      ..sort();

    return [
      for (var index = 0; index < paths.length; index++)
        _soundFromPath(
          source: paths[index],
          categoryId: _defaultCategoryId,
          isAsset: true,
          isDefault: true,
          sortIndex: index,
        ),
    ];
  }

  Future<Set<String>> _loadAssetManifest() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets().toSet();
  }

  Future<List<Sound>> _discoverUserSounds() async {
    final files = await _fileStorage.listLocalAudioFiles();
    return [
      for (var index = 0; index < files.length; index++)
        _soundFromPath(
          source: files[index].path,
          categoryId: _customCategoryId,
          isAsset: false,
          isDefault: false,
          sortIndex: index,
        ),
    ];
  }

  Sound _soundFromPath({
    required String source,
    required String categoryId,
    required bool isAsset,
    required bool isDefault,
    required int sortIndex,
  }) {
    final fileName = p.basenameWithoutExtension(source);
    final idPrefix = isAsset ? 'asset' : 'user';
    final id = '${idPrefix}_${_slugify(fileName)}';
    return Sound(
      id: id,
      name: _displayNameForFile(fileName),
      emoji: isAsset ? '🎵' : '🎙',
      colorValue: _colorForId(id),
      categoryId: categoryId,
      source: source,
      isAsset: isAsset,
      isDefault: isDefault,
      createdAt: DateTime.fromMillisecondsSinceEpoch(sortIndex),
    );
  }

  String _slugify(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return slug.isEmpty ? _uuid.v4() : slug;
  }

  String _displayNameForFile(String value) {
    return value
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toUpperCase();
  }

  int _colorForId(String id) {
    const colors = [
      0xFFF97316,
      0xFF7C3AED,
      0xFFEF4444,
      0xFF3B82F6,
      0xFF14B8A6,
      0xFFEAB308,
      0xFFEC4899,
      0xFF22C55E,
    ];
    return colors[id.hashCode.abs() % colors.length];
  }

  Future<void> _removeMissingAssignedSounds(Set<String> soundIds) async {
    var changed = false;
    if (settings.volumeUpSoundId != null &&
        !soundIds.contains(settings.volumeUpSoundId)) {
      settings = settings.copyWith(volumeUpSoundId: null);
      changed = true;
    }
    if (settings.volumeDownSoundId != null &&
        !soundIds.contains(settings.volumeDownSoundId)) {
      settings = settings.copyWith(volumeDownSoundId: null);
      changed = true;
    }
    if (settings.shakeSoundId != null &&
        !soundIds.contains(settings.shakeSoundId)) {
      settings = settings.copyWith(shakeSoundId: null);
      changed = true;
    }
    if (changed) {
      await _persistSettings();
    }
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

  // FIX #6: Update category count cache
  Future<void> _updateCategoryCounts() async {
    _soundCountByCategory.clear();
    for (final category in categories) {
      _soundCountByCategory[category.id] =
          sounds.where((s) => s.categoryId == category.id).length;
    }
  }

  // FIX #6: Get sound count for a category
  int getSoundCountForCategory(String categoryId) {
    return _soundCountByCategory[categoryId] ?? 0;
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
  Future<void> dispose() async {
    try {
      // FIX #2: Properly clean up resources
      await _audioService.stopAll();
      await _audioService.dispose();
      
      await _recorder.dispose();
      
      await _hardwareService.setEnabled(false);
      
      _errorTimer?.cancel();
      _searchDebounce?.cancel();
      
      _logInfo('SoundProvider disposed successfully');
      super.dispose();
    } catch (e, st) {
      _logError('Error in dispose', e, st);
      super.dispose();
    }
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

