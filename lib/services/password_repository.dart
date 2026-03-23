import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart'
    if (dart.library.io) 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/password_item.dart';

class PasswordRepository {
  PasswordRepository();

  static const String _dbName = 'KeyRing.db';
  static const String _table = 'password_items';

  Database? _db;
  final ValueNotifier<List<PasswordItem>> itemsNotifier =
      ValueNotifier<List<PasswordItem>>(<PasswordItem>[]);

  Future<void> init() async {
    final String dbPath = await _resolveDbPath();
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            username TEXT NOT NULL,
            password TEXT NOT NULL,
            url TEXT,
            notes TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            isFavorite INTEGER NOT NULL DEFAULT 0
          );
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_${_table}_updatedAt ON $_table(updatedAt DESC)',
        );
      },
    );
    await _reloadItems();
  }

  Future<void> dispose() async {
    await _db?.close();
  }

  Future<void> _reloadItems() async {
    final List<Map<String, Object?>> rows = await _db!.query(
      _table,
      orderBy: 'isFavorite DESC, datetime(updatedAt) DESC',
    );
    final List<PasswordItem> items = rows
        .map((Map<String, Object?> row) => PasswordItem.fromMap(row))
        .toList();
    itemsNotifier.value = items;
  }

  Future<void> addItem(PasswordItem item) async {
    item.updatedAt = DateTime.now();
    await _db!.insert(
      _table,
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _reloadItems();
  }

  Future<void> updateItem(PasswordItem item) async {
    item.updatedAt = DateTime.now();
    await _db!.update(
      _table,
      item.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[item.id],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _reloadItems();
  }

  /// Check if a title already exists (case-insensitive). Optionally exclude one id.
  Future<bool> titleExists(String title, {String? exceptId}) async {
    final String where = exceptId == null
        ? 'LOWER(title) = LOWER(?)'
        : 'LOWER(title) = LOWER(?) AND id != ?';
    final List<Object?> whereArgs = exceptId == null
        ? <Object?>[title]
        : <Object?>[title, exceptId];
    final List<Map<String, Object?>> rows = await _db!.query(
      _table,
      columns: const <String>['id'],
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> removeItem(String id) async {
    await _db!.delete(_table, where: 'id = ?', whereArgs: <Object?>[id]);
    await _reloadItems();
  }

  Future<PasswordItem?> getByIdAsync(String id) async {
    final List<Map<String, Object?>> rows = await _db!.query(
      _table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (rows.isEmpty) return null;
    return PasswordItem.fromMap(rows.first);
  }

  PasswordItem? getById(String id) {
    throw UnimplementedError('Use getByIdAsync for SQLite backend');
  }

  /// Upsert an item coming from remote sync while preserving its timestamps.
  Future<void> upsertPreserveTimestamps(PasswordItem item) async {
    await _db!.insert(
      _table,
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _reloadItems();
  }

  Future<String> _resolveDbPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, _dbName);
  }
}
