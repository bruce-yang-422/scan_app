import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/scan_item.dart';
import '../models/scan_status.dart';
import '../models/batch.dart';
import '../utils/date_parser.dart';

// 匯入結果
class ImportResult {
  final List<ScanItem> items;
  final int skippedCount; // 跳過的筆數（格式錯誤、必填欄位為空等）
  final int blankCount; // 空白資料筆數
  final int duplicateCount; // 重複資料筆數

  ImportResult({
    required this.items,
    required this.skippedCount,
    this.blankCount = 0,
    this.duplicateCount = 0,
  });
}

// 多批次匯入結果
class MultiBatchImportResult {
  final Map<String, List<ScanItem>> batches; // batchId -> items
  final Map<String, String> batchStoreNames; // batchId -> storeName
  final int skippedCount; // 跳過的筆數（格式錯誤、必填欄位為空等）
  final int blankCount; // 空白資料筆數
  final int duplicateCount; // 重複資料筆數

  MultiBatchImportResult({
    required this.batches,
    required this.batchStoreNames,
    required this.skippedCount,
    this.blankCount = 0,
    this.duplicateCount = 0,
  });

  int get batchCount => batches.length;
  int get totalItemsCount {
    return batches.values.fold(0, (sum, items) => sum + items.length);
  }
}

// Google Sheets 服務
class GoogleSheetsService {
  // 從公開的 Google Sheet 匯入資料
  // 欄位順序固定：
  // 1. 分店名稱（非必填）
  // 2. 訂單日期（必填，YYYY-MM-DD）
  // 3. 訂單編號（必填）
  // 4. 物流公司（非必填）
  // 5. 物流單號（必填）
  // 6. 備註（非必填）
  
  static Future<ImportResult> importFromSheet(
    String sheetUrl,
    String batchId,
  ) async {
    try {
      // 將 Google Sheet URL 轉換為 CSV 匯出 URL
      final csvUrl = _convertToCsvUrl(sheetUrl);
      
      // 下載 CSV 資料
      final response = await http.get(Uri.parse(csvUrl)).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('下載逾時，請檢查網路連線');
        },
      );

      if (response.statusCode != 200) {
        throw Exception('無法下載資料，狀態碼：${response.statusCode}');
      }

      // 解析 CSV
      final csvData = utf8.decode(response.bodyBytes);
      final lines = csvData.split('\n').where((line) => line.trim().isNotEmpty).toList();
      
      if (lines.isEmpty) {
        throw Exception('資料表為空');
      }

      // 跳過標題行（第一行），從第二行開始解析
      final List<ScanItem> items = [];
      final Set<String> seenKeys = {}; // 用於去重：orderDate + logisticsNo
      int skippedCount = 0; // 統計跳過的筆數（格式錯誤、必填欄位為空等）
      int blankCount = 0; // 統計空白資料筆數
      int duplicateCount = 0; // 統計重複資料筆數
      
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        
        // 檢查是否為空白行
        if (line.isEmpty) {
          blankCount++;
          continue;
        }
        
        final values = _parseCsvLine(line);
        
        // 確保至少有 5 個欄位（訂單日期、訂單編號、物流單號是必填）
        if (values.length < 5) {
          skippedCount++;
          continue; // 跳過不完整的行
        }

        // storeName 在此處不使用，因為 batchId 已經在外部確定
        final orderDateRaw = values[1].trim();
        final orderNo = values[2].trim();
        final logisticsCompany = values.length > 3 && values[3].trim().isNotEmpty 
            ? values[3].trim() 
            : null;
        final logisticsNo = values[4].trim();
        final sheetNote = values.length > 5 && values[5].trim().isNotEmpty 
            ? values[5].trim() 
            : null;

        // 檢查是否為空白資料（所有必填欄位都為空）
        if (orderDateRaw.isEmpty && orderNo.isEmpty && logisticsNo.isEmpty) {
          blankCount++;
          continue;
        }

        // 驗證必填欄位
        if (orderDateRaw.isEmpty || orderNo.isEmpty || logisticsNo.isEmpty) {
          skippedCount++;
          continue; // 跳過必填欄位為空的資料
        }

