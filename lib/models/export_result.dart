import 'batch.dart';

// 匯出結果模型
class ExportResult {
  final String storeName;
  final String orderDate;
  final String scanFinishTime; // 掃描完成時間（最後一次掃描時間，固定不變）
  final String exportTime; // 匯出時間（實際匯出時的時間，會變動）
  final ExportSummary summary;
  final List<ExportItem> items;
  final String? scannerName; // 掃描人員姓名（可選）
  final String? scannerId; // 掃描人員編號/ID（可選）
  final Map<String, Batch>? batchMap; // 批次映射（用於總出貨模式，根據 item 的 batchId 查找對應的 store_name）

  ExportResult({
    required this.storeName,
    required this.orderDate,
    required this.scanFinishTime,
    required this.exportTime,
    required this.summary,
    required this.items,
    this.scannerName,
    this.scannerId,
    this.batchMap,
  });

  Map<String, dynamic> toJson() {
    // 為每個 item 添加 store_name，並按照 CSV 欄位順序組織
    final itemsJson = items.map((item) {
      final itemJson = item.toJson();
      // 按照 CSV 欄位順序：分店名稱,訂單日期,訂單編號,物流公司,物流單號,備註(匯入原始的),掃描狀態,掃描時間,掃描備註
      // 重新組織 JSON 結構
      return {
        'store_name': _getItemStoreName(item), // 分店名稱（每個 item 使用自己的批次來源）
        'order_date': itemJson['order_date'], // 訂單日期
        'order_no': itemJson['order_no'], // 訂單編號
        'logistics_company': itemJson['logistics_company'] ?? '', // 物流公司
        'logistics_no': itemJson['logistics_no'], // 物流單號
        'sheet_note': itemJson['sheet_note'] ?? '', // 備註(匯入原始的)
        'scan_status': itemJson['scan_status'], // 掃描狀態
        'scan_time': itemJson['scan_time'] ?? '', // 掃描時間
        'scan_note': itemJson['scan_note'] ?? '', // 掃描備註
      };
    }).toList();
    
    final json = {
      // 統計摘要和掃描人資訊（開頭）
      'store_name': storeName,
      'order_date': orderDate,
      'scan_finish_time': scanFinishTime, // 掃描完成時間（最後一次掃描時間）
      'export_time': exportTime, // 匯出時間（實際匯出時的時間）
      'summary': summary.toJson(),
      // 掃描人員資料（如果有）
      if (scannerName != null && scannerName!.isNotEmpty)
        'scanner_name': scannerName!,
      if (scannerId != null && scannerId!.isNotEmpty)
        'scanner_id': scannerId!,
      // 資料陣列（按照 CSV 欄位順序：分店名稱,訂單日期,訂單編號,物流公司,物流單號,備註(匯入原始的),掃描狀態,掃描時間,掃描備註）
      'items': itemsJson,
    };
    
    return json;
  }

  // 取得 item 的 store_name（如果是總出貨模式，根據 batchId 查找；否則使用匯總的 storeName）
  String _getItemStoreName(ExportItem item) {
    if (batchMap != null && item.batchId != null) {
      final batch = batchMap![item.batchId];
      if (batch != null && batch.storeName != null && batch.storeName!.isNotEmpty) {
        return batch.storeName!;
      }
    }
    return storeName;
  }
}

// 匯出摘要
class ExportSummary {
  final int total;
  final int scanned;
  final int notScanned;
  final int error; // duplicate + invalid
  final int offListCount; // 非清單內記錄筆數

  ExportSummary({
    required this.total,
    required this.scanned,
    required this.notScanned,
    required this.error,
    this.offListCount = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'scanned': scanned,
      'not_scanned': notScanned,
      'error': error,
      'off_list_count': offListCount,
    };
  }
}

// 匯出項目
class ExportItem {
  final String orderDate; // 訂單日期
  final String orderNo;
  final String? logisticsCompany;
  final String logisticsNo;
  final String scanStatus;
  final String? scanTime;
  final String? scanNote;
  final String? sheetNote;
  final String? batchId; // 批次 ID（用於總出貨模式，查找對應的 store_name）

  ExportItem({
    required this.orderDate,
    required this.orderNo,
    this.logisticsCompany,
    required this.logisticsNo,
    required this.scanStatus,
    this.scanTime,
    this.scanNote,
    this.sheetNote,
    this.batchId,
  });

  Map<String, dynamic> toJson() {
    return {
      'order_date': orderDate,
      'order_no': orderNo,
      'logistics_company': logisticsCompany,
      'logistics_no': logisticsNo,
      'scan_status': scanStatus,
      'scan_time': scanTime,
      'scan_note': scanNote,
      'sheet_note': sheetNote,
    };
  }
}

