import 'scan_status.dart';
import '../utils/scan_status_helper.dart';

// 掃描項目模型
class ScanItem {
  final int? id; // SQLite 自動遞增 ID
  final String batchId;
  final String orderDate; // YYYY-MM-DD
  final String orderNo;
  final String? logisticsCompany;
  final String logisticsNo; // 掃描唯一 Key
  final String? sheetNote; // Google Sheet 中的備註
  final ScanStatus scanStatus;
  final String? scanTime; // ISO 8601, nullable
  final String? scanNote; // 使用者手動備註

  ScanItem({
    this.id,
    required this.batchId,
    required this.orderDate,
    required this.orderNo,
    this.logisticsCompany,
    required this.logisticsNo,
    this.sheetNote,
    required this.scanStatus,
    this.scanTime,
    this.scanNote,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'batch_id': batchId,
      'order_date': orderDate,
      'order_no': orderNo,
      'logistics_company': logisticsCompany,
      'logistics_no': logisticsNo,
      'sheet_note': sheetNote,
      'scan_status': scanStatus.value,
      'scan_time': scanTime,
      'scan_note': scanNote,
    };
  }

  factory ScanItem.fromMap(Map<String, dynamic> map) {
    return ScanItem(
      id: map['id'] as int?,
      batchId: map['batch_id'] as String,
      orderDate: map['order_date'] as String,
      orderNo: map['order_no'] as String,
      logisticsCompany: map['logistics_company'] as String?,
      logisticsNo: map['logistics_no'] as String,
      sheetNote: map['sheet_note'] as String?,
      scanStatus: ScanStatusHelper.fromString(map['scan_status'] as String),
      scanTime: map['scan_time'] as String?,
      scanNote: map['scan_note'] as String?,
    );
  }

  ScanItem copyWith({
    int? id,
    String? batchId,
    String? orderDate,
    String? orderNo,
    String? logisticsCompany,
    String? logisticsNo,
    String? sheetNote,
    ScanStatus? scanStatus,
    String? scanTime,
    String? scanNote,
  }) {
    return ScanItem(
      id: id ?? this.id,
      batchId: batchId ?? this.batchId,
      orderDate: orderDate ?? this.orderDate,
      orderNo: orderNo ?? this.orderNo,
      logisticsCompany: logisticsCompany ?? this.logisticsCompany,
      logisticsNo: logisticsNo ?? this.logisticsNo,
      sheetNote: sheetNote ?? this.sheetNote,
      scanStatus: scanStatus ?? this.scanStatus,
      scanTime: scanTime ?? this.scanTime,
      scanNote: scanNote ?? this.scanNote,
    );
  }
}