        // 解析並正規化日期為 yyyy-MM-dd（處理日期時間格式）
        String normalizedDate;
        try {
          normalizedDate = DateParser.normalizeDate(orderDateRaw);
        } catch (e) {
          // 日期解析失敗，跳過此筆資料
          skippedCount++;
          continue;
        }

        // 檢查日期是否超過7天（不匯入超過7天的資料）
        try {
          final orderDate = DateTime.parse(normalizedDate);
          final today = DateTime.now();
          final daysDiff = today.difference(orderDate).inDays;
          if (daysDiff > 7) {
            skippedCount++;
            continue; // 跳過超過7天的資料
          }
        } catch (e) {
          // 日期解析失敗，跳過此筆資料
          skippedCount++;
          continue;
        }

        // 檢查重複（基於 orderDate + logisticsNo）
        final uniqueKey = '$normalizedDate|$logisticsNo';
        if (seenKeys.contains(uniqueKey)) {
          duplicateCount++;
          continue; // 跳過重複資料
        }
        seenKeys.add(uniqueKey);

        final item = ScanItem(
          batchId: batchId,
          orderDate: normalizedDate,
          orderNo: orderNo,
          logisticsCompany: logisticsCompany,
          logisticsNo: logisticsNo,
          sheetNote: sheetNote,
          scanStatus: ScanStatus.pending,
        );

