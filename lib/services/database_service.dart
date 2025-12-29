import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/batch.dart' as models;
import '../models/scan_item.dart';
import '../models/scan_status.dart';
import '../utils/timezone_helper.dart';
import 'dart:io';

// 資料庫服務
class DatabaseService {
  static Database? _database;
  static const String _dbName = 'scan_app.db';
  static const int _dbVersion = 2;

  // 取得資料庫實例
  static Future<Database> get database async {
    // 檢查資料庫連線是否有效
    if (_database != null) {
      try {
        // 嘗試執行一個簡單的查詢來檢查連線是否有效
        await _database!.rawQuery('SELECT 1');
        return _database!;
      } catch (e) {
        // 連線失效，關閉並重新初始化
        try {
          await _database!.close();
        } catch (_) {
          // 忽略關閉錯誤
        }
        _database = null;
      }
    }
    _database = await _initDatabase();
    return _database!;
  }

  // 初始化資料庫
  static Future<Database> _initDatabase() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbDir = Directory(path.join(documentsDir.path, 'db'));
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }
      final dbPath = path.join(dbDir.path, _dbName);

      // 檢查資料庫檔案是否存在，如果存在則檢查權限
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        // 確保檔案可寫入
        try {
          // 嘗試開啟檔案以檢查權限
          final testFile = await dbFile.open(mode: FileMode.append);
          await testFile.close();
        } catch (e) {
          // 如果無法寫入，記錄錯誤但繼續嘗試開啟資料庫
          if (kDebugMode) {
            debugPrint('資料庫檔案權限檢查：$e');
          }
        }
      }

      return await openDatabase(
        dbPath,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        // 確保資料庫可以寫入
        readOnly: false,
        // 單一連線模式，避免並發問題
        singleInstance: true,
      );
    } catch (e) {
      debugPrint('初始化資料庫時發生錯誤：$e');
      rethrow;
    }
  }

  // 建立資料表
  static Future<void> _onCreate(Database db, int version) async {
    // batches 表
    await db.execute('''
      CREATE TABLE batches (
        id TEXT PRIMARY KEY,
        store_name TEXT NOT NULL,
        order_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        finished_at TEXT
      )
    ''');

    // scan_items 表
    await db.execute('''
      CREATE TABLE scan_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id TEXT NOT NULL,
        order_date TEXT NOT NULL,
        order_no TEXT NOT NULL,
        logistics_company TEXT,
        logistics_no TEXT NOT NULL,
        sheet_note TEXT,
        scan_status TEXT NOT NULL,
        scan_time TEXT,
        scan_note TEXT,
        UNIQUE(batch_id, logistics_no),
        FOREIGN KEY (batch_id) REFERENCES batches(id)
      )
    ''');

    // 建立索引
    await db.execute('CREATE INDEX idx_batch_id ON scan_items(batch_id)');
    await db.execute('CREATE INDEX idx_logistics_no ON scan_items(logistics_no)');
    await db.execute('CREATE INDEX idx_order_date ON batches(order_date)');
    
    // 非清單內記錄表
    await db.execute('''
      CREATE TABLE off_list_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        logistics_no TEXT NOT NULL UNIQUE,
        scan_time TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    
    // 建立索引
    await db.execute('CREATE INDEX idx_off_list_logistics_no ON off_list_records(logistics_no)');
    await db.execute('CREATE INDEX idx_off_list_scan_time ON off_list_records(scan_time)');
  }

  // 資料庫升級
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 從版本 1 升級到版本 2：添加非清單內記錄表
      await db.execute('''
        CREATE TABLE IF NOT EXISTS off_list_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          logistics_no TEXT NOT NULL UNIQUE,
          scan_time TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      
      await db.execute('CREATE INDEX IF NOT EXISTS idx_off_list_logistics_no ON off_list_records(logistics_no)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_off_list_scan_time ON off_list_records(scan_time)');
    }
  }

  // ========== Batch 操作 ==========

  // 插入或更新 Batch
  static Future<void> insertOrUpdateBatch(models.Batch batch) async {
    int retryCount = 0;
    const maxRetries = 3;
    
    while (retryCount < maxRetries) {
      try {
        // 每次操作前都重新取得資料庫連線（會自動檢查連線有效性）
        final db = await database;
        await db.insert(
          'batches',
          batch.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return; // 成功則返回
      } catch (e) {
        final errorStr = e.toString();
        // 如果發生唯讀錯誤或資料庫移動錯誤，強制重新初始化
        if (errorStr.contains('readonly') || 
            errorStr.contains('READONLY') || 
            errorStr.contains('READONLY_DBMOVED') ||
            errorStr.contains('1032')) {
          retryCount++;
          // 強制清除連線並重新初始化
          if (_database != null) {
            try {
              await _database!.close();
            } catch (_) {
              // 忽略關閉錯誤
            }
          }
          _database = null;
          
          // 等待一下再重試
          if (retryCount < maxRetries) {
            await Future.delayed(Duration(milliseconds: 100 * retryCount));
            continue;
          }
        }
        // 其他錯誤或重試次數用完，拋出異常
        rethrow;
      }
    }
  }

  // 取得 Batch
  static Future<models.Batch?> getBatch(String batchId) async {
    final db = await database;
    final maps = await db.query(
      'batches',
      where: 'id = ?',
      whereArgs: [batchId],
    );
    if (maps.isEmpty) return null;
    return models.Batch.fromMap(maps.first);
  }

  // 取得所有未完成的 Batch
  static Future<List<models.Batch>> getUnfinishedBatches() async {
    final db = await database;
    final maps = await db.query(
      'batches',
      where: 'finished_at IS NULL',
      orderBy: 'order_date DESC, created_at DESC',
    );
    return maps.map((map) => models.Batch.fromMap(map)).toList();
  }

  // 取得所有可掃描的 Batch（未完成的 + 最近 7 天內已完成的）
  // 用於「總出貨」模式，支援補掃漏掉的項目
  static Future<List<models.Batch>> getScannableBatches() async {
    final db = await database;
    
    // 計算 7 天前的日期
    final now = DateTime.now().toUtc();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final sevenDaysAgoStr = sevenDaysAgo.toIso8601String();
    
    final maps = await db.rawQuery(
      '''
      SELECT *
      FROM batches
      WHERE finished_at IS NULL 
         OR (finished_at IS NOT NULL AND finished_at >= ?)
      ORDER BY 
        CASE WHEN finished_at IS NULL THEN 0 ELSE 1 END,
        order_date DESC, 
        created_at DESC
      ''',
      [sevenDaysAgoStr],
    );
    return maps.map((map) => models.Batch.fromMap(map)).toList();
  }

  // 取得「今天有掃描活動」的 Batch（用於總出貨模式匯出）
  // 包含：
  // 1. 未完成的批次（今天可能有掃描）
  // 2. 已完成的批次，但今天有掃描活動（今天補掃的）
  static Future<List<models.Batch>> getBatchesWithTodayScans() async {
    final db = await database;
    
    // 計算今天的開始時間（UTC）
    final now = DateTime.now().toUtc();
    final todayStart = DateTime(now.year, now.month, now.day).toUtc();
    final todayStartStr = todayStart.toIso8601String();
    
    // 查詢所有「今天有掃描活動」的批次
    // 條件：
    // 1. 未完成的批次（finished_at IS NULL）
    // 2. 或已完成的批次，但今天有掃描活動（scan_items 中有 scan_time >= todayStart）
    final maps = await db.rawQuery(
      '''
      SELECT DISTINCT b.*
      FROM batches b
      INNER JOIN scan_items si ON b.id = si.batch_id
      WHERE (
        b.finished_at IS NULL
        OR (
          b.finished_at IS NOT NULL
          AND si.scan_time IS NOT NULL
          AND si.scan_time >= ?
        )
      )
      ORDER BY 
        CASE WHEN b.finished_at IS NULL THEN 0 ELSE 1 END,
        b.order_date DESC,
        b.created_at DESC
      ''',
      [todayStartStr],
    );
    
    return maps.map((map) => models.Batch.fromMap(map)).toList();
  }

  // 取得所有 Batch（包括已完成的）
  static Future<List<models.Batch>> getAllBatches() async {
    try {
      final db = await database;
      final maps = await db.query(
        'batches',
        orderBy: 'finished_at IS NULL DESC, order_date DESC, created_at DESC',
      );
      return maps.map((map) => models.Batch.fromMap(map)).toList();
    } catch (e) {
      debugPrint('取得所有批次時發生錯誤：$e');
      // 返回空列表，避免應用崩潰
      return [];
    }
  }

  // 刪除 Batch 及其所有 ScanItem
  static Future<void> deleteBatch(String batchId) async {
    final db = await database;
    await db.transaction((txn) async {
      // 先刪除所有相關的 scan_items
      await txn.delete(
        'scan_items',
        where: 'batch_id = ?',
        whereArgs: [batchId],
      );
      // 再刪除 batch
      await txn.delete(
        'batches',
        where: 'id = ?',
        whereArgs: [batchId],
      );
    });
  }

  // 標記 Batch 為已完成
  // scanFinishTime: 掃描完成時間（最後一次掃描時間），如果為 null 則使用當前時間
  static Future<void> finishBatch(String batchId, {String? scanFinishTime}) async {
    final db = await database;
    // 如果提供了掃描完成時間，使用該時間；否則使用當前時間
    final finishedAt = scanFinishTime ?? (await TimezoneHelper.getUtcNow()).toIso8601String();
    await db.update(
      'batches',
      {'finished_at': finishedAt},
      where: 'id = ?',
      whereArgs: [batchId],
    );
  }

  // ========== ScanItem 操作 ==========

  // 批量插入 ScanItem（智能更新：保留已掃描狀態）
  static Future<void> insertScanItems(List<ScanItem> items) async {
    if (items.isEmpty) return;
    
    int retryCount = 0;
    const maxRetries = 3;
    
    while (retryCount < maxRetries) {
      try {
        // 每次操作前都重新取得資料庫連線（會自動檢查連線有效性）
        final db = await database;
        
        // 先批量查詢現有記錄（基於 batch_id 和 logistics_no）
        // 取得所有唯一的 batch_id 和 logistics_no 組合
        final batchIds = items.map((item) => item.batchId).toSet().toList();
        final logisticsNos = items.map((item) => item.logisticsNo).toSet().toList();
        
        // 批量查詢現有記錄
        final existingItemsMap = <String, ScanItem>{}; // key: '${batchId}_${logisticsNo}'
        
        // 分批查詢，避免 SQL 語句過長
        for (final batchId in batchIds) {
          final batchItems = items.where((item) => item.batchId == batchId).toList();
          if (batchItems.isEmpty) continue;
          
          final batchLogisticsNos = batchItems.map((item) => item.logisticsNo).toList();
          
          // 使用 IN 查詢該 batch 的所有相關記錄
          final placeholders = List.filled(batchLogisticsNos.length, '?').join(',');
          final maps = await db.rawQuery(
            '''
            SELECT * FROM scan_items 
            WHERE batch_id = ? AND logistics_no IN ($placeholders)
            ''',
            [batchId, ...batchLogisticsNos],
          );
          
          // 建立映射表
          for (final map in maps) {
            final existingItem = ScanItem.fromMap(map);
            final key = '${existingItem.batchId}_${existingItem.logisticsNo}';
            existingItemsMap[key] = existingItem;
          }
        }
        
        // 準備批量操作
        final batch = db.batch();
        
        for (final newItem in items) {
          final key = '${newItem.batchId}_${newItem.logisticsNo}';
          final existingItem = existingItemsMap[key];
          
          if (existingItem == null) {
            // 情況 1：不存在，插入為 PENDING
            batch.insert(
              'scan_items',
              newItem.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } else {
            // 情況 2 和 3：已存在，根據 scan_status 決定更新行為
            if (existingItem.scanStatus == ScanStatus.pending) {
              // 情況 2：存在且為 PENDING，允許更新（維持 PENDING）
              batch.insert(
                'scan_items',
                newItem.toMap(),
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            } else if (existingItem.scanStatus == ScanStatus.scanned || 
                       existingItem.scanStatus == ScanStatus.duplicate) {
              // 情況 3：存在且為 SCANNED 或 DUPLICATE
              // 保留原本的 scan_status、scan_time、scan_note
              // 僅更新非掃描關鍵欄位：logistics_company、sheet_note、order_no、order_date
              final updatedItem = existingItem.copyWith(
                orderDate: newItem.orderDate,
                orderNo: newItem.orderNo,
                logisticsCompany: newItem.logisticsCompany,
                sheetNote: newItem.sheetNote,
                // scan_status、scan_time、scan_note 保持不變
              );
              
              batch.update(
                'scan_items',
                {
                  'order_date': updatedItem.orderDate,
                  'order_no': updatedItem.orderNo,
                  'logistics_company': updatedItem.logisticsCompany,
                  'sheet_note': updatedItem.sheetNote,
                  // 不更新 scan_status、scan_time、scan_note
                },
                where: 'batch_id = ? AND logistics_no = ?',
                whereArgs: [updatedItem.batchId, updatedItem.logisticsNo],
              );
            } else {
              // 其他狀態（如 INVALID，理論上不應該存在於資料庫中）
              // 但為了安全，也允許更新
              batch.insert(
                'scan_items',
                newItem.toMap(),
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }
        
        await batch.commit(noResult: true);
        return; // 成功則返回
      } catch (e) {
        final errorStr = e.toString();
        // 如果發生唯讀錯誤或資料庫移動錯誤，強制重新初始化
        if (errorStr.contains('readonly') || 
            errorStr.contains('READONLY') || 
            errorStr.contains('READONLY_DBMOVED') ||
            errorStr.contains('1032')) {
          retryCount++;
          // 強制清除連線並重新初始化
          if (_database != null) {
            try {
              await _database!.close();
            } catch (_) {
              // 忽略關閉錯誤
            }
          }
          _database = null;
          
          // 等待一下再重試
          if (retryCount < maxRetries) {
            await Future.delayed(Duration(milliseconds: 100 * retryCount));
            continue;
          }
        }
        // 其他錯誤或重試次數用完，拋出異常
        rethrow;
      }
    }
  }

  // 取得 Batch 的所有 ScanItem
  static Future<List<ScanItem>> getScanItemsByBatch(String batchId) async {
    final db = await database;
    final maps = await db.query(
      'scan_items',
      where: 'batch_id = ?',
      whereArgs: [batchId],
      orderBy: 'order_no ASC',
    );
    return maps.map((map) => ScanItem.fromMap(map)).toList();
  }

  // 取得 Batch 的訂單日期範圍（最小和最大日期）
  static Future<Map<String, String?>> getBatchDateRange(String batchId) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT 
        MIN(order_date) as min_date,
        MAX(order_date) as max_date
      FROM scan_items
      WHERE batch_id = ?
      ''',
      [batchId],
    );
    
    if (result.isEmpty) {
      return {'min_date': null, 'max_date': null};
    }
    
    return {
      'min_date': result.first['min_date'] as String?,
      'max_date': result.first['max_date'] as String?,
    };
  }

  // 根據 batch_id 和 logistics_no 查詢 ScanItem
  static Future<ScanItem?> getScanItem(String batchId, String logisticsNo) async {
    final db = await database;
    final maps = await db.query(
      'scan_items',
      where: 'batch_id = ? AND logistics_no = ?',
      whereArgs: [batchId, logisticsNo],
    );
    if (maps.isEmpty) return null;
    return ScanItem.fromMap(maps.first);
  }

  // 跨 Batch 查詢物流單號（在所有未完成的 Batch 中查找，以及最近 7 天內已完成的 Batch）
  // 這樣可以支援「今天漏掉一筆，明天補掃」的場景
  static Future<ScanItem?> getScanItemAcrossBatches(String logisticsNo) async {
    final db = await database;
    
    // 計算 7 天前的日期（用於查詢最近 7 天內已完成的批次）
    final now = DateTime.now().toUtc();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final sevenDaysAgoStr = sevenDaysAgo.toIso8601String();
    
    final maps = await db.rawQuery(
      '''
      SELECT si.*
      FROM scan_items si
      INNER JOIN batches b ON si.batch_id = b.id
      WHERE si.logistics_no = ? 
        AND (
          b.finished_at IS NULL 
          OR (b.finished_at IS NOT NULL AND b.finished_at >= ?)
        )
      ORDER BY 
        CASE WHEN b.finished_at IS NULL THEN 0 ELSE 1 END,
        si.id ASC
      LIMIT 1
      ''',
      [logisticsNo, sevenDaysAgoStr],
    );
    if (maps.isEmpty) return null;
    return ScanItem.fromMap(maps.first);
  }

  // 更新 ScanItem
  static Future<void> updateScanItem(ScanItem item) async {
    final db = await database;
    await db.update(
      'scan_items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  // 根據 ID 取得 ScanItem
  static Future<ScanItem?> getScanItemById(int id) async {
    final db = await database;
    final maps = await db.query(
      'scan_items',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return ScanItem.fromMap(maps.first);
  }

  // 刪除單筆 ScanItem
  static Future<void> deleteScanItem(int id) async {
    final db = await database;
    await db.delete(
      'scan_items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 批次刪除 ScanItem
  static Future<int> deleteScanItems(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    return await db.delete(
      'scan_items',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  // 刪除 Batch 的所有 ScanItem
  static Future<int> deleteScanItemsByBatch(String batchId) async {
    final db = await database;
    return await db.delete(
      'scan_items',
      where: 'batch_id = ?',
      whereArgs: [batchId],
    );
  }

  // ========== 清理操作 ==========

  // 清理 7 天前的已完成 Batch
  static Future<int> cleanupOldBatches() async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(const Duration(days: 7));
    final cutoffDateStr = cutoffDate.toUtc().toIso8601String().split('T')[0]; // YYYY-MM-DD

    // 先刪除相關的 scan_items
    final batchIds = await db.rawQuery('''
      SELECT id FROM batches 
      WHERE order_date < ? AND finished_at IS NOT NULL
    ''', [cutoffDateStr]);

    if (batchIds.isNotEmpty) {
      final ids = batchIds.map((map) => map['id'] as String).toList();
      final placeholders = List.filled(ids.length, '?').join(',');
      await db.delete(
        'scan_items',
        where: 'batch_id IN ($placeholders)',
        whereArgs: ids,
      );
    }

    // 再刪除 batches
    return await db.delete(
      'batches',
      where: 'order_date < ? AND finished_at IS NOT NULL',
      whereArgs: [cutoffDateStr],
    );
  }

  // ========== 非清單內記錄操作 ==========

  // 插入非清單內記錄
  static Future<void> insertOffListRecord(String logisticsNo) async {
    final db = await database;
    final now = await TimezoneHelper.getUtcNow();
    final nowStr = now.toIso8601String();
    
    try {
      await db.insert(
        'off_list_records',
        {
          'logistics_no': logisticsNo,
          'scan_time': nowStr,
          'created_at': nowStr,
        },
        conflictAlgorithm: ConflictAlgorithm.replace, // 如果已存在則更新
      );
    } catch (e) {
      debugPrint('插入非清單內記錄失敗：$e');
      rethrow;
    }
  }

  // 查詢所有非清單內記錄
  static Future<List<Map<String, dynamic>>> getAllOffListRecords() async {
    final db = await database;
    return await db.query(
      'off_list_records',
      orderBy: 'scan_time DESC',
    );
  }

  // 查詢指定時間範圍內的非清單內記錄
  static Future<List<Map<String, dynamic>>> getOffListRecordsByDateRange(
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    return await db.query(
      'off_list_records',
      where: 'scan_time >= ? AND scan_time <= ?',
      whereArgs: [startDate, endDate],
      orderBy: 'scan_time DESC',
    );
  }

  // 刪除非清單內記錄
  static Future<void> deleteOffListRecord(int id) async {
    final db = await database;
    await db.delete(
      'off_list_records',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 清空所有非清單內記錄
  static Future<int> deleteAllOffListRecords() async {
    final db = await database;
    return await db.delete('off_list_records');
  }

  // 關閉資料庫
  static Future<void> close() async {
    if (_database != null) {
      try {
        await _database!.close();
      } catch (_) {
        // 忽略關閉錯誤
      }
      _database = null;
    }
  }

  // 強制重置資料庫連線（用於修復連線問題）
  static Future<void> resetConnection() async {
    await close();
    await database; // 重新初始化
  }
}

