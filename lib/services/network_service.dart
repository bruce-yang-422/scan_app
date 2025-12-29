import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

// 網路狀態檢查服務
class NetworkService {
  // 檢查是否有網路連線（手機網路或 WiFi）
  static Future<bool> hasNetworkConnection() async {
    try {
      final ConnectivityResult connectivityResult = await Connectivity().checkConnectivity();
      
      // 檢查是否有任何網路連線（WiFi、行動網路、乙太網路）
      return connectivityResult == ConnectivityResult.mobile ||
          connectivityResult == ConnectivityResult.wifi ||
          connectivityResult == ConnectivityResult.ethernet;
    } catch (e) {
      debugPrint('檢查網路狀態時發生錯誤：$e');
      // 如果檢查失敗，預設返回 false（較安全）
      return false;
    }
  }

  // 取得網路連線類型描述
  static Future<String> getNetworkTypeDescription() async {
    try {
      final ConnectivityResult connectivityResult = await Connectivity().checkConnectivity();
      
      switch (connectivityResult) {
        case ConnectivityResult.wifi:
          return 'WiFi';
        case ConnectivityResult.mobile:
          return '行動網路';
        case ConnectivityResult.ethernet:
          return '乙太網路';
        case ConnectivityResult.none:
        default:
          return '無網路';
      }
    } catch (e) {
      debugPrint('取得網路類型時發生錯誤：$e');
      return '未知';
    }
  }
}
