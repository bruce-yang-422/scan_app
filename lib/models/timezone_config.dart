// 時區設定模型
class TimezoneConfig {
  final int offsetHours; // 時區偏移（小時），例如 +8
  final String name;     // 時區名稱，例如 "台北"

  const TimezoneConfig({
    required this.offsetHours,
    required this.name,
  });

  // 取得時區偏移的 Duration
  Duration get offset => Duration(hours: offsetHours);

  // 取得時區顯示名稱（例如：UTC+8 台北）
  String get displayName => 'UTC${offsetHours >= 0 ? '+' : ''}$offsetHours $name';

  // 轉換為 Map（用於 SharedPreferences）
  Map<String, dynamic> toMap() {
    return {
      'offset_hours': offsetHours,
      'name': name,
    };
  }

  // 從 Map 建立（從 SharedPreferences）
  factory TimezoneConfig.fromMap(Map<String, dynamic> map) {
    return TimezoneConfig(
      offsetHours: map['offset_hours'] as int,
      name: map['name'] as String,
    );
  }

  // 預設時區（UTC+8 台北）
  static const TimezoneConfig defaultTimezone = TimezoneConfig(
    offsetHours: 8,
    name: '台北',
  );

  // 常用時區列表
  static const List<TimezoneConfig> commonTimezones = [
    TimezoneConfig(offsetHours: 8, name: '台北'),
    TimezoneConfig(offsetHours: 8, name: '香港'),
    TimezoneConfig(offsetHours: 8, name: '新加坡'),
    TimezoneConfig(offsetHours: 9, name: '東京'),
    TimezoneConfig(offsetHours: 0, name: '倫敦'),
    TimezoneConfig(offsetHours: -5, name: '紐約'),
    TimezoneConfig(offsetHours: -8, name: '洛杉磯'),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimezoneConfig &&
          runtimeType == other.runtimeType &&
          offsetHours == other.offsetHours &&
          name == other.name;

  @override
  int get hashCode => offsetHours.hashCode ^ name.hashCode;
}

