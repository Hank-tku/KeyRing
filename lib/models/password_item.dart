import 'package:uuid/uuid.dart';

class PasswordItem {
  PasswordItem({
    String? id,
    required this.title,
    required this.username,
    required this.password,
    this.url,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isFavorite = false,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  String username;
  String password;
  String? url;
  String? notes;
  DateTime createdAt;
  DateTime updatedAt;
  bool isFavorite;

  PasswordItem copyWith({
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isFavorite,
  }) {
    return PasswordItem(
      id: id,
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'username': username,
      'password': password,
      'url': url,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isFavorite': isFavorite ? 1 : 0, // Convert bool to int for SQLite
    };
  }

  static PasswordItem fromMap(Map map) {
    bool parseBool(dynamic v) {
      if (v is bool) return v;
      if (v is int) return v != 0;
      if (v is num) return v != 0;
      if (v is String) {
        final String s = v.toLowerCase();
        return s == 'true' || s == '1' || s == 'yes';
      }
      return false;
    }

    String? asString(dynamic v) => v?.toString();

    final String? createdAtStr = asString(map['createdAt']);
    final String? updatedAtStr = asString(map['updatedAt']);

    return PasswordItem(
      id: asString(map['id']),
      title: asString(map['title']) ?? '',
      username: asString(map['username']) ?? '',
      password: asString(map['password']) ?? '',
      url: asString(map['url']),
      notes: asString(map['notes']),
      createdAt: DateTime.tryParse(createdAtStr ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(updatedAtStr ?? '') ?? DateTime.now(),
      isFavorite: parseBool(map['isFavorite'] ?? false),
    );
  }
}
