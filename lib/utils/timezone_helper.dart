import 'package:intl/intl.dart';
import '../models/timezone_config.dart';
import '../services/ntp_service.dart';

// 時區輔助工具
// 固定使用 UTC+8 (Asia/Taipei)
class TimezoneHelper {
  // 固定時區：UTC+8 (Asia/Taipei)
  static const TimezoneConfig _fixedTimezone = TimezoneConfig(
    offsetHours: 8,
    name: '台北',
  );
  
  // 初始化時區（在 App 啟動時呼叫，現在不需要做任何事）
  static Future<void> initialize() async {
    // 時區已固定為 UTC+8，不需要初始化
  }

  // 取得當前時區（固定為 UTC+8）
  static TimezoneConfig getCurrentTimezone() {
    return _fixedTimezone;
  }

  // 將 UTC DateTime 轉換為設定的時區時間
  static DateTime toLocalTime(DateTime utcTime) {
    final timezone = getCurrentTimezone();
    return utcTime.add(timezone.offset);
  }

  // 將設定的時區時間轉換為 UTC DateTime
  static DateTime toUtcTime(DateTime localTime) {
    final timezone = getCurrentTimezone();
    return localTime.subtract(timezone.offset);
  }

  // 取得當前 UTC 時間（從 NTP 伺服器同步）
  static Future<DateTime> getUtcNow() async {
    try {
      final ntpTime = await NtpService.getNetworkTime();
      // 確保返回的是 UTC 時間
      return ntpTime.isUtc ? ntpTime : ntpTime.toUtc();
    } catch (e) {
      // 如果 NTP 同步失敗，返回本地 UTC 時間
      // 確保返回的是 UTC 時間
      final now = DateTime.now();
      return now.isUtc ? now : now.toUtc();
    }
  }

  // 取得當前 UTC 時間（同步版本，使用本地時間）
  // 注意：此方法不使用 NTP，僅用於不需要精確時間的場景
  static DateTime getUtcNowSync() {
    return DateTime.now().toUtc();
  }

  // 取得當前本地時間（根據設定的時區）
  static Future<DateTime> getLocalNow() async {
    final utcNow = await getUtcNow();
    return toLocalTime(utcNow);
  }

  // 將 ISO 8601 字串（UTC）轉換為本地時間字串
  static String formatLocalTime(String isoUtcString) {
    try {
      final utcTime = DateTime.parse(isoUtcString);
      final localTime = toLocalTime(utcTime);
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(localTime);
    } catch (e) {
      return isoUtcString; // 如果解析失敗，返回原字串
    }
  }

  // 將 ISO 8601 字串（UTC）轉換為本地時間字串（不含時區標示，直接顯示台灣時間）
  static String formatLocalTimeWithTimezone(String isoUtcString) {
    try {
      final utcTime = DateTime.parse(isoUtcString);
      final localTime = toLocalTime(utcTime);
      // 直接顯示台灣時間，不標註時區
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(localTime);
    } catch (e) {
      return isoUtcString;
    }
  }

  // 格式化當前本地時間（用於匯出檔名）
  static Future<String> formatLocalNowForFilename() async {
    final localNow = await getLocalNow();
    return DateFormat('yyyyMMdd_HHmm').format(localNow);
  }

  // 格式化當前本地時間（直接顯示台灣時間，不含時區標示）
  static Future<String> formatLocalNowIso() async {
    // 取得 UTC 時間
    final utcNow = await getUtcNow();
    // 轉換為台灣時間（加8小時）
    final localTime = toLocalTime(utcNow);
    // 直接顯示台灣時間，不標註時區
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(localTime);
  }

  // 將 UTC ISO 8601 轉換為本地時間字串（直接顯示台灣時間，不含時區標示）
  // 輸入：UTC 時間字符串（ISO 8601 格式，如 "2025-01-20T07:30:00.000Z"）
  // 輸出：台灣時間字符串（格式 "2025-01-20 15:30:00"，已加8小時）
  static String convertUtcToLocalIso(String isoUtcString) {
    try {
      // 解析 UTC 時間字符串
      final parsedTime = DateTime.parse(isoUtcString);
      // 確保是 UTC 時間
      final utcTime = parsedTime.isUtc ? parsedTime : parsedTime.toUtc();
      // 轉換為台灣時間（加8小時）
      final localTime = toLocalTime(utcTime);
      // 直接顯示台灣時間，不標註時區
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(localTime);
    } catch (e) {
      // 如果解析失敗，返回原字串
      return isoUtcString;
    }
  }
}