        items.add(item);
      }

      if (items.isEmpty) {
        throw Exception('沒有有效的資料行');
      }

      return ImportResult(
        items: items,
        skippedCount: skippedCount,
        blankCount: blankCount,
        duplicateCount: duplicateCount,
      );
    } catch (e) {
      throw Exception('匯入失敗：${e.toString()}');
    }
  }

  // 將 Google Sheet URL 轉換為 CSV 匯出 URL
  static String _convertToCsvUrl(String sheetUrl) {
    // 提取 Sheet ID
    final sheetIdMatch = RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)').firstMatch(sheetUrl);
    if (sheetIdMatch == null) {
      throw Exception('無效的 Google Sheet URL');
    }
    
    final sheetId = sheetIdMatch.group(1)!;
    
    // 提取 GID（如果有的話）
    final gidMatch = RegExp(r'[#&]gid=(\d+)').firstMatch(sheetUrl);
    final gid = gidMatch?.group(1) ?? '0';
    
    // 產生 CSV 匯出 URL
    return 'https://docs.google.com/spreadsheets/d/$sheetId/export?format=csv&gid=$gid';
  }

  // 解析 CSV 行（處理引號和逗號）
  static List<String> _parseCsvLine(String line) {
    final List<String> fields = [];
    final StringBuffer currentField = StringBuffer();
    bool inQuotes = false;
    
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          // 雙引號轉義
          currentField.write('"');
          i++; // 跳過下一個引號
        } else {
          // 切換引號狀態
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        // 欄位分隔符
        fields.add(currentField.toString());
        currentField.clear();
      } else {
        currentField.write(char);
      }
    }
    
    // 添加最後一個欄位
    fields.add(currentField.toString());
    
    return fields;
  }

  // 從公開的 Google Sheet 匯入資料（支援多批次自動分批）
  // 會依據訂單日期自動分批管理，每個 {store_name}_{order_date} 為一個 Batch
  static Future<MultiBatchImportResult> importFromSheetMultiBatch(
    String sheetUrl,
  ) async {
    try {
      // 將 Google Sheet URL 轉換為 CSV 匯出 URL
      final csvUrl = _convertToCsvUrl(sheetUrl);
      
      // 下載 CSV 資料
      final response = await http.get(Uri.parse(csvUrl)).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('下載逾時，請檢查網路連線');
        },
      );

      if (response.statusCode != 200) {
        throw Exception('無法下載資料，狀態碼：${response.statusCode}');
      }

      // 解析 CSV
      final csvData = utf8.decode(response.bodyBytes);
      final lines = csvData.split('\n').where((line) => line.trim().isNotEmpty).toList();
      
      if (lines.isEmpty) {
        throw Exception('資料表為空');
      }

      // 跳過標題行（第一行），從第二行開始解析
      final Map<String, List<ScanItem>> batches = {}; // batchId -> items
      final Map<String, String> batchStoreNames = {}; // batchId -> storeName
      final Map<String, Set<String>> seenKeys = {}; // batchId -> Set<uniqueKey>，用於去重
      int skippedCount = 0; // 統計跳過的筆數（格式錯誤、必填欄位為空等）
      int blankCount = 0; // 統計空白資料筆數
      int duplicateCount = 0; // 統計重複資料筆數
      
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        
        // 檢查是否為空白行
        if (line.isEmpty) {
          blankCount++;
          continue;
        }
        
        final values = _parseCsvLine(line);
        
        // 確保至少有 5 個欄位（訂單日期、訂單編號、物流單號是必填）
        if (values.length < 5) {
          skippedCount++;
          continue; // 跳過不完整的行
        }

        // 取得各欄位
        final storeNameRaw = values[0].trim();
        final orderDateRaw = values[1].trim();
        final orderNo = values[2].trim();
        final logisticsCompany = values.length > 3 && values[3].trim().isNotEmpty 
            ? values[3].trim() 
            : null;
        final logisticsNo = values[4].trim();
        final sheetNote = values.length > 5 && values[5].trim().isNotEmpty 
            ? values[5].trim() 
            : null;

        // 檢查是否為空白資料（所有必填欄位都為空）
        if (orderDateRaw.isEmpty && orderNo.isEmpty && logisticsNo.isEmpty) {
          blankCount++;
          continue;
        }

        // 驗證必填欄位
        if (orderDateRaw.isEmpty || orderNo.isEmpty || logisticsNo.isEmpty) {
          skippedCount++;
          continue; // 跳過必填欄位為空的資料
        }

        // 解析並正規化日期為 yyyy-MM-dd（處理日期時間格式）
        String normalizedDate;
        try {
          normalizedDate = DateParser.normalizeDate(orderDateRaw);
        } catch (e) {
          // 日期解析失敗，跳過此筆資料
          skippedCount++;
          continue;
        }

        // 檢查日期是否超過7天（不匯入超過7天的資料）
        try {
          final orderDate = DateTime.parse(normalizedDate);
          final today = DateTime.now();
          final daysDiff = today.difference(orderDate).inDays;
          if (daysDiff > 7) {
            skippedCount++;
            continue; // 跳過超過7天的資料
          }
        } catch (e) {
          // 日期解析失敗，跳過此筆資料
          skippedCount++;
          continue;
        }

        // 取得 store_name（如果為空，使用「未命名分店」）
        final storeName = storeNameRaw.isEmpty ? '未命名分店' : storeNameRaw;

        // 產生 batch_id（依據 store_name 和 order_date）
        final batchId = Batch.generateId(storeName, normalizedDate);

        // 初始化 batch 相關資料結構（如果不存在）
        if (!batches.containsKey(batchId)) {
          batches[batchId] = [];
          batchStoreNames[batchId] = storeName;
          seenKeys[batchId] = {};
        }

        // 檢查重複（基於 orderDate + logisticsNo，在同一個 batch 內）
        final uniqueKey = '$normalizedDate|$logisticsNo';
        if (seenKeys[batchId]!.contains(uniqueKey)) {
          duplicateCount++;
          continue; // 跳過重複資料
        }
        seenKeys[batchId]!.add(uniqueKey);

        final item = ScanItem(
          batchId: batchId,
          orderDate: normalizedDate,
          orderNo: orderNo,
          logisticsCompany: logisticsCompany,
          logisticsNo: logisticsNo,
          sheetNote: sheetNote,
          scanStatus: ScanStatus.pending,
        );

        batches[batchId]!.add(item);
      }

      if (batches.isEmpty) {
        throw Exception('沒有有效的資料行');
      }

      return MultiBatchImportResult(
        batches: batches,
        batchStoreNames: batchStoreNames,
        skippedCount: skippedCount,
        blankCount: blankCount,
        duplicateCount: duplicateCount,
      );
    } catch (e) {
      throw Exception('匯入失敗：${e.toString()}');
    }
  }

}
