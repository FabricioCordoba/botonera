import 'package:botonera/data/datasources/file_storage.dart';
import 'package:botonera/data/datasources/local_db.dart';
import 'package:botonera/domain/entities/app_settings.dart';
import 'package:botonera/domain/entities/category.dart';
import 'package:botonera/domain/entities/sound.dart';
import 'package:botonera/main.dart';
import 'package:botonera/presentation/providers/sound_provider.dart';
import 'package:botonera/services/audio_service.dart';
import 'package:botonera/services/hardware_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders dashboard shell', (WidgetTester tester) async {
    final fakeProvider = _FakeSoundProvider();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          soundboardProvider.overrideWith((ref) => fakeProvider),
        ],
        child: const SoundboardApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Soundboard Epico'), findsOneWidget);
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Config'), findsOneWidget);
    expect(find.text('Por defecto'), findsOneWidget);
    expect(find.text('BOCINA'), findsOneWidget);
  });
}

class _FakeSoundProvider extends SoundProvider {
  _FakeSoundProvider()
      : super(
          database: LocalDb(),
          fileStorage: FileStorage(),
          audioService: AudioService(),
          hardwareService: HardwareService(),
        ) {
    settings = const AppSettings();
    categories = const [
      SoundCategory(
        id: 'default',
        name: 'Por defecto',
        icon: '🎛',
        sortOrder: 0,
        isSystem: true,
      ),
      SoundCategory(
        id: 'custom',
        name: 'Personalizados',
        icon: '🎙',
        sortOrder: 1,
        isSystem: true,
      ),
    ];
    sounds = const [
      Sound(
        id: 'asset_bocina',
        name: 'BOCINA',
        emoji: '💥',
        colorValue: 0xFFF97316,
        categoryId: 'default',
        source: 'assets/sounds/bocina.mp3',
        isAsset: true,
        isDefault: true,
      ),
      Sound(
        id: 'campeon',
        name: 'CAMPEON x3',
        emoji: '🏆',
        colorValue: 0xFF7C3AED,
        categoryId: 'default',
        source: 'assets/sounds/encara_messi.mp3',
        isAsset: true,
        isDefault: true,
        isFavorite: true,
      ),
    ];
    selectedCategoryId = 'default';
    recentHistoryIds = const ['campeon'];
    isInitialized = true;
  }
}
