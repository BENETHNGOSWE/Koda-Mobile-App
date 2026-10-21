class UserEntity {
  final String id;
  final String email;
  final String phone;
  final String name;
  final String? avatarUrl;
  final DateTime? createdAt;
  final bool isVerified;

  const UserEntity({
    required this.id,
    required this.email,
    this.phone = '',
    required this.name,
    this.avatarUrl,
    this.createdAt,
    this.isVerified = false,
  });

  UserEntity copyWith({
    String? id,
    String? email,
    String? phone,
    String? name,
    String? avatarUrl,
    DateTime? createdAt,
    bool? isVerified,
  }) {
    return UserEntity(
      id: id ?? this.id,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      isVerified: isVerified ?? this.isVerified,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserEntity && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}