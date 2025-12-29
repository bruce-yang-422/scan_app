import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/batch.dart';
import '../models/scan_item.dart';
import '../models/export_result.dart';
import '../models/scan_status.dart';
import 'database_service.dart';
import '../utils/timezone_helper.dart';
import 'app_settings_service.dart';

// 匯出服務
class ExportService {
  // 匯出 Batch 結果
  // 返回產生的檔案路徑
  // allowReexport: 是否允許重新匯出已完成的批次（用於分享失敗後重試）
  static Future<ExportFiles> exportBatch(String batchId, {bool allowReexport = false}) async {
    // 取得 Batch 資訊
    final batch = await DatabaseService.getBatch(batchId);
    if (batch == null) {
      throw Exception('找不到 Batch：$batchId');
    }

    // 如果已完成且不允許重新匯出，檢查是否有現有檔案
    if (batch.isFinished && !allowReexport) {
      // 嘗試尋找已匯出的檔案
      final reportsDir = await _getReportsDirectory(batch.storeName, batch.orderDate);
      final files = await reportsDir.list().toList();
      
      // 尋找該批次的最新匯出檔案
      String? latestTxtPath;
      String? latestJsonPath;
      DateTime? latestTime;
      
      for (final file in files) {
        if (file is File) {
          final fileName = path.basename(file.path);
          if (fileName.startsWith('scan_result_${batch.storeName}_') && 
              fileName.contains(batch.orderDate.replaceAll('-', ''))) {
            final stat = await file.stat();
            if (latestTime == null || stat.modified.isAfter(latestTime)) {
              latestTime = stat.modified;
              if (fileName.endsWith('.txt')) {
                latestTxtPath = file.path;
              } else if (fileName.endsWith('.json')) {
                latestJsonPath = file.path;
              }
            }
          }
        }
      }
      
      // 如果找到檔案，返回檔案路徑（不重新匯出）
      if (latestTxtPath != null && latestJsonPath != null) {
        return ExportFiles(
          txtPath: latestTxtPath,
          jsonPath: latestJsonPath,
        );
      }
      
      throw Exception('此 Batch 已完成匯出，且找不到匯出檔案。請使用重新匯出功能。');
    }

    // 取得所有 ScanItem
    final items = await DatabaseService.getScanItemsByBatch(batchId);

    // 產生檔名（使用本地時間）
    final timestamp = await TimezoneHelper.formatLocalNowForFilename();
    
    // 產生匯出資料
    final exportResult = await _buildExportResult(batch, items);
    final fileName = 'scan_result_${batch.storeName}_$timestamp';

    // 取得 reports 目錄
    final reportsDir = await _getReportsDirectory(batch.storeName, batch.orderDate);

    // 同時產生 TXT 和 JSON 檔案
    final txtFile = File(path.join(reportsDir.path, '$fileName.txt'));
    final jsonFile = File(path.join(reportsDir.path, '$fileName.json'));
    
    // 並行寫入兩個檔案
    await Future.wait([
      txtFile.writeAsString(
        _generateTxt(exportResult),
        encoding: utf8,
      ),
      jsonFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(exportResult.toJson()),
        encoding: utf8,
      ),
    ]);

    // 只有在首次匯出時才標記為已完成
    if (!batch.isFinished) {
      await DatabaseService.finishBatch(batchId);
    }

