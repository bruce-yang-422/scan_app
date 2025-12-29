import 'package:ntp/ntp.dart';

// NTP 時間同步服務
class NtpService {
  // 從 NTP 伺服器取得標準時間
  static Future<DateTime> getNetworkTime() async {
    try {
      // 使用預設的 NTP 伺服器池
      final ntpTime = await NTP.now();
      return ntpTime;
    } catch (e) {
      // 如果 NTP 同步失敗，返回本地 UTC 時間
      return DateTime.now().toUtc();
    }
  }

  // 取得本地時間與 NTP 時間的差異（秒）
  static Future<Duration> getTimeOffset() async {
    try {
      final localTime = DateTime.now();
      final ntpTime = await getNetworkTime();
      return ntpTime.difference(localTime);
    } catch (e) {
      return Duration.zero;
    }
  }
}

