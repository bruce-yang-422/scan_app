import 'package:shared_preferences/shared_preferences.dart';

// App 設定服務
class AppSettingsService {
  // 狀態顯示時間（秒）- 所有狀態共用此設定
  static const String _keyStatusDelaySeconds = 'status_delay_seconds';
  static const int _defaultStatusDelaySeconds = 2; // 預設 2 秒

  // 掃描成功震動開關
  static const String _keyVibrationEnabled = 'vibration_enabled';
  static const bool _defaultVibrationEnabled = true;

  // 掃描成功聲音開關
  static const String _keySoundEnabled = 'sound_enabled';
  static const bool _defaultSoundEnabled = true;

  // 掃描人員姓名
  static const String _keyScannerName = 'scanner_name';
  static const String _defaultScannerName = '';

  // 掃描人員編號/ID
  static const String _keyScannerId = 'scanner_id';
  static const String _defaultScannerId = '';

  // 顯示模式：'auto', 'dark', 'light'
  static const String _keyThemeMode = 'theme_mode';
  static const String _defaultThemeMode = 'auto'; // 預設自動（跟隨系統）

  // 匯出檔案保留天數
  static const String _keyExportFileRetentionDays = 'export_file_retention_days';
  static const int _defaultExportFileRetentionDays = 10; // 預設保留 10 天

  // 相機掃描重複判斷間隔（秒）- 用於判斷是否為重複掃描
  static const String _keyCameraDuplicateIntervalSeconds = 'camera_duplicate_interval_seconds';
  static const int _defaultCameraDuplicateIntervalSeconds = 10; // 預設 10 秒

  // 非清單內出貨紀錄模式開關
  static const String _keyOffListRecordModeEnabled = 'off_list_record_mode_enabled';
  static const bool _defaultOffListRecordModeEnabled = false; // 預設關閉

  // 非清單內出貨紀錄模式預設值（用於設定頁面）
  static const String _keyOffListRecordModeDefault = 'off_list_record_mode_default';
  static const bool _defaultOffListRecordModeDefault = false; // 預設關閉

  // 上次清除非清單內記錄的時間（ISO 8601格式）
  static const String _keyLastOffListCleanupTime = 'last_off_list_cleanup_time';

  // 上次清除一般掃描記錄的時間（ISO 8601格式）
  static const String _keyLastScanRecordsCleanupTime = 'last_scan_records_cleanup_time';

  // 一般掃描記錄自動歸零開關
  static const String _keyAutoCleanupScanRecords = 'auto_cleanup_scan_records';
  static const bool _defaultAutoCleanupScanRecords = false; // 預設關閉

  // 非清單內記錄自動歸零開關
  static const String _keyAutoCleanupOffListRecords = 'auto_cleanup_off_list_records';
  static const bool _defaultAutoCleanupOffListRecords = false; // 預設關閉

