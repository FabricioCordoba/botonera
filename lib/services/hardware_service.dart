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
      'Volumen + y Volumen - funcionan con la app abierta. En segundo plano, el servicio usa notificacion persistente, botones multimedia y shake.';

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

  Future<bool> isNotificationPermissionGranted() async {
    return await _channel.invokeMethod<bool>(
          'isNotificationPermissionGranted',
        ) ??
        true;
  }

  Future<bool> requestNotificationPermission() async {
    return await _channel.invokeMethod<bool>(
          'requestNotificationPermission',
        ) ??
        true;
  }

  Future<void> startOrUpdateBackgroundService({
    required String? mediaButtonPath,
    required String? mediaButtonLabel,
    required String? notification1Path,
    required String? notification1Label,
    required String? notification2Path,
    required String? notification2Label,
    required String? shakePath,
    required String? shakeLabel,
    required bool shakeEnabled,
  }) async {
    await _channel.invokeMethod<void>('startOrUpdateBackgroundService', {
      'mediaButtonPath': mediaButtonPath,
      'mediaButtonLabel': mediaButtonLabel,
      'notification1Path': notification1Path,
      'notification1Label': notification1Label,
      'notification2Path': notification2Path,
      'notification2Label': notification2Label,
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
      'headset' => PhysicalButtonType.headset,
      _ => null,
    };

    if (button != null) {
      await _onButtonPressed?.call(button);
    }
  }
}
