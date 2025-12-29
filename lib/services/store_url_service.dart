import 'package:shared_preferences/shared_preferences.dart';

// 來源 URL 管理服務（來源可以是分店、供應商、或其他任何名稱）
class StoreUrlService {
  static const String _prefix = 'store_url_';

  // 儲存來源的 Google Sheet URL（來源名稱可自由設定）
  static Future<void> saveStoreUrl(String storeName, String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$storeName', url);
  }

  // 取得來源的 Google Sheet URL
  static Future<String?> getStoreUrl(String storeName) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$storeName');
  }

  // 刪除來源的 URL
  static Future<void> deleteStoreUrl(String storeName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$storeName');
  }

  // 取得所有已儲存的來源名稱
  static Future<List<String>> getAllStoreNames() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final storeNames = <String>[];
    
    for (final key in keys) {
      if (key.startsWith(_prefix)) {
        final storeName = key.substring(_prefix.length);
        storeNames.add(storeName);
      }
    }
    
    return storeNames;
  }

  // 取得所有來源和對應的 URL
  static Future<Map<String, String>> getAllStoreUrls() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final storeUrls = <String, String>{};
    
    for (final key in keys) {
      if (key.startsWith(_prefix)) {
        final storeName = key.substring(_prefix.length);
        final url = prefs.getString(key);
        if (url != null) {
          storeUrls[storeName] = url;
        }
      }
    }
    
    return storeUrls;
  }
}

