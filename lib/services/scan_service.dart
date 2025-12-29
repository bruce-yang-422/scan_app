import '../models/scan_item.dart';
import '../models/scan_status.dart';
import 'database_service.dart';
import '../utils/timezone_helper.dart';
import 'app_settings_service.dart';

// 掃描服務
class ScanService {
  // 掃描物流單號（單一 Batch）
  // 返回更新後的 ScanItem 和狀態訊息
  static Future<ScanResult> scanLogisticsNo(
    String batchId,
    String logisticsNo,
  ) async {
    // 查詢該物流單號
    final item = await DatabaseService.getScanItem(batchId, logisticsNo);

    if (item == null) {
      // 查無資料 → INVALID
      return ScanResult(
        status: ScanStatus.invalid,
        message: '不在清單內',
      );
    }

    return await _processScanResult(item);
  }

  // 跨 Batch 掃描物流單號（在所有未完成的 Batch 中查找）
  // 返回更新後的 ScanItem 和狀態訊息
  static Future<ScanResult> scanLogisticsNoAcrossBatches(
    String logisticsNo,
  ) async {
    // 在所有未完成的 Batch 中查找該物流單號
    final item = await DatabaseService.getScanItemAcrossBatches(logisticsNo);

    if (item == null) {
      // 查無資料 → INVALID
      return ScanResult(
        status: ScanStatus.invalid,
        message: '不在清單內',
      );
    }

    return await _processScanResult(item);
  }

  // 處理掃描結果（共用邏輯）
  static Future<ScanResult> _processScanResult(ScanItem item) async {

    // 根據當前狀態決定新狀態
    ScanStatus newStatus;
    String? scanTime;
    String message;

    switch (item.scanStatus) {
      case ScanStatus.pending:
        // PENDING → SCANNED
        newStatus = ScanStatus.scanned;
        // 儲存為 UTC 時間（標準時間，從 NTP 同步）
        scanTime = (await TimezoneHelper.getUtcNow()).toIso8601String();
        message = '掃描成功';
        break;
      case ScanStatus.scanned:
        // SCANNED：檢查是否超過重複判斷間隔
        if (item.scanTime != null) {
          try {
            // 解析上次掃描時間（UTC）
            final lastScanTime = DateTime.parse(item.scanTime!);
            final now = await TimezoneHelper.getUtcNow();
            final timeDiff = now.difference(lastScanTime).inSeconds;
            
            // 取得相機掃描重複判斷間隔設定
            final duplicateInterval = await AppSettingsService.getCameraDuplicateIntervalSeconds();
            
            // 如果在時間間隔內，不算重複，更新掃描時間
            if (timeDiff < duplicateInterval) {
              newStatus = ScanStatus.scanned;
              scanTime = now.toIso8601String();
              message = '掃描成功';
            } else {
              // 超過時間間隔，判定為重複
              newStatus = ScanStatus.duplicate;
              message = '重複掃描';
            }
          } catch (e) {
            // 時間解析失敗，預設判定為重複
            newStatus = ScanStatus.duplicate;
            message = '重複掃描';
          }
        } else {
          // 沒有上次掃描時間，預設判定為重複（不應該發生）
          newStatus = ScanStatus.duplicate;
          message = '重複掃描';
        }
        break;
      case ScanStatus.duplicate:
        // 已經是 DUPLICATE，檢查是否在時間間隔內
        if (item.scanTime != null) {
          try {
            // 解析上次掃描時間（UTC）
            final lastScanTime = DateTime.parse(item.scanTime!);
            final now = await TimezoneHelper.getUtcNow();
            final timeDiff = now.difference(lastScanTime).inSeconds;
            
            // 取得相機掃描重複判斷間隔設定
            final duplicateInterval = await AppSettingsService.getCameraDuplicateIntervalSeconds();
            
            // 如果在時間間隔內，不算重複，更新掃描時間
            if (timeDiff < duplicateInterval) {
              newStatus = ScanStatus.scanned;
              scanTime = now.toIso8601String();
              message = '掃描成功';
            } else {
              // 超過時間間隔，保持為重複
              newStatus = ScanStatus.duplicate;
              message = '重複掃描';
            }
          } catch (e) {
            // 時間解析失敗，保持為重複
            newStatus = ScanStatus.duplicate;
            message = '重複掃描';
          }
        } else {
          // 沒有上次掃描時間，保持為重複
          newStatus = ScanStatus.duplicate;
          message = '重複掃描';
        }
        break;
      case ScanStatus.invalid:
        // 不應該發生，但處理一下
        newStatus = ScanStatus.invalid;
        message = '無效';
        break;
    }

    // 更新 ScanItem
    final updatedItem = item.copyWith(
      scanStatus: newStatus,
      scanTime: scanTime ?? item.scanTime,
    );

    await DatabaseService.updateScanItem(updatedItem);

    return ScanResult(
      status: newStatus,
      message: message,
      item: updatedItem,
    );
  }

  // 更新掃描備註
  static Future<void> updateScanNote(
    int itemId,
    String? scanNote,
  ) async {
    final item = await DatabaseService.getScanItemById(itemId);
    if (item != null) {
      final updatedItem = item.copyWith(scanNote: scanNote);
      await DatabaseService.updateScanItem(updatedItem);
    }
  }

  // 取得 Batch 的統計資訊
  static Future<BatchStatistics> getBatchStatistics(String batchId) async {
    final items = await DatabaseService.getScanItemsByBatch(batchId);
    
    int total = items.length;
    int scanned = items.where((i) => i.scanStatus == ScanStatus.scanned).length;
    int pending = items.where((i) => i.scanStatus == ScanStatus.pending).length;
    int duplicate = items.where((i) => i.scanStatus == ScanStatus.duplicate).length;
    int invalid = items.where((i) => i.scanStatus == ScanStatus.invalid).length;

    return BatchStatistics(
      total: total,
      scanned: scanned,
      pending: pending,
      duplicate: duplicate,
      invalid: invalid,
    );
  }
}

// 掃描結果
class ScanResult {
  final ScanStatus status;
  final String message;
  final ScanItem? item;

  ScanResult({
    required this.status,
    required this.message,
    this.item,
  });
}

// Batch 統計資訊
class BatchStatistics {
  final int total;
  final int scanned;
  final int pending;
  final int duplicate;
  final int invalid;

  BatchStatistics({
    required this.total,
    required this.scanned,
    required this.pending,
    required this.duplicate,
    required this.invalid,
  });

  int get error => duplicate + invalid;
  int get notScanned => pending;
}

