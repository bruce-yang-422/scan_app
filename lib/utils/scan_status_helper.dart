import '../models/scan_status.dart';

// ScanStatus 輔助函數
class ScanStatusHelper {
  static ScanStatus fromString(String value) {
    switch (value) {
      case 'PENDING':
        return ScanStatus.pending;
      case 'SCANNED':
        return ScanStatus.scanned;
      case 'DUPLICATE':
        return ScanStatus.duplicate;
      case 'INVALID':
        return ScanStatus.invalid;
      default:
        return ScanStatus.pending;
    }
  }
}

