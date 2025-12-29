import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'database_service.dart';
import 'app_settings_service.dart';
import '../utils/timezone_helper.dart';

// 清理服務
class CleanupService {
  // 清理 7 天前的已完成 Batch
  // 在 App 啟動時呼叫
  // 如果自動歸零開關開啟，則每天00:00台灣時區自動清除
  static Future<int> cleanupOldBatches() async {
    // 檢查自動歸零開關
    final autoCleanupEnabled = await AppSettingsService.isAutoCleanupScanRecordsEnabled();
    if (!autoCleanupEnabled) {
      // 開關關閉，不執行自動清理
      return 0;
    }

    // 檢查是否需要清理（每天00:00台灣時區）
    // 系統層使用UTC時間，但判斷基準是台灣時區的00:00
    final lastCleanupTimeStr = await AppSettingsService.getLastScanRecordsCleanupTime();
    final nowUtc = await TimezoneHelper.getUtcNow();
    // 轉換為台灣時區以判斷今天的00:00
    final nowTaiwan = TimezoneHelper.toLocalTime(nowUtc);
    final todayStartTaiwan = DateTime(nowTaiwan.year, nowTaiwan.month, nowTaiwan.day);
    // 將台灣時區的今天00:00轉換回UTC用於比較
    final todayStartUtc = TimezoneHelper.toUtcTime(todayStartTaiwan);

    // 如果上次清除時間為空，或上次清除時間在今天00:00之前，則需要清除
    if (lastCleanupTimeStr == null || 
        DateTime.parse(lastCleanupTimeStr).isBefore(todayStartUtc)) {
      final deletedCount = await DatabaseService.cleanupOldBatches();
      
      // 更新上次清除時間為今天00:00（台灣時區，轉換為UTC儲存）
      await AppSettingsService.setLastScanRecordsCleanupTime(todayStartUtc.toIso8601String());
      
      return deletedCount;
    }
    
    return 0;
  }

  // 清理過期的匯出檔案
  // 根據設定的保留天數刪除過期檔案，並清理空目錄
  static Future<CleanupFileResult> cleanupOldExportFiles() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final reportsBaseDir = Directory(path.join(documentsDir.path, 'reports'));
      
      if (!await reportsBaseDir.exists()) {
        return CleanupFileResult(deletedFiles: 0, deletedDirs: 0);
      }

