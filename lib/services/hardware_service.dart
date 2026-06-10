import '../domain/entities/app_settings.dart';
import 'package:flutter/services.dart';

class HardwareService {
  static const MethodChannel _channel = MethodChannel('botonera/hardware');
  Future<void> Function(PhysicalButtonType button)? _onButtonPressed;
  bool _isInitialized = false;

  Future<void> initialize({
    required Future<void> Function(PhysicalButtonType button) onButtonPressed,
  }) async {
    _onButtonPressed = onButtonPressed;
    if (_isInitialized) {
      return;
    }
    _channel.setMethodCallHandler(_handleMethodCall);
    _isInitialized = true;
  }

  String get availabilityMessage =>
      'Volumen +, Volumen - y shake pueden funcionar en segundo plano con el servicio persistente activo.';

  Future<void> simulatePress(PhysicalButtonType button) async {
    await _onButtonPressed?.call(button);
  }

  Future<void> setEnabled(bool enabled) async {
    await _channel.invokeMethod<void>('setInterceptEnabled', enabled);
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    return await _channel.invokeMethod<bool>(
          'isIgnoringBatteryOptimizations',
        ) ??
        false;
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    return await _channel.invokeMethod<bool>(
          'requestIgnoreBatteryOptimizations',
        ) ??
        false;
  }

  Future<bool> isVolumeAccessibilityServiceEnabled() async {
    return await _channel.invokeMethod<bool>(
          'isVolumeAccessibilityServiceEnabled',
        ) ??
        false;
  }

  Future<bool> requestVolumeAccessibilityService() async {
    return await _channel.invokeMethod<bool>(
          'requestVolumeAccessibilityService',
        ) ??
        false;
  }

  Future<void> startOrUpdateBackgroundService({
    required String? volumeUpPath,
    required String? volumeUpLabel,
    required String? volumeDownPath,
    required String? volumeDownLabel,
    required String? mediaButtonPath,
    required String? mediaButtonLabel,
    required String? shakePath,
    required String? shakeLabel,
    required bool shakeEnabled,
  }) async {
    await _channel.invokeMethod<void>('startOrUpdateBackgroundService', {
      'volumeUpPath': volumeUpPath,
      'volumeUpLabel': volumeUpLabel,
      'volumeDownPath': volumeDownPath,
      'volumeDownLabel': volumeDownLabel,
      'mediaButtonPath': mediaButtonPath,
      'mediaButtonLabel': mediaButtonLabel,
      'shakePath': shakePath,
      'shakeLabel': shakeLabel,
      'shakeEnabled': shakeEnabled,
    });
  }

  Future<void> stopBackgroundService() async {
    await _channel.invokeMethod<void>('stopBackgroundService');
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'buttonPressed') {
      return;
    }

    final buttonName = call.arguments as String?;
    final button = switch (buttonName) {
      'volume_up' => PhysicalButtonType.volumeUp,
      'volume_down' => PhysicalButtonType.volumeDown,
      _ => null,
    };

    if (button != null) {
      await _onButtonPressed?.call(button);
    }
  }
}
