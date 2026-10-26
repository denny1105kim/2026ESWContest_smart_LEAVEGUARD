import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';

import 'schema.dart';

class AppDatabase {
  Database? _db;

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('AppDatabase.open()을 먼저 호출해야 한다');
    }
    return database;
  }

  void open({String? path}) {
    if (_db != null) return;

    final file = path ?? _defaultPath();
    Directory(File(file).parent.path).createSync(recursive: true);

    sqlite_open.open.overrideFor(
        sqlite_open.OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
    final database = sqlite3.open(file);
    database.execute('PRAGMA foreign_keys = ON');
    database.execute(createSchemaSql);
    _migrate(database);

    database.execute(seedSql);

    _db = database;
  }

  // CREATE TABLE IF NOT EXISTS 는 있는 표를 바꾸지 않으니 예전 DB 에 나중에 생긴 열을 더한다
  static void _migrate(Database db) {
    void addColumn(String table, String column, String type) {
      final has = db.select('PRAGMA table_info($table)').any((r) => r['name'] == column);
      if (!has) db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }

    addColumn('members', 'pin_hash', 'TEXT');
    addColumn('members', 'pin_salt', 'TEXT');
    addColumn('belongings', 'thumbnail', 'BLOB');
    addColumn('belongings', 'hard_to_detect', 'INTEGER NOT NULL DEFAULT 0');
    addColumn('belongings', 'watch_box', 'TEXT');
    addColumn('belonging_views', 'source', "TEXT NOT NULL DEFAULT 'register'");
    db.execute('DROP TABLE IF EXISTS object_states');
    // 예전 행의 member_id 를 주인 표로 옮긴다
    db.execute('INSERT OR IGNORE INTO belonging_owners (belonging_id, member_id) SELECT id, member_id FROM belongings');
    addColumn('belonging_presence', 'taken_by', 'INTEGER REFERENCES members(id) ON DELETE SET NULL');
    db.execute('DROP TABLE IF EXISTS belonging_marks');
    addColumn('members', 'return_check', 'INTEGER NOT NULL DEFAULT 1');
    addColumn('members', 'onboarding', 'INTEGER NOT NULL DEFAULT 0');
  }

  void close() {
    _db?.dispose();
    _db = null;
  }

  // 보드에서 HOME 은 앱마다 주는 /data/profiles/0/appdata/<앱ID>/home
  String _defaultPath() => '${Platform.environment['HOME'] ?? '.'}/leaveguard.db';
}