  // 取得狀態顯示時間（秒）- 所有狀態共用
  static Future<int> getStatusDelaySeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyStatusDelaySeconds) ?? _defaultStatusDelaySeconds;
  }

  // 設定狀態顯示時間（秒）- 所有狀態共用
  static Future<void> setStatusDelaySeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyStatusDelaySeconds, seconds);
  }

  // 向後相容：保留舊的 getSuccessDelaySeconds 方法（使用狀態顯示時間）
  @Deprecated('請使用 getStatusDelaySeconds()')
  static Future<int> getSuccessDelaySeconds() async {
    return await getStatusDelaySeconds();
  }

  // 向後相容：保留舊的 setSuccessDelaySeconds 方法（使用狀態顯示時間）
  @Deprecated('請使用 setStatusDelaySeconds()')
  static Future<void> setSuccessDelaySeconds(int seconds) async {
    await setStatusDelaySeconds(seconds);
  }

  // 取得震動開關狀態
  static Future<bool> isVibrationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyVibrationEnabled) ?? _defaultVibrationEnabled;
  }

  // 設定震動開關
  static Future<void> setVibrationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVibrationEnabled, enabled);
  }

  // 取得聲音開關狀態
  static Future<bool> isSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySoundEnabled) ?? _defaultSoundEnabled;
  }

  // 設定聲音開關
  static Future<void> setSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySoundEnabled, enabled);
  }

  // 取得掃描人員姓名
  static Future<String> getScannerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyScannerName) ?? _defaultScannerName;
  }

  // 設定掃描人員姓名
  static Future<void> setScannerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyScannerName, name);
  }

  // 取得掃描人員編號/ID
  static Future<String> getScannerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyScannerId) ?? _defaultScannerId;
  }

  // 設定掃描人員編號/ID
  static Future<void> setScannerId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyScannerId, id);
  }

  // 取得顯示模式
  static Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyThemeMode) ?? _defaultThemeMode;
  }

  // 設定顯示模式
  static Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode);
  }

  // 取得匯出檔案保留天數
  static Future<int> getExportFileRetentionDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyExportFileRetentionDays) ?? _defaultExportFileRetentionDays;
  }

  // 設定匯出檔案保留天數
  static Future<void> setExportFileRetentionDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyExportFileRetentionDays, days);
  }

  // 取得相機掃描重複判斷間隔（秒）
  static Future<int> getCameraDuplicateIntervalSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_keyCameraDuplicateIntervalSeconds);
    // 確保值在有效範圍內（5-60秒）
    if (value != null && value >= 5 && value <= 60) {
      return value;
    }
    return _defaultCameraDuplicateIntervalSeconds;
  }

  // 設定相機掃描重複判斷間隔（秒）
  static Future<void> setCameraDuplicateIntervalSeconds(int seconds) async {
    // 確保值在有效範圍內（5-60秒）
    final clampedSeconds = seconds.clamp(5, 60);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCameraDuplicateIntervalSeconds, clampedSeconds);
  }

  // 取得非清單內出貨紀錄模式開關狀態
  static Future<bool> isOffListRecordModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOffListRecordModeEnabled) ?? _defaultOffListRecordModeEnabled;
  }

  // 設定非清單內出貨紀錄模式開關
  static Future<void> setOffListRecordModeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOffListRecordModeEnabled, enabled);
  }

  // 取得非清單內出貨紀錄模式預設值
  static Future<bool> getOffListRecordModeDefault() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOffListRecordModeDefault) ?? _defaultOffListRecordModeDefault;
  }

  // 設定非清單內出貨紀錄模式預設值
  static Future<void> setOffListRecordModeDefault(bool defaultValue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOffListRecordModeDefault, defaultValue);
  }

  // 取得上次清除非清單內記錄的時間
  static Future<String?> getLastOffListCleanupTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastOffListCleanupTime);
  }

  // 設定上次清除非清單內記錄的時間
  static Future<void> setLastOffListCleanupTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastOffListCleanupTime, time);
  }

  // 取得一般掃描記錄自動歸零開關狀態
  static Future<bool> isAutoCleanupScanRecordsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoCleanupScanRecords) ?? _defaultAutoCleanupScanRecords;
  }

  // 設定一般掃描記錄自動歸零開關
  static Future<void> setAutoCleanupScanRecordsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoCleanupScanRecords, enabled);
  }

  // 取得非清單內記錄自動歸零開關狀態
  static Future<bool> isAutoCleanupOffListRecordsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoCleanupOffListRecords) ?? _defaultAutoCleanupOffListRecords;
  }

  // 設定非清單內記錄自動歸零開關
  static Future<void> setAutoCleanupOffListRecordsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoCleanupOffListRecords, enabled);
  }

  // 取得上次清除一般掃描記錄的時間
  static Future<String?> getLastScanRecordsCleanupTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastScanRecordsCleanupTime);
  }

  // 設定上次清除一般掃描記錄的時間
  static Future<void> setLastScanRecordsCleanupTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastScanRecordsCleanupTime, time);
  }
}