      // 取得保留天數設定
      final retentionDays = await AppSettingsService.getExportFileRetentionDays();
      final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));

      // 遞迴遍歷所有目錄和檔案
      final result = await _cleanupDirectory(reportsBaseDir, cutoffDate);

      return CleanupFileResult(
        deletedFiles: result.deletedFiles,
        deletedDirs: result.deletedDirs,
      );
    } catch (e) {
      // 清理失敗不影響 App 運行，只記錄錯誤
      debugPrint('清理過期匯出檔案時發生錯誤：$e');
      return CleanupFileResult(deletedFiles: 0, deletedDirs: 0);
    }
  }

  // 遞迴清理目錄
  static Future<CleanupFileResult> _cleanupDirectory(
    Directory dir,
    DateTime cutoffDate,
  ) async {
    int deletedFiles = 0;
    int deletedDirs = 0;

    if (!await dir.exists()) {
      return CleanupFileResult(deletedFiles: 0, deletedDirs: 0);
    }

    try {
      final entities = await dir.list().toList();
      bool hasNonDeletedFiles = false;

      for (final entity in entities) {
        if (entity is File) {
          // 檢查檔案修改時間
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            // 檔案過期，刪除
            try {
              await entity.delete();
              deletedFiles++;
              debugPrint('已刪除過期檔案：${entity.path}');
            } catch (e) {
              debugPrint('刪除檔案失敗：${entity.path}, 錯誤：$e');
            }
          } else {
            // 檔案未過期，標記為有未刪除檔案
            hasNonDeletedFiles = true;
          }
        } else if (entity is Directory) {
          // 遞迴處理子目錄
          final subResult = await _cleanupDirectory(entity, cutoffDate);
          deletedFiles += subResult.deletedFiles;
          deletedDirs += subResult.deletedDirs;
          
          // 檢查子目錄是否為空
          try {
            final subEntities = await entity.list().toList();
            if (subEntities.isEmpty) {
              // 目錄為空，刪除
              await entity.delete(recursive: true);
              deletedDirs++;
              debugPrint('已刪除空目錄：${entity.path}');
            } else {
              // 子目錄有內容，標記為有未刪除檔案
              hasNonDeletedFiles = true;
            }
          } catch (e) {
            debugPrint('檢查子目錄失敗：${entity.path}, 錯誤：$e');
          }
        }
      }

      // 如果當前目錄為空且不是根目錄，嘗試刪除
      if (!hasNonDeletedFiles && dir.path != path.join((await getApplicationDocumentsDirectory()).path, 'reports')) {
        try {
          final remainingEntities = await dir.list().toList();
          if (remainingEntities.isEmpty) {
            await dir.delete(recursive: true);
            deletedDirs++;
            debugPrint('已刪除空目錄：${dir.path}');
          }
        } catch (e) {
          debugPrint('刪除空目錄失敗：${dir.path}, 錯誤：$e');
        }
      }
    } catch (e) {
      debugPrint('清理目錄失敗：${dir.path}, 錯誤：$e');
    }

    return CleanupFileResult(
      deletedFiles: deletedFiles,
      deletedDirs: deletedDirs,
    );
  }

  // 清除非清單內記錄（每天00:00台灣時區自動清除）
  // 在 App 啟動時呼叫，檢查是否需要清除
  static Future<bool> cleanupOffListRecordsIfNeeded() async {
    try {
      // 檢查自動歸零開關
      final autoCleanupEnabled = await AppSettingsService.isAutoCleanupOffListRecordsEnabled();
      if (!autoCleanupEnabled) {
        // 開關關閉，不執行自動清理
        return false;
      }

      // 取得上次清除時間（UTC）
      final lastCleanupTimeStr = await AppSettingsService.getLastOffListCleanupTime();
      
      // 系統層使用UTC時間，但判斷基準是台灣時區的00:00
      final nowUtc = await TimezoneHelper.getUtcNow();
      // 轉換為台灣時區以判斷今天的00:00
      final nowTaiwan = TimezoneHelper.toLocalTime(nowUtc);
      final todayStartTaiwan = DateTime(nowTaiwan.year, nowTaiwan.month, nowTaiwan.day);
      // 將台灣時區的今天00:00轉換回UTC用於比較
      final todayStartUtc = TimezoneHelper.toUtcTime(todayStartTaiwan);
      
      // 如果上次清除時間為空，或上次清除時間（UTC）在今天00:00（UTC）之前，則需要清除
      if (lastCleanupTimeStr == null) {
        // 首次清除
        final deletedCount = await DatabaseService.deleteAllOffListRecords();
        await AppSettingsService.setLastOffListCleanupTime(todayStartUtc.toIso8601String());
        if (deletedCount > 0) {
          debugPrint('已自動清除非清單內記錄：$deletedCount 筆');
        }
        return true;
      }
      
      // 比較時間（都轉換為UTC比較）
      final lastCleanupTimeUtc = DateTime.parse(lastCleanupTimeStr);
      if (lastCleanupTimeUtc.isBefore(todayStartUtc)) {
        // 清除非清單內記錄
        final deletedCount = await DatabaseService.deleteAllOffListRecords();
        
        // 更新上次清除時間為今天00:00（台灣時區，轉換為UTC儲存）
        await AppSettingsService.setLastOffListCleanupTime(todayStartUtc.toIso8601String());
        
        if (deletedCount > 0) {
          debugPrint('已自動清除非清單內記錄：$deletedCount 筆');
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('清除非清單內記錄時發生錯誤：$e');
      return false;
    }
  }

  // 手動清除非清單內記錄
  static Future<int> cleanupOffListRecordsManually() async {
    try {
      final deletedCount = await DatabaseService.deleteAllOffListRecords();
      
      // 更新上次清除時間為當前時間（UTC）
      final nowUtc = await TimezoneHelper.getUtcNow();
      await AppSettingsService.setLastOffListCleanupTime(nowUtc.toIso8601String());
      
      return deletedCount;
    } catch (e) {
      debugPrint('手動清除非清單內記錄時發生錯誤：$e');
      rethrow;
    }
  }
}

// 清理檔案結果
class CleanupFileResult {
  final int deletedFiles;
  final int deletedDirs;

  CleanupFileResult({
    required this.deletedFiles,
    required this.deletedDirs,
  });
}

