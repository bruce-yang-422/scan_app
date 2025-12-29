import 'database_service.dart';

// 清理服務
class CleanupService {
  // 清理 7 天前的已完成 Batch
  // 在 App 啟動時呼叫
  static Future<int> cleanupOldBatches() async {
    return await DatabaseService.cleanupOldBatches();
  }
}

