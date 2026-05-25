import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/entities/category.dart';
import '../../domain/entities/sound.dart';

class LocalDb {
  Database? _db;
  bool _memoryOnly = false;
  final Map<String, SoundCategory> _memoryCategories = {};
  final Map<String, Sound> _memorySounds = {};

  Future<void> init() async {
    if (_db != null || _memoryOnly) {
      return;
    }

    try {
      final directory = await getApplicationSupportDirectory();
      final dbPath = p.join(directory.path, 'soundboard.db');
      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE categories(
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              icon TEXT NOT NULL,
              sort_order INTEGER NOT NULL,
              is_system INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE sounds(
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              emoji TEXT NOT NULL,
              color_value INTEGER NOT NULL,
              category_id TEXT NOT NULL,
              source TEXT NOT NULL,
              is_asset INTEGER NOT NULL,
              is_default INTEGER NOT NULL,
              is_favorite INTEGER NOT NULL DEFAULT 0,
              duration_ms INTEGER,
              play_count INTEGER NOT NULL DEFAULT 0,
              last_played_at INTEGER,
              created_at INTEGER NOT NULL
            )
          ''');
        },
      );
    } catch (_) {
      _memoryOnly = true;
    }
  }

  Future<void> seedDefaults({
    required List<SoundCategory> categories,
    required List<Sound> sounds,
  }) async {
    final existingCategories = await getCategories();
    if (existingCategories.isEmpty) {
      for (final category in categories) {
        await upsertCategory(category);
      }
    }

    final existingSounds = await getSounds();
    if (existingSounds.isEmpty) {
      for (final sound in sounds) {
        await upsertSound(sound);
      }
    }
  }

  Future<List<SoundCategory>> getCategories() async {
    if (_memoryOnly || _db == null) {
      return _memoryCategories.values.toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }

    final rows = await _db!.query('categories', orderBy: 'sort_order ASC');
    return rows.map(SoundCategory.fromMap).toList();
  }

  Future<List<Sound>> getSounds() async {
    if (_memoryOnly || _db == null) {
      return _memorySounds.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    }

    final rows = await _db!.query('sounds', orderBy: 'created_at ASC');
    return rows.map(Sound.fromMap).toList();
  }

  Future<void> upsertCategory(SoundCategory category) async {
    if (_memoryOnly || _db == null) {
      _memoryCategories[category.id] = category;
      return;
    }

    await _db!.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertSound(Sound sound) async {
    if (_memoryOnly || _db == null) {
      _memorySounds[sound.id] = sound;
      return;
    }

    await _db!.insert(
      'sounds',
      sound.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSound(String soundId) async {
    if (_memoryOnly || _db == null) {
      _memorySounds.remove(soundId);
      return;
    }

    await _db!.delete('sounds', where: 'id = ?', whereArgs: [soundId]);
  }
}
