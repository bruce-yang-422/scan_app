// 掃描狀態枚舉
enum ScanStatus {
  pending,   // 尚未掃描
  scanned,   // 成功
  duplicate, // 重複掃描
  invalid,   // 不在清單內
}

extension ScanStatusExtension on ScanStatus {
  String get value {
    switch (this) {
      case ScanStatus.pending:
        return 'PENDING';
      case ScanStatus.scanned:
        return 'SCANNED';
      case ScanStatus.duplicate:
        return 'DUPLICATE';
      case ScanStatus.invalid:
        return 'INVALID';
    }
  }

  String get displayName {
    switch (this) {
      case ScanStatus.pending:
        return '待掃描';
      case ScanStatus.scanned:
        return '已掃描';
      case ScanStatus.duplicate:
        return '重複';
      case ScanStatus.invalid:
        return '無效';
    }
  }
}

