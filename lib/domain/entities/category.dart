class SoundCategory {
  const SoundCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.sortOrder,
    this.isSystem = false,
  });

  final String id;
  final String name;
  final String icon;
  final int sortOrder;
  final bool isSystem;

  SoundCategory copyWith({
    String? id,
    String? name,
    String? icon,
    int? sortOrder,
    bool? isSystem,
  }) {
    return SoundCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      isSystem: isSystem ?? this.isSystem,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'sort_order': sortOrder,
      'is_system': isSystem ? 1 : 0,
    };
  }

  factory SoundCategory.fromMap(Map<String, Object?> map) {
    return SoundCategory(
      id: map['id']! as String,
      name: map['name']! as String,
      icon: map['icon']! as String,
      sortOrder: map['sort_order']! as int,
      isSystem: (map['is_system'] as int? ?? 0) == 1,
    );
  }
}
