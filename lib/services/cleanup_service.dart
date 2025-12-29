import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'database_service.dart';
import 'app_settings_service.dart';

// 清理服務
class CleanupService {
  // 清理 7 天前的已完成 Batch
  // 在 App 啟動時呼叫
  static Future<int> cleanupOldBatches() async {
    return await DatabaseService.cleanupOldBatches();
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

