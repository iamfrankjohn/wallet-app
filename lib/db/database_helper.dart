import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  static DatabaseHelper? _instance;
  static Database? _db;

  DatabaseHelper._();
  factory DatabaseHelper() => _instance ??= DatabaseHelper._();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    // Windows / Linux / macOS desktop needs FFI
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'wallet.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE entries (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        type        TEXT NOT NULL CHECK(type IN ('income','bill')),
        amount      REAL NOT NULL,
        entry_date  TEXT NOT NULL,
        cutoff_date TEXT NOT NULL DEFAULT '2000-01-01',
        description TEXT NOT NULL,
        status      TEXT NOT NULL DEFAULT 'paid' CHECK(status IN ('paid','pending')),
        source_ref  TEXT,
        created_at  TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE recurring (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT NOT NULL,
        type        TEXT NOT NULL DEFAULT 'bill' CHECK(type IN ('income','bill')),
        amount      REAL NOT NULL,
        pay_day     INTEGER NOT NULL,
        pay_day2    INTEGER,
        start_date  TEXT NOT NULL,
        end_date    TEXT,
        notes       TEXT,
        active      INTEGER NOT NULL DEFAULT 1,
        last_synced TEXT,
        created_at  TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE credit_accounts (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        name         TEXT NOT NULL,
        credit_limit REAL NOT NULL DEFAULT 0,
        balance      REAL NOT NULL DEFAULT 0,
        color        TEXT NOT NULL DEFAULT '#10B981',
        notes        TEXT,
        active       INTEGER NOT NULL DEFAULT 1,
        created_at   TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE credit_txns (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id       INTEGER NOT NULL,
        txn_type         TEXT NOT NULL CHECK(txn_type IN ('charge','payment','rebate','adjustment')),
        amount           REAL NOT NULL,
        txn_date         TEXT NOT NULL,
        description      TEXT NOT NULL,
        num_installments INTEGER NOT NULL DEFAULT 0,
        paid_date        TEXT,
        created_at       TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (account_id) REFERENCES credit_accounts(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE credit_installments (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        txn_id         INTEGER NOT NULL,
        installment_no INTEGER NOT NULL,
        amount         REAL NOT NULL,
        interest       REAL NOT NULL DEFAULT 0,
        adjustment     REAL NOT NULL DEFAULT 0,
        due_date       TEXT NOT NULL,
        paid_date      TEXT,
        created_at     TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (txn_id) REFERENCES credit_txns(id) ON DELETE CASCADE
      )
    ''');
  }

  // ─── ENTRIES ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getEntries() async {
    final db = await database;
    return db.query('entries', orderBy: 'cutoff_date DESC, entry_date DESC, created_at DESC');
  }

  Future<int> addEntry(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('entries', data);
  }

  Future<bool> deleteEntry(int id) async {
    final db = await database;
    final entry = await db.query('entries', where: 'id=?', whereArgs: [id]);
    if (entry.isEmpty) return false;
    if (isPreviousCutoffOrOlder(entry.first['cutoff_date'] as String)) return false;
    await db.delete('entries', where: 'id=?', whereArgs: [id]);
    return true;
  }

  Future<bool> toggleEntryStatus(int id, String newStatus) async {
    final db = await database;
    final entry = await db.query('entries', where: 'id=?', whereArgs: [id]);
    if (entry.isEmpty) return false;
    if (isPreviousCutoffOrOlder(entry.first['cutoff_date'] as String)) return false;
    await db.update('entries', {'status': newStatus}, where: 'id=?', whereArgs: [id]);

    // Sync credit installment if source_ref set
    final ref = entry.first['source_ref'] as String?;
    if (ref != null && ref.startsWith('credit:')) {
      final parts = ref.split(':');
      final txnId = int.tryParse(parts.length > 1 ? parts[1] : '');
      final instNo = parts.length > 2 ? int.tryParse(parts[2]) : null;
      if (txnId != null) {
        final paidDate = newStatus == 'paid' ? DateTime.now().toIso8601String().substring(0, 10) : null;
        if (instNo != null) {
          await db.update(
            'credit_installments',
            {'paid_date': paidDate},
            where: 'txn_id=? AND installment_no=?',
            whereArgs: [txnId, instNo],
          );
        } else {
          await db.update('credit_txns', {'paid_date': paidDate}, where: 'id=?', whereArgs: [txnId]);
        }
        await recalcAccountBalance(db, txnId);
      }
    }
    return true;
  }

  // ─── RECURRING ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getRecurring() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT r.*,
        COALESCE(SUM(CASE WHEN e.status='pending' THEN e.amount ELSE 0 END), 0) AS unpaid_total,
        COUNT(CASE WHEN e.status='pending' THEN 1 END) AS unpaid_count
      FROM recurring r
      LEFT JOIN entries e ON e.description = r.name AND e.type = r.type AND e.amount = r.amount
      GROUP BY r.id
      ORDER BY r.active DESC, r.name ASC
    ''');
    return rows;
  }

  Future<int> addRecurring(Map<String, dynamic> data) async {
    final db = await database;
    final id = await db.insert('recurring', data);
    final rec = (await db.query('recurring', where: 'id=?', whereArgs: [id])).first;
    await syncRecurring(db, rec);
    return id;
  }

  Future<void> toggleRecurring(int id, bool active) async {
    final db = await database;
    await db.update('recurring', {'active': active ? 1 : 0}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> deleteRecurring(int id) async {
    final db = await database;
    final rec = await db.query('recurring', where: 'id=?', whereArgs: [id]);
    if (rec.isNotEmpty) {
      final r = rec.first;
      await db.delete('entries',
          where: 'description=? AND type=? AND amount=? AND status=?',
          whereArgs: [r['name'], r['type'], r['amount'], 'pending']);
    }
    await db.delete('recurring', where: 'id=?', whereArgs: [id]);
  }

  Future<int> syncRecurring(Database db, Map<String, dynamic> rec) async {
    int inserted = 0;
    final dates = _payDates(rec);
    for (final payDate in dates) {
      final cutoff = cutoffForDate(payDate);
      final label = rec['name'] as String;
      final type = rec['type'] as String;
      final amt = (rec['amount'] as num).toDouble();

      final existing = await db.query('entries',
          where: 'description=? AND entry_date=? AND type=? AND amount=?',
          whereArgs: [label, payDate, type, amt]);
      if (existing.isNotEmpty) {
        final ex = existing.first;
        if (ex['cutoff_date'] != cutoff) {
          await db.update('entries', {'cutoff_date': cutoff},
              where: 'id=?', whereArgs: [ex['id']]);
        }
      } else {
        await db.insert('entries', {
          'type': type,
          'amount': amt,
          'entry_date': payDate,
          'cutoff_date': cutoff,
          'description': label,
          'status': 'pending',
        });
        inserted++;
      }
    }
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await db.update('recurring', {'last_synced': today},
        where: 'id=?', whereArgs: [rec['id']]);
    return inserted;
  }

  Future<int> syncRecurringById(int id) async {
    final db = await database;
    final rows = await db.query('recurring', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) return 0;
    return syncRecurring(db, rows.first);
  }

  Future<int> syncAllRecurring() async {
    final db = await database;
    final rows = await db.query('recurring', where: 'active=1');
    int total = 0;
    for (final r in rows) {
      total += await syncRecurring(db, r);
    }
    return total;
  }

  // ─── CREDIT ACCOUNTS ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCreditAccounts() async {
    final db = await database;
    // Recalc balances first
    final accounts = await db.query('credit_accounts');
    for (final acc in accounts) {
      await recalcAccountBalance(db, null, accountId: acc['id'] as int);
    }
    return db.rawQuery('''
      SELECT a.*,
        COALESCE(SUM(CASE WHEN t.txn_type='charge' THEN t.amount ELSE 0 END),0) AS total_charges,
        COALESCE(SUM(CASE WHEN t.txn_type IN ('payment','rebate') THEN t.amount ELSE 0 END),0) AS total_payments
      FROM credit_accounts a
      LEFT JOIN credit_txns t ON t.account_id = a.id
      GROUP BY a.id
      ORDER BY a.active DESC, a.name ASC
    ''');
  }

  Future<int> addCreditAccount(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('credit_accounts', data);
  }

  Future<void> editCreditAccount(int id, Map<String, dynamic> data) async {
    final db = await database;
    await db.update('credit_accounts', data, where: 'id=?', whereArgs: [id]);
  }

  Future<void> deleteCreditAccount(int id) async {
    final db = await database;
    // Remove mirrored entries
    final txns = await db.query('credit_txns', where: 'account_id=?', whereArgs: [id]);
    for (final t in txns) {
      await db.delete('entries',
          where: "source_ref LIKE 'credit:${t['id']}%'");
    }
    await db.delete('credit_accounts', where: 'id=?', whereArgs: [id]);
  }

  // ─── CREDIT TRANSACTIONS ─────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCreditTxns(int accountId) async {
    final db = await database;
    return db.query('credit_txns',
        where: 'account_id=?', whereArgs: [accountId], orderBy: 'txn_date DESC');
  }

  Future<List<Map<String, dynamic>>> getCreditInstallments(int txnId) async {
    final db = await database;
    return db.query('credit_installments',
        where: 'txn_id=?', whereArgs: [txnId], orderBy: 'installment_no ASC');
  }

  Future<int> addCreditTxn(Map<String, dynamic> data) async {
    final db = await database;
    final accountId = data['account_id'] as int;
    final txnType = data['txn_type'] as String;
    final amount = (data['amount'] as num).toDouble();
    final txnDate = data['txn_date'] as String;
    final description = data['description'] as String;
    final numInstallments = (data['num_installments'] ?? 0) as int;

    final txnId = await db.insert('credit_txns', {
      'account_id': accountId,
      'txn_type': txnType,
      'amount': amount,
      'txn_date': txnDate,
      'description': description,
      'num_installments': numInstallments,
    });

    if (txnType == 'charge') {
      if (numInstallments > 1) {
        // Create installments
        final monthly = amount / numInstallments;
        final startDt = DateTime.parse(txnDate);
        for (int i = 0; i < numInstallments; i++) {
          final dueDate = DateTime(startDt.year, startDt.month + i, startDt.day);
          final dueDateStr = dueDate.toIso8601String().substring(0, 10);
          final cutoff = cutoffForDate(dueDateStr);
          await db.insert('credit_installments', {
            'txn_id': txnId,
            'installment_no': i + 1,
            'amount': monthly,
            'interest': 0,
            'due_date': dueDateStr,
          });
          // Mirror to entries
          await db.insert('entries', {
            'type': 'bill',
            'amount': monthly,
            'entry_date': dueDateStr,
            'cutoff_date': cutoff,
            'description': '$description (${i + 1}/$numInstallments)',
            'status': 'pending',
            'source_ref': 'credit:$txnId:${i + 1}',
          });
        }
      } else {
        // Single charge — mirror as one bill entry
        final cutoff = cutoffForDate(txnDate);
        await db.insert('entries', {
          'type': 'bill',
          'amount': amount,
          'entry_date': txnDate,
          'cutoff_date': cutoff,
          'description': description,
          'status': 'pending',
          'source_ref': 'credit:$txnId',
        });
      }
    }

    await recalcAccountBalance(db, txnId, accountId: accountId);
    return txnId;
  }

  Future<void> deleteCreditTxn(int txnId) async {
    final db = await database;
    final txn = await db.query('credit_txns', where: 'id=?', whereArgs: [txnId]);
    if (txn.isEmpty) return;
    final accountId = txn.first['account_id'] as int;
    // Remove mirrored entries
    await db.delete('entries', where: "source_ref LIKE 'credit:$txnId%'");
    await db.delete('credit_txns', where: 'id=?', whereArgs: [txnId]);
    await recalcAccountBalance(db, null, accountId: accountId);
  }

  Future<void> recalcAccountBalance(Database db, int? txnId, {int? accountId}) async {
    int? accId = accountId;
    if (accId == null && txnId != null) {
      final txn = await db.query('credit_txns', where: 'id=?', whereArgs: [txnId]);
      if (txn.isEmpty) return;
      accId = txn.first['account_id'] as int;
    }
    if (accId == null) return;

    final txns = await db.query('credit_txns', where: 'account_id=?', whereArgs: [accId]);
    double balance = 0;
    for (final t in txns) {
      final type = t['txn_type'] as String;
      final amt = (t['amount'] as num).toDouble();
      final numInst = (t['num_installments'] ?? 0) as int;
      if (type == 'payment' || type == 'rebate') {
        balance -= amt;
      } else if (type == 'charge') {
        if (numInst > 0) {
          final insts = await db.query('credit_installments',
              where: 'txn_id=? AND paid_date IS NULL', whereArgs: [t['id']]);
          for (final inst in insts) {
            final iAmt = (inst['amount'] as num).toDouble();
            final iInt = (inst['interest'] as num? ?? 0).toDouble();
            balance += iAmt - iInt;
          }
        } else if (t['paid_date'] == null) {
          balance += amt;
        }
      }
    }
    await db.update('credit_accounts', {'balance': balance},
        where: 'id=?', whereArgs: [accId]);
  }

  // ─── HELPER FUNCTIONS ─────────────────────────────────────────────────────

  static String cutoffForDate(String date) {
    final dt = DateTime.parse(date);
    final d = dt.day;
    final y = dt.year;
    final m = dt.month;
    if (d >= 5 && d <= 19) return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-05';
    if (d >= 20) return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-20';
    // days 1-4: previous month 20th
    final pm = m == 1 ? 12 : m - 1;
    final py = m == 1 ? y - 1 : y;
    return '${py.toString().padLeft(4, '0')}-${pm.toString().padLeft(2, '0')}-20';
  }

  static String prevCutoff(String cutoff) {
    final dt = DateTime.parse(cutoff);
    if (dt.day == 20) {
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-05';
    }
    final pm = dt.month == 1 ? 12 : dt.month - 1;
    final py = dt.month == 1 ? dt.year - 1 : dt.year;
    return '${py.toString().padLeft(4, '0')}-${pm.toString().padLeft(2, '0')}-20';
  }

  static bool isPreviousCutoffOrOlder(String entryCutoff) {
    final today = DateTime.now();
    final d = today.day;
    final y = today.year;
    final m = today.month;
    late String currentCutoff;
    if (d >= 5 && d <= 19) {
      currentCutoff = '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-05';
    } else if (d >= 20) {
      currentCutoff = '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-20';
    } else {
      final pm = m == 1 ? 12 : m - 1;
      final py = m == 1 ? y - 1 : y;
      currentCutoff = '${py.toString().padLeft(4, '0')}-${pm.toString().padLeft(2, '0')}-20';
    }
    final previousCutoff = prevCutoff(currentCutoff);
    return entryCutoff.compareTo(previousCutoff) <= 0;
  }

  static List<String> _payDates(Map<String, dynamic> rec) {
    final days = [rec['pay_day'] as int];
    if (rec['pay_day2'] != null) days.add(rec['pay_day2'] as int);
    days.sort();
    final start = DateTime.parse(rec['start_date'] as String);
    final endRaw = rec['end_date'] as String?;
    final end = endRaw != null ? DateTime.parse(endRaw) : DateTime.now().add(const Duration(days: 730));
    final limit = endRaw != null ? end : DateTime.now().add(const Duration(days: 60));

    final dates = <String>[];
    var curY = start.year;
    var curM = start.month;

    outer:
    while (true) {
      for (final pd in days) {
        final lastDay = DateTime(curY, curM + 1, 0).day;
        final d = pd > lastDay ? lastDay : pd;
        final dt = DateTime(curY, curM, d);
        if (dt.isBefore(start)) continue;
        if (dt.isAfter(limit)) break outer;
        dates.add(dt.toIso8601String().substring(0, 10));
      }
      curM++;
      if (curM > 12) {
        curM = 1;
        curY++;
      }
      if (DateTime(curY, curM, 1).isAfter(end.add(const Duration(days: 90)))) break;
    }
    return dates;
  }
}