import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/timezone_config.dart';

// 時區服務
class TimezoneService {
  static const String _key = 'timezone_config';

  // 取得當前設定的時區
  static Future<TimezoneConfig> getTimezone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_key);
      if (jsonString != null) {
        final map = jsonDecode(jsonString) as Map<String, dynamic>;
        return TimezoneConfig.fromMap(map);
      }
    } catch (e) {
      // 如果讀取失敗，返回預設時區
    }
    return TimezoneConfig.defaultTimezone;
  }

  // 設定時區
  static Future<void> setTimezone(TimezoneConfig timezone) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(timezone.toMap());
    await prefs.setString(_key, jsonString);
  }

  // 清除時區設定（恢復預設）
  static Future<void> clearTimezone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

