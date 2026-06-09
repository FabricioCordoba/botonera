import 'package:flutter/material.dart';

class Sound {
  const Sound({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorValue,
    required this.categoryId,
    required this.source,
    required this.isAsset,
    required this.isDefault,
    this.isFavorite = false,
    this.durationMs,
    this.playCount = 0,
    this.lastPlayedAt,
    this.createdAt,
  });

  final String id;
  final String name;
  final String emoji;
  final int colorValue;
  final String categoryId;
  final String source;
  final bool isAsset;
  final bool isDefault;
  final bool isFavorite;
  final int? durationMs;
  final int playCount;
  final DateTime? lastPlayedAt;
  final DateTime? createdAt;

  Color get color => Color(colorValue);

  Sound copyWith({
    String? id,
    String? name,
    String? emoji,
    int? colorValue,
    String? categoryId,
    String? source,
    bool? isAsset,
    bool? isDefault,
    bool? isFavorite,
    int? durationMs,
    int? playCount,
    DateTime? lastPlayedAt,
    DateTime? createdAt,
  }) {
    return Sound(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      colorValue: colorValue ?? this.colorValue,
      categoryId: categoryId ?? this.categoryId,
      source: source ?? this.source,
      isAsset: isAsset ?? this.isAsset,
      isDefault: isDefault ?? this.isDefault,
      isFavorite: isFavorite ?? this.isFavorite,
      durationMs: durationMs ?? this.durationMs,
      playCount: playCount ?? this.playCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'emoji': emoji,
      'color_value': colorValue,
      'category_id': categoryId,
      'source': source,
      'is_asset': isAsset ? 1 : 0,
      'is_default': isDefault ? 1 : 0,
      'is_favorite': isFavorite ? 1 : 0,
      'duration_ms': durationMs,
      'play_count': playCount,
      'last_played_at': lastPlayedAt?.millisecondsSinceEpoch,
      'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
    };
  }

  factory Sound.fromMap(Map<String, Object?> map) {
    return Sound(
      id: map['id']! as String,
      name: map['name']! as String,
      emoji: map['emoji']! as String,
      colorValue: map['color_value']! as int,
      categoryId: map['category_id']! as String,
      source: map['source']! as String,
      isAsset: (map['is_asset']! as int) == 1,
      isDefault: (map['is_default']! as int) == 1,
      isFavorite: (map['is_favorite']! as int) == 1,
      durationMs: map['duration_ms'] as int?,
      playCount: (map['play_count'] as int?) ?? 0,
      lastPlayedAt: map['last_played_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['last_played_at']! as int),
      createdAt: map['created_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
    );
  }
}
