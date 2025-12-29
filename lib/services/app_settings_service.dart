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
  static const String _defaultThemeMode = 'auto'; // 預設自動

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
}