    return ExportFiles(
      txtPath: txtFile.path,
      jsonPath: jsonFile.path,
    );
  }

  // 匯出多個 Batch 的匯總結果（用於總出貨模式）
  // 返回產生的檔案路徑
  static Future<ExportFiles> exportMultipleBatches(List<String> batchIds) async {
    if (batchIds.isEmpty) {
      throw Exception('批次列表為空');
    }

    // 取得所有 Batch 資訊和 ScanItem
    final batches = <Batch>[];
    final allItems = <ScanItem>[];
    final allStoreNames = <String>{};
    final allOrderDates = <String>{};
    
    for (final batchId in batchIds) {
      final batch = await DatabaseService.getBatch(batchId);
      if (batch != null) {
        batches.add(batch);
        if (batch.storeName != null && batch.storeName!.isNotEmpty) {
          allStoreNames.add(batch.storeName!);
        }
        if (batch.orderDate != null) {
          allOrderDates.add(batch.orderDate!);
        }
        
        final items = await DatabaseService.getScanItemsByBatch(batchId);
        allItems.addAll(items);
      }
    }

    if (batches.isEmpty) {
      throw Exception('找不到任何有效的批次');
    }

    // 產生檔名（使用本地時間）
    final timestamp = await TimezoneHelper.formatLocalNowForFilename();
    
    // 產生匯總的匯出資料
    final exportResult = await _buildMultiBatchExportResult(
      batches,
      allItems,
      allStoreNames.toList()..sort(),
      allOrderDates.toList()..sort(),
    );
    
    // 使用第一個批次的 storeName 和 orderDate 作為檔名（或使用 "總出貨"）
    final storeName = allStoreNames.length == 1 
        ? allStoreNames.first 
        : '總出貨';
    final fileName = 'scan_result_${storeName}_$timestamp';

    // 取得 reports 目錄（使用第一個批次的路徑，或使用總出貨目錄）
    final reportsDir = batches.isNotEmpty
        ? await _getReportsDirectory(batches.first.storeName, batches.first.orderDate)
        : await _getReportsDirectory('總出貨', DateTime.now().toIso8601String().split('T')[0]);

    // 同時產生 TXT 和 JSON 檔案
    final txtFile = File(path.join(reportsDir.path, '$fileName.txt'));
    final jsonFile = File(path.join(reportsDir.path, '$fileName.json'));
    
    // 並行寫入兩個檔案
    await Future.wait([
      txtFile.writeAsString(
        _generateTxt(exportResult),
        encoding: utf8,
      ),
      jsonFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(exportResult.toJson()),
        encoding: utf8,
      ),
    ]);

    return ExportFiles(
      txtPath: txtFile.path,
      jsonPath: jsonFile.path,
    );
  }

  // 建立多批次匯總的匯出結果
  static Future<ExportResult> _buildMultiBatchExportResult(
    List<Batch> batches,
    List<ScanItem> allItems,
    List<String> storeNames,
    List<String> orderDates,
  ) async {
    // 使用本地時間（台灣時間）
    final scanFinishTime = await TimezoneHelper.formatLocalNowIso();

    // 取得掃描人員資料
    final scannerName = await AppSettingsService.getScannerName();
    final scannerId = await AppSettingsService.getScannerId();

    // 建立批次 ID 到 Batch 的映射，以便快速查找每個 item 的批次資訊
    final batchMap = <String, Batch>{};
    for (final batch in batches) {
      batchMap[batch.id] = batch;
    }

    // 匯總統計
    int total = allItems.length;
    int scanned = allItems.where((i) => i.scanStatus == ScanStatus.scanned).length;
    int notScanned = allItems.where((i) => i.scanStatus == ScanStatus.pending).length;
    int duplicate = allItems.where((i) => i.scanStatus == ScanStatus.duplicate).length;
    int invalid = allItems.where((i) => i.scanStatus == ScanStatus.invalid).length;
    int error = duplicate + invalid;

    final summary = ExportSummary(
      total: total,
      scanned: scanned,
      notScanned: notScanned,
      error: error,
    );

    // 轉換為 ExportItem（將 scanTime 從 UTC 轉換為本地時間）
    // 注意：每個 item 的 store_name 將在 ExportResult.toJson() 中根據 item 的批次資訊設置
    final exportItems = allItems.map((item) {
      // 如果 scanTime 存在，轉換為本地時間（直接顯示台灣時間，不含時區標示）
      String? localScanTime;
      if (item.scanTime != null) {
        localScanTime = TimezoneHelper.convertUtcToLocalIso(item.scanTime!);
      }
      
      return ExportItem(
        orderDate: item.orderDate,
        orderNo: item.orderNo,
        logisticsCompany: item.logisticsCompany,
        logisticsNo: item.logisticsNo,
        scanStatus: item.scanStatus.value,
        scanTime: localScanTime,
        scanNote: item.scanNote,
        sheetNote: item.sheetNote,
        batchId: item.batchId, // 保存批次 ID，用於在 toJson() 中查找對應的 store_name
      );
    }).toList();

    // 使用多個來源名稱（用逗號分隔）或 "總出貨"
    final storeName = storeNames.length == 1 
        ? storeNames.first 
        : storeNames.join('、');
    
    // 使用多個訂單日期（用逗號分隔）或第一個日期
    final orderDate = orderDates.length == 1 
        ? orderDates.first 
        : orderDates.join('、');

    return ExportResult(
      storeName: storeName,
      orderDate: orderDate,
      scanFinishTime: scanFinishTime,
      summary: summary,
      items: exportItems,
      scannerName: scannerName.isNotEmpty ? scannerName : null,
      scannerId: scannerId.isNotEmpty ? scannerId : null,
      batchMap: batchMap, // 傳遞批次映射，用於在 toJson() 中查找每個 item 的 store_name
    );
  }

  // 建立匯出結果（公開方法，用於生成 LINE 版本）
  static Future<ExportResult> buildExportResult(Batch batch, List<ScanItem> items) async {
    return await _buildExportResult(batch, items);
  }

  // 建立多批次匯出結果（公開方法，用於生成 LINE 版本）
  static Future<ExportResult> buildMultiBatchExportResult(
    List<Batch> batches,
    List<ScanItem> allItems,
    List<String> storeNames,
    List<String> orderDates,
  ) async {
    return await _buildMultiBatchExportResult(batches, allItems, storeNames, orderDates);
  }

  // 建立匯出結果（內部方法）
  static Future<ExportResult> _buildExportResult(Batch batch, List<ScanItem> items) async {
    // 使用本地時間（但標示為本地時間）
    final scanFinishTime = await TimezoneHelper.formatLocalNowIso();

    // 取得掃描人員資料
    final scannerName = await AppSettingsService.getScannerName();
    final scannerId = await AppSettingsService.getScannerId();

    // 統計
    // 注意：根據規格，INVALID 不會寫入資料庫，所以這裡的 invalid 應該始終為 0
    int total = items.length;
    int scanned = items.where((i) => i.scanStatus == ScanStatus.scanned).length;
    int notScanned = items.where((i) => i.scanStatus == ScanStatus.pending).length;
    int duplicate = items.where((i) => i.scanStatus == ScanStatus.duplicate).length;
    // INVALID 不會出現在資料庫中，此統計僅用於程式碼完整性
    int invalid = items.where((i) => i.scanStatus == ScanStatus.invalid).length;
    int error = duplicate + invalid;

    final summary = ExportSummary(
      total: total,
      scanned: scanned,
      notScanned: notScanned,
      error: error,
    );

    // 轉換為 ExportItem（將 scanTime 從 UTC 轉換為本地時間）
    final exportItems = items.map((item) {
      // 如果 scanTime 存在，轉換為本地時間（直接顯示台灣時間，不含時區標示）
      String? localScanTime;
      if (item.scanTime != null) {
        localScanTime = TimezoneHelper.convertUtcToLocalIso(item.scanTime!);
      }
      
      return ExportItem(
        orderDate: item.orderDate, // 添加訂單日期
        orderNo: item.orderNo,
        logisticsCompany: item.logisticsCompany,
        logisticsNo: item.logisticsNo,
        scanStatus: item.scanStatus.value,
        scanTime: localScanTime,
        scanNote: item.scanNote,
        sheetNote: item.sheetNote,
      );
    }).toList();

    return ExportResult(
      storeName: batch.storeName,
      orderDate: batch.orderDate,
      scanFinishTime: scanFinishTime,
      summary: summary,
      items: exportItems,
      scannerName: scannerName.isNotEmpty ? scannerName : null,
      scannerId: scannerId.isNotEmpty ? scannerId : null,
    );
  }

  // 產生 TXT 內容（用於分享）
  static String _generateTxt(ExportResult result) {
    return _generateTextContent(result, lineWidth: 40);
  }

  // 產生 LINE 複製/貼上版本（簡潔格式，不列出掃描成功清單）
  static String generateLineText(ExportResult result) {
    return _generateLineTextContent(result, lineWidth: 20);
  }

  // 產生 LINE 文字內容（不列出掃描成功清單）
  static String _generateLineTextContent(ExportResult result, {required int lineWidth}) {
    final buffer = StringBuffer();
    
    // 標題
    buffer.writeln('=' * lineWidth);
    buffer.writeln('掃描結果報告');
    buffer.writeln('=' * lineWidth);
    buffer.writeln();

    // 基本資訊
    buffer.writeln('店名：${result.storeName}');
    buffer.writeln('訂單日期：${result.orderDate}');
    // scanFinishTime 已經是台灣時間格式（yyyy-MM-dd HH:mm:ss），直接使用
    buffer.writeln('掃描完成時間：${result.scanFinishTime}');
    if (result.scannerName != null && result.scannerName!.isNotEmpty) {
      buffer.writeln('掃描人員姓名：${result.scannerName}');
    }
    if (result.scannerId != null && result.scannerId!.isNotEmpty) {
      buffer.writeln('掃描人員編號：${result.scannerId}');
    }
    buffer.writeln();

    // 統計摘要
    buffer.writeln('-' * lineWidth);
    buffer.writeln('統計摘要');
    buffer.writeln('-' * lineWidth);
    buffer.writeln('總筆數：${result.summary.total}');
    buffer.writeln('已掃描：${result.summary.scanned}');
    buffer.writeln('未掃描：${result.summary.notScanned}');
    buffer.writeln('錯誤（重複/無效）：${result.summary.error}');
    buffer.writeln();

    // 未掃描清單（重點）
    final notScannedItems = result.items.where((item) => item.scanStatus == 'PENDING').toList();
    if (notScannedItems.isNotEmpty) {
      buffer.writeln('-' * lineWidth);
      buffer.writeln('未掃描清單（${notScannedItems.length} 筆）');
      buffer.writeln('-' * lineWidth);
      for (final item in notScannedItems) {
        buffer.writeln('訂單編號：${item.orderNo}');
        buffer.writeln('物流單號：${item.logisticsNo}');
        if (item.logisticsCompany != null) {
          buffer.writeln('物流公司：${item.logisticsCompany}');
        }
        if (item.sheetNote != null) {
          buffer.writeln('備註：${item.sheetNote}');
        }
        buffer.writeln();
      }
    }

    // 錯誤／重複明細
    // 注意：根據規格，INVALID 不會寫入資料庫，所以這裡只會有 DUPLICATE
    final errorItems = result.items.where((item) => 
      item.scanStatus == 'DUPLICATE'
    ).toList();
    if (errorItems.isNotEmpty) {
      buffer.writeln('-' * lineWidth);
      buffer.writeln('錯誤／重複明細（${errorItems.length} 筆）');
      buffer.writeln('-' * lineWidth);
      for (final item in errorItems) {
        buffer.writeln('訂單編號：${item.orderNo}');
        buffer.writeln('物流單號：${item.logisticsNo}');
        buffer.writeln('狀態：${_getStatusDisplayName(item.scanStatus)}');
        if (item.scanTime != null) {
          buffer.writeln('掃描時間：${_formatDateTimeWithTimezone(item.scanTime!)}');
        }
        if (item.scanNote != null) {
          buffer.writeln('備註：${item.scanNote}');
        }
        buffer.writeln();
      }
    }

    // LINE 版本不列出已掃描成功的清單，只顯示統計摘要中的數量

    buffer.writeln();
    buffer.writeln('=' * lineWidth);
    buffer.writeln('報告結束');
    buffer.writeln('=' * lineWidth);

    return buffer.toString();
  }

  // 產生文字內容（通用方法）
  static String _generateTextContent(ExportResult result, {required int lineWidth}) {
    final buffer = StringBuffer();
    
    // 標題
    buffer.writeln('=' * lineWidth);
    buffer.writeln('掃描結果報告');
    buffer.writeln('=' * lineWidth);
    buffer.writeln();

    // 基本資訊
    buffer.writeln('店名：${result.storeName}');
    buffer.writeln('訂單日期：${result.orderDate}');
    // scanFinishTime 已經是台灣時間格式（yyyy-MM-dd HH:mm:ss），直接使用
    buffer.writeln('掃描完成時間：${result.scanFinishTime}');
    if (result.scannerName != null && result.scannerName!.isNotEmpty) {
      buffer.writeln('掃描人員姓名：${result.scannerName}');
    }
    if (result.scannerId != null && result.scannerId!.isNotEmpty) {
      buffer.writeln('掃描人員編號：${result.scannerId}');
    }
    buffer.writeln();

    // 統計摘要
    buffer.writeln('-' * lineWidth);
    buffer.writeln('統計摘要');
    buffer.writeln('-' * lineWidth);
    buffer.writeln('總筆數：${result.summary.total}');
    buffer.writeln('已掃描：${result.summary.scanned}');
    buffer.writeln('未掃描：${result.summary.notScanned}');
    buffer.writeln('錯誤（重複/無效）：${result.summary.error}');
    buffer.writeln();

    // 未掃描清單（重點）
    final notScannedItems = result.items.where((item) => item.scanStatus == 'PENDING').toList();
    if (notScannedItems.isNotEmpty) {
      buffer.writeln('-' * lineWidth);
      buffer.writeln('未掃描清單（${notScannedItems.length} 筆）');
      buffer.writeln('-' * lineWidth);
      for (final item in notScannedItems) {
        buffer.writeln('訂單編號：${item.orderNo}');
        buffer.writeln('物流單號：${item.logisticsNo}');
        if (item.logisticsCompany != null) {
          buffer.writeln('物流公司：${item.logisticsCompany}');
        }
        if (item.sheetNote != null) {
          buffer.writeln('備註：${item.sheetNote}');
        }
        buffer.writeln();
      }
    }

    // 錯誤／重複明細
    // 注意：根據規格，INVALID 不會寫入資料庫，所以這裡只會有 DUPLICATE
    final errorItems = result.items.where((item) => 
      item.scanStatus == 'DUPLICATE'
    ).toList();
    if (errorItems.isNotEmpty) {
      buffer.writeln('-' * lineWidth);
      buffer.writeln('錯誤／重複明細（${errorItems.length} 筆）');
      buffer.writeln('-' * lineWidth);
      for (final item in errorItems) {
        buffer.writeln('訂單編號：${item.orderNo}');
        buffer.writeln('物流單號：${item.logisticsNo}');
        buffer.writeln('狀態：${_getStatusDisplayName(item.scanStatus)}');
        if (item.scanTime != null) {
          buffer.writeln('掃描時間：${_formatDateTimeWithTimezone(item.scanTime!)}');
        }
        if (item.scanNote != null) {
          buffer.writeln('備註：${item.scanNote}');
        }
        buffer.writeln();
      }
    }

    // 已掃描統計（簡化顯示，不列出明細）
    final scannedItems = result.items.where((item) => item.scanStatus == 'SCANNED').toList();
    if (scannedItems.isNotEmpty) {
      buffer.writeln('-' * lineWidth);
      buffer.writeln('已掃描統計');
      buffer.writeln('-' * lineWidth);
      buffer.writeln('成功：${scannedItems.length} 筆');
      buffer.writeln('成功的包含：');
      buffer.writeln('  日期：${result.orderDate}');
      buffer.writeln('  分店：${result.storeName}');
      buffer.writeln('  成功：${scannedItems.length} 筆');
      buffer.writeln();
    }

    buffer.writeln();
    buffer.writeln('=' * lineWidth);
    buffer.writeln('報告結束');
    buffer.writeln('=' * lineWidth);

    return buffer.toString();
  }

  // 取得 reports 目錄
  static Future<Directory> _getReportsDirectory(String storeName, String orderDate) async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final reportsBaseDir = Directory(path.join(
      documentsDir.path,
      'reports',
      'store=$storeName',
      'order_date=$orderDate',
    ));

    if (!await reportsBaseDir.exists()) {
      await reportsBaseDir.create(recursive: true);
    }

    return reportsBaseDir;
  }

  // 格式化日期時間（直接顯示台灣時間，不含時區標示）
  static String _formatDateTimeWithTimezone(String isoString) {
    // 如果已經是台灣時間格式（不含時區標示，格式為 yyyy-MM-dd HH:mm:ss），直接返回
    if (RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(isoString)) {
      return isoString;
    }
    
    // 如果是 UTC ISO 格式（包含 T 和 Z 或時區偏移），轉換為台灣時間
    if (isoString.contains('T') && (isoString.endsWith('Z') || isoString.contains('+'))) {
      return TimezoneHelper.formatLocalTimeWithTimezone(isoString);
    }
    
    // 其他情況，嘗試解析為 UTC 並轉換
    try {
      final dateTime = DateTime.parse(isoString);
      // 如果沒有時區信息，假設是 UTC
      final utcTime = dateTime.isUtc ? dateTime : dateTime.toUtc();
      return TimezoneHelper.formatLocalTimeWithTimezone(utcTime.toIso8601String());
    } catch (e) {
      // 如果解析失敗，直接返回原字串
      return isoString;
    }
  }

  // 產生 CSV 內容（用於 Python 轉 Excel）
  static String _generateCsv(ExportResult result) {
    final buffer = StringBuffer();
    
    // CSV 開頭：統計摘要和掃描人資訊（以註解形式）
    buffer.writeln('# 掃描結果報告');
    buffer.writeln('# 分店名稱：${result.storeName}');
    buffer.writeln('# 訂單日期：${result.orderDate}');
    buffer.writeln('# 掃描完成時間：${result.scanFinishTime}');
    if (result.scannerName != null && result.scannerName!.isNotEmpty) {
      buffer.writeln('# 掃描人員姓名：${result.scannerName}');
    }
    if (result.scannerId != null && result.scannerId!.isNotEmpty) {
      buffer.writeln('# 掃描人員編號：${result.scannerId}');
    }
    buffer.writeln('# 統計摘要：');
    buffer.writeln('#   總筆數：${result.summary.total}');
    buffer.writeln('#   已掃描：${result.summary.scanned}');
    buffer.writeln('#   未掃描：${result.summary.notScanned}');
    buffer.writeln('#   錯誤（重複/無效）：${result.summary.error}');
    buffer.writeln('');
    
    // CSV 標題行
    buffer.writeln('分店名稱,訂單日期,訂單編號,物流公司,物流單號,備註(匯入原始的),掃描狀態,掃描時間,掃描備註');
    
    // CSV 資料行
    for (final item in result.items) {
      // CSV 格式：處理包含逗號的值（用引號包圍）
      buffer.writeln('${_escapeCsvValue(result.storeName)},'
          '${_escapeCsvValue(item.orderDate)},'
          '${_escapeCsvValue(item.orderNo)},'
          '${_escapeCsvValue(item.logisticsCompany ?? '')},'
          '${_escapeCsvValue(item.logisticsNo)},'
          '${_escapeCsvValue(item.sheetNote ?? '')},'
          '${_escapeCsvValue(_getStatusDisplayName(item.scanStatus))},'
          '${_escapeCsvValue(item.scanTime ?? '')},'
          '${_escapeCsvValue(item.scanNote ?? '')}');
    }
    
    return buffer.toString();
  }

  // CSV 值轉義（處理包含逗號、引號、換行的值）
  static String _escapeCsvValue(String value) {
    if (value.isEmpty) return '';
    
    // 如果包含逗號、引號或換行，需要用引號包圍，並將引號轉義為雙引號
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  // 取得狀態顯示名稱
  static String _getStatusDisplayName(String status) {
    switch (status) {
      case 'PENDING':
        return '待掃描';
      case 'SCANNED':
        return '已掃描';
      case 'DUPLICATE':
        return '重複掃描';
      case 'INVALID':
        return '不在清單內';
      default:
        return status;
    }
  }
}

// 匯出檔案路徑
class ExportFiles {
  final String txtPath;
  final String jsonPath;

  ExportFiles({
    required this.txtPath,
    required this.jsonPath,
  });
}
