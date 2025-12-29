import 'package:intl/intl.dart';

// 日期解析與正規化工具
class DateParser {
  // 正規化日期為 yyyy-MM-dd 格式
  // 支援多種輸入格式並統一輸出為 yyyy-MM-dd
  static String normalizeDate(String dateStr) {
    if (dateStr.trim().isEmpty) {
      throw FormatException('日期字串為空');
    }

    final trimmed = dateStr.trim();

    // 0. 處理日期時間格式（例如：2025-12-01 0:17 或 2025-12-01 00:17）
    // 提取日期部分（空格前的部分）
    final dateTimeParts = trimmed.split(RegExp(r'\s+'));
    final datePart = dateTimeParts.isNotEmpty ? dateTimeParts[0] : trimmed;

    // 1. 如果已經是 yyyy-MM-dd 格式，直接驗證並返回
    if (_isValidYYYYMMDD(datePart)) {
      return datePart;
    }

    // 2. 嘗試解析為 DateTime（支援多種格式）
    DateTime? parsedDate;

    // 常見日期格式列表
    final dateFormats = [
      'yyyy-MM-dd',           // 2025-12-22
      'yyyy/MM/dd',           // 2025/12/22
      'MM/dd/yyyy',           // 12/22/2025
      'dd/MM/yyyy',           // 22/12/2025
      'yyyy年MM月dd日',        // 2025年12月22日
      'yyyy.MM.dd',           // 2025.12.22
      'dd-MM-yyyy',           // 22-12-2025
      'dd/MM/yyyy',           // 22/12/2025
      'MM-dd-yyyy',           // 12-22-2025
    ];

    // 嘗試使用各種格式解析（使用日期部分）
    for (final format in dateFormats) {
      try {
        parsedDate = DateFormat(format).parse(datePart);
        break;
      } catch (e) {
        // 繼續嘗試下一個格式
      }
    }

    // 3. 如果格式解析失敗，嘗試直接解析為 DateTime（處理 ISO 8601 等）
    if (parsedDate == null) {
      try {
        parsedDate = DateTime.parse(datePart);
      } catch (e) {
        // 繼續嘗試其他方法
      }
    }

    // 4. 處理 Google Sheets Date 型別匯出為 CSV 的情況
    // 可能是序列號（例如：44927 代表 2023-01-01）
    if (parsedDate == null) {
      try {
        final serialNumber = double.tryParse(trimmed);
        if (serialNumber != null) {
          // Google Sheets 日期序列號：1900-01-01 為基準（但實際是 1899-12-30）
          // 需要減去 2 天來修正
          final baseDate = DateTime(1899, 12, 30);
          parsedDate = baseDate.add(Duration(days: serialNumber.toInt()));
        }
      } catch (e) {
        // 不是序列號
      }
    }

    // 5. 如果還是無法解析，嘗試手動解析常見格式
    parsedDate ??= _tryManualParse(datePart);

    // 6. 如果所有方法都失敗，拋出異常
    if (parsedDate == null) {
      throw FormatException('無法解析日期格式：$dateStr');
    }

    // 7. 驗證日期有效性
    if (!_isValidDate(parsedDate)) {
      throw FormatException('無效的日期：$dateStr');
    }

    // 8. 正規化為 yyyy-MM-dd 格式
    return DateFormat('yyyy-MM-dd').format(parsedDate);
  }

  // 驗證是否為有效的 yyyy-MM-dd 格式
  static bool _isValidYYYYMMDD(String dateStr) {
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!dateRegex.hasMatch(dateStr)) {
      return false;
    }
    try {
      final parts = dateStr.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      final date = DateTime(year, month, day);
      return date.year == year && date.month == month && date.day == day;
    } catch (e) {
      return false;
    }
  }

  // 驗證日期有效性
  static bool _isValidDate(DateTime date) {
    try {
      // 檢查日期是否在合理範圍內（例如：1900-2100）
      if (date.year < 1900 || date.year > 2100) {
        return false;
      }
      // 檢查月份和日期是否有效
      final reconstructed = DateTime(date.year, date.month, date.day);
      return reconstructed.year == date.year &&
          reconstructed.month == date.month &&
          reconstructed.day == date.day;
    } catch (e) {
      return false;
    }
  }

  // 手動解析常見日期格式
  static DateTime? _tryManualParse(String dateStr) {
    // 嘗試匹配常見的日期模式
    // yyyy-MM-dd, yyyy/MM/dd, MM/dd/yyyy, dd/MM/yyyy 等
    final patterns = [
      RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$'),  // yyyy-MM-dd, yyyy/MM/dd
      RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$'),  // MM/dd/yyyy, dd/MM/yyyy
      RegExp(r'^(\d{4})年(\d{1,2})月(\d{1,2})日$'),     // yyyy年MM月dd日
      RegExp(r'^(\d{4})\.(\d{1,2})\.(\d{1,2})$'),      // yyyy.MM.dd
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(dateStr);
      if (match != null) {
        try {
          final groups = match.groups([1, 2, 3]);
          if (groups.length == 3) {
            final n1 = int.parse(groups[0]!);
            final n2 = int.parse(groups[1]!);
            final n3 = int.parse(groups[2]!);

            // 判斷格式：如果第一個數字 >= 1000，可能是年份
            if (n1 >= 1000) {
              // yyyy-MM-dd 或 yyyy/MM/dd
              return DateTime(n1, n2, n3);
            } else if (n3 >= 1000) {
              // MM/dd/yyyy 或 dd/MM/yyyy
              // 需要判斷是 MM/dd/yyyy 還是 dd/MM/yyyy
              // 如果 n1 > 12，則 n1 是日期，n2 是月份（dd/MM/yyyy）
              if (n1 > 12) {
                return DateTime(n3, n2, n1); // dd/MM/yyyy
              } else if (n2 > 12) {
                return DateTime(n3, n1, n2); // MM/dd/yyyy
              } else {
                // 無法確定，假設為 MM/dd/yyyy（美式格式）
                return DateTime(n3, n1, n2);
              }
            }
          }
        } catch (e) {
          // 解析失敗，繼續嘗試下一個模式
        }
      }
    }

    return null;
  }

  // 驗證日期字串是否可以正規化
  static bool canNormalize(String dateStr) {
    try {
      normalizeDate(dateStr);
      return true;
    } catch (e) {
      return false;
    }
  }
}

