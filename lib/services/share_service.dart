import 'package:share_plus/share_plus.dart';
import 'dart:io';

// 分享服務
class ShareService {
  // 分享檔案（TXT 和 JSON）
  static Future<void> shareFiles(String txtPath, [String? jsonPath]) async {
    try {
      // 檢查檔案是否存在
      final txtFile = File(txtPath);
      if (!await txtFile.exists()) {
        throw Exception('TXT 檔案不存在：$txtPath');
      }

      final files = <XFile>[
        XFile(txtPath),
      ];
      
      if (jsonPath != null) {
        final jsonFile = File(jsonPath);
        if (await jsonFile.exists()) {
          files.add(XFile(jsonPath));
        }
      }
      
      // 使用 try-catch 包裝，避免 device_info 插件錯誤影響分享功能
      try {
        await Share.shareXFiles(
          files,
          text: '掃描結果匯出',
          subject: '出貨掃描結果',
        );
      } catch (pluginError) {
        // 如果是插件錯誤，嘗試使用簡單的分享方式
        if (pluginError.toString().contains('MissingPluginException') ||
            pluginError.toString().contains('device_info')) {
          // 降級處理：只分享第一個檔案
          await Share.shareXFiles(
            [XFile(txtPath)],
            text: '掃描結果匯出',
            subject: '出貨掃描結果',
          );
        } else {
          rethrow;
        }
      }
    } catch (e) {
      // 提供更友好的錯誤訊息
      final errorMsg = e.toString();
      if (errorMsg.contains('MissingPluginException') ||
          errorMsg.contains('device_info')) {
        throw Exception('分享功能需要重新啟動應用程式。請關閉 App 後重新開啟。');
      }
      throw Exception('分享失敗：${e.toString()}');
    }
  }
}
